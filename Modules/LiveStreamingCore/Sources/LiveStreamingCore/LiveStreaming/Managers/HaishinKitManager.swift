import AVFoundation
import Accelerate
import Combine
import CoreImage
import Foundation
import HaishinKit
import Network
import UIKit
import VideoToolbox
import os.log

/// 오디오 품질 레벨
enum AudioQualityLevel: String {
  case low = "low"
  case standard = "standard"
  case high = "high"

  var displayName: String {
    switch self {
    case .low: return NSLocalizedString("haishinkit_quality_low", comment: "저품질")
    case .standard: return NSLocalizedString("haishinkit_quality_standard", comment: "표준")
    case .high: return NSLocalizedString("haishinkit_quality_high", comment: "고품질")
    }
  }
}

// MARK: - 스트리밍 진단 보고서 구조체들

/// 종합 진단 보고서
public struct StreamingDiagnosisReport {
  var configValidation = ConfigValidationResult()
  var mediaMixerStatus = MediaMixerValidationResult()
  var rtmpStreamStatus = RTMPStreamValidationResult()
  var screenCaptureStatus = ScreenCaptureValidationResult()
  var networkStatus = NetworkValidationResult()
  var deviceStatus = DeviceValidationResult()
  var dataFlowStatus = DataFlowValidationResult()

  var overallScore: Int = 0
  var overallGrade: String = "F"

  mutating func calculateOverallScore() {
    let results = [
      configValidation.isValid,
      mediaMixerStatus.isValid,
      rtmpStreamStatus.isValid,
      screenCaptureStatus.isValid,
      networkStatus.isValid,
      deviceStatus.isValid,
      dataFlowStatus.isValid,
    ]

    let passedCount = results.filter { $0 }.count
    overallScore = Int((Double(passedCount) / Double(results.count)) * 100)

    switch overallScore {
    case 90...100: overallGrade = "A"
    case 80...89: overallGrade = "B"
    case 70...79: overallGrade = "C"
    case 60...69: overallGrade = "D"
    default: overallGrade = "F"
    }
  }

  func getRecommendation() -> String {
    switch overallGrade {
    case "A":
      return NSLocalizedString("diagnosis_recommendation_a", comment: "스트리밍 환경이 완벽합니다")
    case "B":
      return NSLocalizedString("diagnosis_recommendation_b", comment: "스트리밍 환경이 양호합니다")
    case "C":
      return NSLocalizedString(
        "diagnosis_recommendation_c", comment: "스트리밍이 가능하지만 안정성에 문제가 있을 수 있습니다")
    case "D":
      return NSLocalizedString("diagnosis_recommendation_d", comment: "스트리밍에 심각한 문제가 있습니다")
    default:
      return NSLocalizedString("diagnosis_recommendation_f", comment: "스트리밍이 불가능한 상태입니다")
    }
  }
}

/// 설정 검증 결과
public struct ConfigValidationResult {
  var isValid: Bool = true
  var validItems: [String] = []
  var issues: [String] = []
  var summary: String = ""
}

/// MediaMixer 검증 결과
public struct MediaMixerValidationResult {
  var isValid: Bool = true
  var validItems: [String] = []
  var issues: [String] = []
  var summary: String = ""
}

/// RTMPStream 검증 결과
public struct RTMPStreamValidationResult {
  var isValid: Bool = true
  var validItems: [String] = []
  var issues: [String] = []
  var summary: String = ""
}

/// 화면 캡처 검증 결과
public struct ScreenCaptureValidationResult {
  var isValid: Bool = true
  var validItems: [String] = []
  var issues: [String] = []
  var summary: String = ""
}

/// 네트워크 검증 결과
public struct NetworkValidationResult {
  var isValid: Bool = true
  var validItems: [String] = []
  var issues: [String] = []
  var summary: String = ""
}

/// 디바이스 검증 결과
public struct DeviceValidationResult {
  var isValid: Bool = true
  var validItems: [String] = []
  var issues: [String] = []
  var summary: String = ""
}

/// 데이터 흐름 검증 결과
public struct DataFlowValidationResult {
  var isValid: Bool = true
  var validItems: [String] = []
  var issues: [String] = []
  var summary: String = ""
}

// MARK: - HaishinKit Manager Protocol

/// HaishinKit 매니저 프로토콜 (화면 캡처 스트리밍용)
public protocol HaishinKitManagerProtocol: AnyObject {
  /// 화면 캡처 스트리밍 시작
  func startScreenCaptureStreaming(with settings: USBExternalCamera.LiveStreamSettings) async throws

  /// 스트리밍 중지
  func stopStreaming() async

  /// 연결 테스트
  func testConnection(to settings: USBExternalCamera.LiveStreamSettings) async
    -> ConnectionTestResult

  /// 현재 스트리밍 상태
  var isStreaming: Bool { get }

  /// 현재 스트리밍 상태 (상세)
  var currentStatus: LiveStreamStatus { get }

  /// 실시간 데이터 송출 통계
  var transmissionStats: DataTransmissionStats { get }

  /// 설정 로드
  func loadSettings() -> USBExternalCamera.LiveStreamSettings

  /// 설정 저장
  func saveSettings(_ settings: USBExternalCamera.LiveStreamSettings)

  /// RTMP 스트림 반환 (UI 미리보기용)
  func getRTMPStream() -> RTMPStream?
}

// MARK: - Stream Switcher (Examples 패턴 적용)

/// Examples의 HKStreamSwitcher 패턴을 적용한 스트림 관리자
final actor StreamSwitcher {
  var preference: StreamPreference?
  private(set) var connection: RTMPConnection?
  private(set) var stream: RTMPStream?

  // HaishinKitManager 참조 (약한 참조로 순환 참조 방지)
  private weak var haishinKitManager: HaishinKitManager?

  init(haishinKitManager: HaishinKitManager? = nil) {
    self.haishinKitManager = haishinKitManager
  }

  func setPreference(_ preference: StreamPreference) async {
    self.preference = preference
    let connection = RTMPConnection()

    self.connection = connection
    self.stream = RTMPStream(connection: connection)
  }

  func startStreaming() async throws {
    guard let preference = preference,
      let connection = connection,
      let stream = stream
    else {
      throw LiveStreamError.configurationError(
        NSLocalizedString("stream_settings_missing", comment: "스트림 설정이 없습니다"))
    }

    do {
      logInfo("RTMP 연결 시도: \(preference.rtmpURL)", category: .streaming)

      // RTMP 연결 (타임아웃 최적화: 15초 → 8초로 단축 - 빠른 연결)
      _ = try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          _ = try await connection.connect(preference.rtmpURL)
        }

        // 8초 타임아웃 설정 (ReplayKit 수준으로 빠르게)
        group.addTask {
          try await Task.sleep(nanoseconds: 8_000_000_000)  // 8초
          throw LiveStreamError.connectionTimeout
        }

        // 첫 번째 완료된 작업 반환
        try await group.next()!
      }

      logInfo("RTMP 연결 성공", category: .streaming)

      // 연결 안정화를 위한 대기 (최적화: 0.3초 → 0.1초로 단축)
      try await Task.sleep(nanoseconds: 100_000_000)  // 0.1초 대기

      // 🔍 스트림 키 상세 검증 및 정제
      let cleanedStreamKey =
        await haishinKitManager?.cleanAndValidateStreamKey(preference.streamKey)
        ?? preference.streamKey
      logInfo("스트리밍 퍼블리시 시도:", category: .streaming)
      logDebug("원본 스트림 키 길이: \(preference.streamKey.count)자", category: .streaming)
      logDebug("정제된 스트림 키 길이: \(cleanedStreamKey.count)자", category: .streaming)
      logDebug("스트림 키: [보안상 출력하지 않음]", category: .streaming)

      // 스트리밍 시작 (publish) - 타임아웃 최적화: 12초 → 6초
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          _ = try await stream.publish(cleanedStreamKey)
        }

        // 6초 타임아웃 설정 (초고속 연결)
        group.addTask {
          try await Task.sleep(nanoseconds: 6_000_000_000)  // 6초
          throw LiveStreamError.connectionTimeout
        }

        // 첫 번째 완료된 작업 반환
        try await group.next()!
      }

      logInfo("스트리밍 퍼블리시 성공", category: .streaming)

      // 퍼블리시 후 연결 상태 재확인 (최적화: 1초 → 0.2초로 단축)
      try await Task.sleep(nanoseconds: 200_000_000)  // 0.2초 대기 (초고속)

      let isActuallyConnected = await connection.connected
      if !isActuallyConnected {
        logError("퍼블리시 후 연결 상태 확인 실패 - 실제로는 연결되지 않음", category: .streaming)
        throw LiveStreamError.streamingFailed(
          NSLocalizedString("rtmp_server_rejected", comment: "RTMP 서버에서 연결을 거부했습니다"))
      }

      logInfo("최종 연결 상태 확인 완료 - 실제 스트리밍 시작됨", category: .streaming)

    } catch {
      logError("스트리밍 실패: \(error)", category: .streaming)

      // 더 구체적인 오류 메시지 제공
      let errorMessage: String
      if error is CancellationError {
        errorMessage = NSLocalizedString(
          "connection_timeout_check_network", comment: "연결 타임아웃 - 네트워크 상태를 확인해주세요")
      } else if let liveStreamError = error as? LiveStreamError {
        switch liveStreamError {
        case .connectionTimeout:
          errorMessage = NSLocalizedString(
            "connection_timeout_rtmp_server", comment: "연결 시간 초과 - RTMP 서버 응답이 없습니다")
        default:
          errorMessage = liveStreamError.localizedDescription
        }
      } else if let rtmpError = error as? RTMPStream.Error {
        // HaishinKit RTMP 스트림 오류 구체적 처리
        let errorDescription = rtmpError.localizedDescription
        if errorDescription.contains("2") || errorDescription.contains("publish") {
          errorMessage = NSLocalizedString("stream_key_auth_failed", comment: "스트림 키 인증 실패")
        } else if errorDescription.contains("1") || errorDescription.contains("connect") {
          errorMessage = NSLocalizedString(
            "rtmp_server_connection_failed", comment: "RTMP 서버 연결 실패")
        } else {
          errorMessage = String(
            format: NSLocalizedString("rtmp_streaming_error", comment: "RTMP 스트리밍 오류"),
            errorDescription)
        }
      } else {
        errorMessage = String(
          format: NSLocalizedString("network_error", comment: "네트워크 오류"), error.localizedDescription
        )
      }

      throw LiveStreamError.streamingFailed(
        String(
          format: NSLocalizedString("streaming_connection_failed", comment: "스트리밍 연결 실패"),
          errorMessage))
    }
  }

  func stopStreaming() async {
    guard let connection = connection,
      let stream = stream
    else { return }

    do {
      // 스트림 중지
      _ = try await stream.close()

      // 연결 중지
      _ = try await connection.close()
      logInfo("RTMP 연결 종료됨", category: .streaming)
    } catch {
      logWarning("연결 종료 중 오류: \(error)", category: .streaming)
    }
  }

}

// MARK: - Stream Preference

/// 스트림 설정 구조체
struct StreamPreference {
  let rtmpURL: String
  let streamKey: String
}

// MARK: - HaishinKit Manager Implementation

/// **Examples 패턴을 적용한 HaishinKit RTMP 스트리밍 매니저**
@MainActor
public class HaishinKitManager: NSObject, @preconcurrency HaishinKitManagerProtocol,
  ObservableObject, CameraFrameDelegate
{

  // MARK: - Properties

  /// 스트리밍 로거
  let logger = StreamingLogger.shared

  /// **MediaMixer (Examples 패턴)**
  lazy var mixer = MediaMixer(
    multiCamSessionEnabled: false, multiTrackAudioMixingEnabled: false, useManualCapture: true)

  /// MediaMixer 인스턴스 저장 용도
  var mediaMixer: MediaMixer?

  /// **StreamSwitcher (Examples 패턴)**
  lazy var streamSwitcher = StreamSwitcher(haishinKitManager: self)

  /// VideoCodec 워크어라운드 매니저 (VideoCodec -12902 에러 해결)
  lazy var videoCodecWorkaround = VideoCodecWorkaroundManager()

  /// 성능 최적화 매니저
  lazy var performanceOptimizer = PerformanceOptimizationManager()

  /// 🔧 개선: VideoToolbox 진단 및 설정 프리셋 지원
  var videoToolboxPreset: VideoToolboxPreset = .balanced
  var videoToolboxDiagnostics: VideoToolboxDiagnostics?

  /// 사용자가 원래 설정한 값들 (덮어쓰기 방지용)
  var originalUserSettings: USBExternalCamera.LiveStreamSettings?

  /// 적응형 품질 조정 활성화 여부 (사용자 선택)
  @Published public internal(set) var adaptiveQualityEnabled: Bool = false

  /// 적응형 품질 조정 활성화/비활성화 (사용자 제어)
  public func setAdaptiveQualityEnabled(_ enabled: Bool) {
    adaptiveQualityEnabled = enabled
    logger.info("🎛️ 적응형 품질 조정 \(enabled ? "활성화" : "비활성화")됨", category: .streaming)

    if !enabled {
      logger.info("🔒 사용자 설정이 보장됩니다 - 자동 품질 조정 없음", category: .streaming)
    }
  }

  /// 현재 스트리밍 중 여부
  @MainActor public internal(set) var isStreaming = false

  /// 화면 캡처 모드 여부 (카메라 대신 manual frame 사용)
  @Published public internal(set) var isScreenCaptureMode: Bool = false

  /// 현재 스트리밍 상태
  @Published public internal(set) var currentStatus: LiveStreamStatus = .idle

  /// 연결 상태 메시지
  @Published public internal(set) var connectionStatus: String = NSLocalizedString(
    "connection_status_ready", comment: "준비됨")

  /// 실시간 데이터 송출 통계
  @Published public internal(set) var transmissionStats: DataTransmissionStats =
    DataTransmissionStats()

  /// 텍스트 오버레이 표시 여부
  @Published public var showTextOverlay: Bool = false

  /// 텍스트 오버레이 설정
  @Published public var textOverlaySettings: TextOverlaySettings = TextOverlaySettings()

  /// 현재 스트리밍 설정
  var currentSettings: USBExternalCamera.LiveStreamSettings?

  /// 현재 RTMPStream 참조 (UI 미리보기용)
  var currentRTMPStream: RTMPStream?

  /// 데이터 모니터링 타이머
  var dataMonitoringTimer: Timer?

  /// 프레임 카운터
  var frameCounter: Int = 0
  var bytesSentCounter: Int64 = 0

  /// 네트워크 모니터
  var networkMonitor: NWPathMonitor?
  var networkQueue = DispatchQueue(label: "NetworkMonitor")

  /// Connection health monitoring
  var lastConnectionCheck = Date()
  var connectionFailureCount = 0
  let maxConnectionFailures = 5  // 3 → 5로 증가 (덜 민감하게)

  /// Connection health monitoring timer
  var connectionHealthTimer: Timer?

  /// 재연결 시도 횟수
  var reconnectAttempts: Int = 0
  let maxReconnectAttempts: Int = 2  // 3 → 2로 감소 (YouTube Live는 수동 재시작이 효과적)

  /// 재연결 백오프 지연시간 (초)
  var reconnectDelay: Double = 8.0  // 15.0 → 8.0으로 단축 (빠른 재연결)
  let maxReconnectDelay: Double = 25.0  // 45.0 → 25.0으로 단축

  /// 화면 캡처 전용 스트리밍 시작
  /// CameraPreviewUIView를 30fps로 캡처하여 송출
  var captureTimer: Timer?

  /// 화면 캡처 관련 통계
  var screenCaptureStats = ScreenCaptureStats()

  /// 프레임 전송 통계 추적
  var frameTransmissionCount = 0
  var frameTransmissionSuccess = 0
  var frameTransmissionFailure = 0
  var frameStatsStartTime = CACurrentMediaTime()
  var lastFrameTime = CACurrentMediaTime()

  // MARK: - Initialization

  public override init() {
    super.init()
    setupNetworkMonitoring()
    logger.info("🏭 **Examples 패턴 HaishinKit 매니저** 초기화됨", category: .system)
  }

  deinit {
    dataMonitoringTimer?.invalidate()
    dataMonitoringTimer = nil
    networkMonitor?.cancel()
    logger.info("🏭 HaishinKit 매니저 해제됨", category: .system)
  }

  // MARK: - Setup Methods

  /// 네트워크 모니터링 설정
  func setupNetworkMonitoring() {
    networkMonitor = NWPathMonitor()
    networkMonitor?.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        self?.updateNetworkQuality(from: path)
      }
    }
    networkMonitor?.start(queue: networkQueue)
    logger.info("📡 네트워크 모니터링 시작됨", category: .system)
  }

  /// 네트워크 품질 업데이트
  func updateNetworkQuality(from path: NWPath) {
    let quality: NetworkTransmissionQuality

    if path.status == .satisfied {
      if path.isExpensive {
        quality = .fair  // 셀룰러 연결
      } else if path.usesInterfaceType(.wifi) {
        quality = .good
      } else if path.usesInterfaceType(.wiredEthernet) {
        quality = .excellent
      } else {
        quality = .good
      }
    } else {
      quality = .poor
    }

    transmissionStats.connectionQuality = quality
    logger.debug("📶 네트워크 품질 업데이트: \(quality.description)", category: .connection)
  }

  // MARK: - 기존 일반 스트리밍 메서드들 제거 - 화면 캡처 스트리밍만 사용

  /// **Examples 패턴을 적용한 스트리밍 중지**
  public func stopStreaming() async {
    logger.info("🛑 **Examples 패턴** 스트리밍 중지 요청")

    // 1. 스트리밍 중지
    await streamSwitcher.stopStreaming()

    // 2. Examples 패턴: MediaMixer 정리
    cleanupMediaMixer()

    // 3. 기존 MediaMixer 중지
    await mixer.stopRunning()

    // 4. 카메라/오디오 해제
    try? await mixer.attachAudio(nil, track: 0)  // 오디오 해제

    // 4. 모니터링 중지
    stopDataMonitoring()
    stopConnectionHealthMonitoring()

    // 5. 상태 업데이트
    isStreaming = false
    isScreenCaptureMode = false  // 화면 캡처 모드 해제
    currentStatus = .idle
    connectionStatus = NSLocalizedString("connection_status_streaming_stopped", comment: "스트리밍 중지됨")
    currentRTMPStream = nil  // 스트림 참조 해제

    logger.info("✅ **Examples 패턴** 스트리밍 중지 완료")
  }

  // 기존 일반 스트리밍용 카메라/오디오 설정 메서드들 제거 - 화면 캡처 스트리밍만 사용
}
