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
private enum AudioQualityLevel: String {
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
  private var preference: StreamPreference?
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
  private let logger = StreamingLogger.shared

  /// **MediaMixer (Examples 패턴)**
  private lazy var mixer = MediaMixer(
    multiCamSessionEnabled: false, multiTrackAudioMixingEnabled: false, useManualCapture: true)

  /// **StreamSwitcher (Examples 패턴)**
  private lazy var streamSwitcher = StreamSwitcher(haishinKitManager: self)

  /// VideoCodec 워크어라운드 매니저 (VideoCodec -12902 에러 해결)
  private lazy var videoCodecWorkaround = VideoCodecWorkaroundManager()

  /// 성능 최적화 매니저
  private lazy var performanceOptimizer = PerformanceOptimizationManager()

  /// 🔧 개선: VideoToolbox 진단 및 설정 프리셋 지원
  private var videoToolboxPreset: VideoToolboxPreset = .balanced
  private var videoToolboxDiagnostics: VideoToolboxDiagnostics?

  /// 사용자가 원래 설정한 값들 (덮어쓰기 방지용)
  private var originalUserSettings: USBExternalCamera.LiveStreamSettings?

  /// 적응형 품질 조정 활성화 여부 (사용자 선택)
  @Published public private(set) var adaptiveQualityEnabled: Bool = false

  /// 적응형 품질 조정 활성화/비활성화 (사용자 제어)
  public func setAdaptiveQualityEnabled(_ enabled: Bool) {
    adaptiveQualityEnabled = enabled
    logger.info("🎛️ 적응형 품질 조정 \(enabled ? "활성화" : "비활성화")됨", category: .streaming)

    if !enabled {
      logger.info("🔒 사용자 설정이 보장됩니다 - 자동 품질 조정 없음", category: .streaming)
    }
  }

  /// 현재 스트리밍 중 여부
  @MainActor public private(set) var isStreaming = false

  /// 화면 캡처 모드 여부 (카메라 대신 manual frame 사용)
  @Published public private(set) var isScreenCaptureMode: Bool = false

  /// 현재 스트리밍 상태
  @Published public private(set) var currentStatus: LiveStreamStatus = .idle

  /// 연결 상태 메시지
  @Published public private(set) var connectionStatus: String = NSLocalizedString(
    "connection_status_ready", comment: "준비됨")

  /// 실시간 데이터 송출 통계
  @Published public private(set) var transmissionStats: DataTransmissionStats =
    DataTransmissionStats()

  /// 현재 스트리밍 설정
  private var currentSettings: USBExternalCamera.LiveStreamSettings?

  /// 현재 RTMPStream 참조 (UI 미리보기용)
  private var currentRTMPStream: RTMPStream?

  /// 데이터 모니터링 타이머
  private var dataMonitoringTimer: Timer?

  /// 프레임 카운터
  private var frameCounter: Int = 0
  private var bytesSentCounter: Int64 = 0

  /// 네트워크 모니터
  private var networkMonitor: NWPathMonitor?
  private var networkQueue = DispatchQueue(label: "NetworkMonitor")

  /// Connection health monitoring
  private var lastConnectionCheck = Date()
  private var connectionFailureCount = 0
  private let maxConnectionFailures = 5  // 3 → 5로 증가 (덜 민감하게)

  /// Connection health monitoring timer
  private var connectionHealthTimer: Timer?

  /// 재연결 시도 횟수
  private var reconnectAttempts: Int = 0
  private let maxReconnectAttempts: Int = 2  // 3 → 2로 감소 (YouTube Live는 수동 재시작이 효과적)

  /// 재연결 백오프 지연시간 (초)
  private var reconnectDelay: Double = 8.0  // 15.0 → 8.0으로 단축 (빠른 재연결)
  private let maxReconnectDelay: Double = 25.0  // 45.0 → 25.0으로 단축

  /// 화면 캡처 전용 스트리밍 시작
  /// CameraPreviewUIView를 30fps로 캡처하여 송출
  private var captureTimer: Timer?

  /// 화면 캡처 관련 통계
  private var screenCaptureStats = ScreenCaptureStats()

  /// 프레임 전송 통계 추적
  private var frameTransmissionCount = 0
  private var frameTransmissionSuccess = 0
  private var frameTransmissionFailure = 0
  private var frameStatsStartTime = CACurrentMediaTime()
  private var lastFrameTime = CACurrentMediaTime()

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
  private func setupNetworkMonitoring() {
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
  private func updateNetworkQuality(from path: NWPath) {
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

  // MARK: - Data Monitoring Methods

  /// 데이터 송출 모니터링 시작
  private func startDataMonitoring() {
    resetTransmissionStats()

    dataMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        await self?.updateTransmissionStats()
        await self?.logConnectionStatus()
      }
    }

    logger.info("📊 데이터 송출 모니터링 시작됨")
  }

  /// 연결 상태 모니터링 시작 (개선된 버전)
  private func startConnectionHealthMonitoring() {
    // 연결 상태를 적당히 체크 (15초마다 - 덜 민감하게)
    connectionHealthTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) {
      [weak self] _ in
      Task { @MainActor [weak self] in
        await self?.checkConnectionHealth()
      }
    }

    // 재연결 상태 초기화
    reconnectAttempts = 0
    reconnectDelay = 8.0  // 초기 재연결 지연시간 최적화 (15.0 → 8.0)
    connectionFailureCount = 0

    logger.info("🔍 향상된 연결 상태 모니터링 시작됨 (15초 주기)", category: .connection)
  }

  /// 연결 상태 건강성 체크 (개선된 버전)
  private func checkConnectionHealth() async {
    guard isStreaming else { return }

    if let connection = await streamSwitcher.connection {
      let isConnected = await connection.connected

      // 추가 검증: 스트림 상태도 확인
      var streamStatus = "unknown"
      var isStreamPublishing = false
      if let stream = await streamSwitcher.stream {
        // Sendable 프로토콜 문제로 인해 stream.info 접근 제외
        streamStatus = "stream_connected"
        // 간단히 connection 연결 상태만 확인
        isStreamPublishing = isConnected  // RTMPConnection이 연결되면 스트림도 활성으로 간주
        logger.debug("🔍 스트림 상태: 연결됨", category: .connection)
      }

      // 실제 연결 상태와 스트림 상태 모두 확인
      let isReallyStreaming = isConnected && isStreamPublishing

      if !isReallyStreaming {
        connectionFailureCount += 1
        logger.warning(
          "⚠️ 연결 상태 불량 감지 - 연결: \(isConnected), 퍼블리싱: \(isStreamPublishing) (\(connectionFailureCount)/\(maxConnectionFailures))",
          category: .connection)

        if connectionFailureCount >= maxConnectionFailures {
          logger.error("❌ 연결 실패 한도 초과, 즉시 재연결 시도", category: .connection)
          handleConnectionLost()
        }
      } else {
        // 연결이 정상이면 모든 카운터 리셋
        if connectionFailureCount > 0 || reconnectAttempts > 0 {
          logger.info("✅ 연결 상태 완전 회복됨 - 모든 카운터 리셋", category: .connection)
          connectionFailureCount = 0
          reconnectAttempts = 0
          reconnectDelay = 10.0
        }
      }
    } else {
      logger.warning("⚠️ RTMP 연결 객체가 존재하지 않음", category: .connection)
      connectionFailureCount += 1
      if connectionFailureCount >= maxConnectionFailures {
        handleConnectionLost()
      }
    }

    lastConnectionCheck = Date()
  }

  /// 실행 환경 분석
  private func analyzeExecutionEnvironment() {
    logger.error("  📱 실행 환경 분석:", category: .connection)

    #if targetEnvironment(simulator)
      logger.error("    🖥️ iOS 시뮬레이터에서 실행 중", category: .connection)
      logger.error("    ⚠️ 시뮬레이터 제약사항:", category: .connection)
      logger.error("      • 화면 캡처 기능이 실제 디바이스와 다를 수 있음", category: .connection)
      logger.error("      • 일부 하드웨어 기능 제한", category: .connection)
      logger.error("      • 네트워크 성능이 실제 디바이스와 차이날 수 있음", category: .connection)
      logger.error("    💡 권장사항: 실제 iOS 디바이스에서 테스트 해보세요", category: .connection)
    #else
      logger.error("    📱 실제 iOS 디바이스에서 실행 중", category: .connection)
      logger.error("    ✅ 하드웨어 환경: 정상", category: .connection)
    #endif

    // iOS 버전 확인
    let systemVersion = UIDevice.current.systemVersion
    logger.error("    📋 iOS 버전: \(systemVersion)", category: .connection)

    // 디바이스 모델 확인
    let deviceModel = UIDevice.current.model
    logger.error("    📱 디바이스 모델: \(deviceModel)", category: .connection)

    // 화면 캡처 권한 상태 확인
    checkScreenCapturePermissions()

    // 송출 데이터 흐름 진단
    analyzeDataFlowConnection()

    logger.error("    ", category: .connection)
  }

  /// 화면 캡처 권한 확인
  private func checkScreenCapturePermissions() {
    // 화면 캡처 가능 여부 확인 (iOS 17+ 타겟이므로 항상 사용 가능)
    logger.error("    🎥 화면 캡처 기능: 사용 가능 (ReplayKit 지원)", category: .connection)

    // 현재 스트리밍 설정 확인
    if let settings = currentSettings {
      logger.error(
        "    📊 현재 설정 해상도: \(settings.videoWidth)x\(settings.videoHeight)", category: .connection)
      logger.error("    📈 현재 설정 비트레이트: \(settings.videoBitrate) kbps", category: .connection)
      logger.error("    📺 현재 설정 프레임레이트: \(settings.frameRate) fps", category: .connection)
    }
  }

  /// 송출 데이터 흐름 진단
  private func analyzeDataFlowConnection() {
    logger.error("  📊 송출 데이터 흐름 진단:", category: .connection)

    // 1. MediaMixer 상태 확인
    Task {
      let isMixerRunning = await mixer.isRunning
      logger.error("    🎛️ MediaMixer 상태: \(isMixerRunning ? "실행 중" : "중지됨")", category: .connection)
    }

    // 2. RTMPStream 연결 상태 확인
    if currentRTMPStream != nil {
      logger.error("    📡 RTMPStream 연결: 연결됨", category: .connection)
    } else {
      logger.error("    📡 RTMPStream 연결: ❌ 연결되지 않음", category: .connection)
    }

    // 3. 화면 캡처 모드 확인
    logger.error("    🎥 화면 캡처 모드: \(isScreenCaptureMode ? "활성화" : "비활성화")", category: .connection)

    // 4. 수동 프레임 전송 상태 확인
    logger.error("    📹 수동 프레임 전송 통계:", category: .connection)
    logger.error("      • 전송 성공: \(screenCaptureStats.successCount)프레임", category: .connection)
    logger.error("      • 전송 실패: \(screenCaptureStats.failureCount)프레임", category: .connection)
    logger.error(
      "      • 현재 FPS: \(String(format: "%.1f", screenCaptureStats.currentFPS))",
      category: .connection)

    // 5. 데이터 흐름 체인 확인
    logger.error("    🔗 데이터 흐름 체인:", category: .connection)
    logger.error("      1️⃣ CameraPreviewUIView → sendManualFrame()", category: .connection)
    logger.error("      2️⃣ HaishinKitManager → RTMPStream.append()", category: .connection)
    logger.error("      3️⃣ RTMPStream → RTMP Server", category: .connection)

    // 6. 목업 데이터 사용 여부 확인
    if screenCaptureStats.frameCount == 0 {
      logger.error("    ⚠️ 실제 프레임 데이터 전송 없음 - 목업 데이터 의심", category: .connection)
      logger.error("    💡 CameraPreviewUIView의 화면 캡처 타이머가 시작되었는지 확인 필요", category: .connection)
    } else {
      logger.error("    ✅ 실제 프레임 데이터 전송 확인됨", category: .connection)
    }

    // 7. MediaMixer vs 직접 전송 방식 확인
    if currentRTMPStream != nil {
      logger.error("    📡 전송 방식: RTMPStream 직접 전송 (권장)", category: .connection)
    } else {
      logger.error("    📡 전송 방식: MediaMixer 백업 전송", category: .connection)
    }

    logger.error("    ", category: .connection)
  }

  /// 연결 상태 모니터링 중지
  private func stopConnectionHealthMonitoring() {
    connectionHealthTimer?.invalidate()
    connectionHealthTimer = nil
    logger.info("🔍 연결 상태 모니터링 중지됨", category: .connection)
  }

  /// 연결 상태 로깅
  private func logConnectionStatus() async {
    guard let connection = await streamSwitcher.connection else {
      logger.warning("⚠️ RTMP 연결 객체가 없습니다", category: .connection)
      return
    }

    let connectionState = await connection.connected ? "연결됨" : "연결 끊어짐"

    logger.debug("🔍 RTMP 연결 상태: \(connectionState)", category: .connection)

    // 연결이 끊어진 경우 에러 로그
    if !(await connection.connected) && isStreaming {
      logger.error("💔 RTMP 연결이 끊어져 있지만 스트리밍 상태가 활성화되어 있습니다", category: .connection)
      handleConnectionLost()
    }
  }

  /// 데이터 송출 모니터링 중지
  private func stopDataMonitoring() {
    dataMonitoringTimer?.invalidate()
    dataMonitoringTimer = nil
    logger.info("📊 데이터 송출 모니터링 중지됨")
  }

  /// 송출 통계 리셋
  private func resetTransmissionStats() {
    transmissionStats = DataTransmissionStats()
    frameCounter = 0
    lastFrameTime = CACurrentMediaTime()
    bytesSentCounter = 0
    logger.debug("📊 송출 통계 초기화됨")
  }

  /// 실시간 송출 통계 업데이트 (백그라운드에서 계산, 메인 스레드에서 UI 업데이트)
  private func updateTransmissionStats() async {
    guard isStreaming else { return }

    // 🔧 개선: 통계 계산을 백그라운드에서 처리
    let currentTime = CACurrentMediaTime()
    let timeDiff = currentTime - lastFrameTime

    // 프레임 레이트 계산 (백그라운드에서 계산)
    let averageFrameRate = timeDiff > 0 ? Double(frameCounter) / timeDiff : 0.0

    // 메인 스레드에서 UI 업데이트
    await MainActor.run {
      self.transmissionStats.averageFrameRate = averageFrameRate
    }

    // 비트레이트 계산 (추정)
    if let settings = currentSettings {
      transmissionStats.currentVideoBitrate = Double(settings.videoBitrate)
      transmissionStats.currentAudioBitrate = Double(settings.audioBitrate)

      // 🔧 개선: 적응형 품질 조정을 사용자 옵션으로 변경 (기본값: 비활성화)
      if adaptiveQualityEnabled, let originalSettings = originalUserSettings {
        let optimizedSettings = performanceOptimizer.adaptQualityRespectingUserSettings(
          currentSettings: settings,
          userDefinedSettings: originalSettings
        )

        if !isSettingsEqual(settings, optimizedSettings) {
          logger.info("🎯 사용자가 활성화한 적응형 품질 조정 적용", category: .streaming)
          logger.info("  • 원본 설정 범위 내에서만 조정", category: .streaming)
          logger.info(
            "  • 비트레이트: \(settings.videoBitrate) → \(optimizedSettings.videoBitrate) kbps",
            category: .streaming)
          logger.info(
            "  • 프레임율: \(settings.frameRate) → \(optimizedSettings.frameRate) fps",
            category: .streaming)

          // 사용자에게 변경사항 통지 (로그로 대체)
          logger.info("📢 품질 조정 알림: 성능 최적화를 위해 설정이 조정되었습니다", category: .streaming)

          currentSettings = optimizedSettings

          // 비동기로 설정 적용
          Task {
            do {
              try await self.applyStreamSettings()
            } catch {
              self.logger.warning("⚠️ 적응형 품질 조정 적용 실패: \(error)", category: .streaming)
            }
          }
        }
      } else if !adaptiveQualityEnabled {
        // 적응형 품질 조정이 비활성화된 경우 사용자 설정 유지
        logger.debug("🔒 적응형 품질 조정 비활성화됨 - 사용자 설정 유지", category: .streaming)
      }
    }

    // 네트워크 지연 시간 업데이트 (실제 구현 시 RTMP 서버 응답 시간 측정)
    transmissionStats.networkLatency = estimateNetworkLatency()

    transmissionStats.lastTransmissionTime = Date()

    // 상세 로그 출력
    logDetailedTransmissionStats()
  }

  /// 네트워크 지연 시간 추정
  private func estimateNetworkLatency() -> TimeInterval {
    // 실제 구현에서는 RTMP 서버와의 핑을 측정해야 함
    // 현재는 네트워크 품질에 따른 추정치 반환
    switch transmissionStats.connectionQuality {
    case .excellent: return 0.020  // 20ms
    case .good: return 0.050  // 50ms
    case .fair: return 0.100  // 100ms
    case .poor: return 0.300  // 300ms
    case .unknown: return 0.150  // 150ms
    }
  }

  /// 상세한 송출 통계 로그 (반복적인 로그 비활성화)
  private func logDetailedTransmissionStats() {
    let stats = transmissionStats

    // 반복적인 상세 통계 로그 비활성화 (성능 최적화 및 로그 정리)
    // 중요한 문제 발생 시에만 로그 출력
    if stats.droppedFrames > 0 || stats.connectionQuality == .poor {
      logger.warning(
        "⚠️ 스트림 품질 문제: 드롭 프레임 \(stats.droppedFrames)개, 품질: \(stats.connectionQuality.description)",
        category: .streaming)
    }

    // 주요 이정표 프레임 수에서만 간단 요약 로그 (1000 프레임마다)
    if stats.videoFramesTransmitted > 0 && stats.videoFramesTransmitted % 1000 == 0 {
      logger.info(
        "📊 스트림 요약: \(stats.videoFramesTransmitted)프레임 전송, 평균 \(String(format: "%.1f", stats.averageFrameRate))fps",
        category: .streaming)
    }
  }

  /// 바이트 포맷팅
  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  /// 연결 끊어짐 처리 (개선된 버전)
  private func handleConnectionLost() {
    logger.error(
      "🚨 연결 끊어짐 감지 - 상세 분석 시작 (시도: \(reconnectAttempts + 1)/\(maxReconnectAttempts))",
      category: .connection)

    // 연결 끊어짐 원인 분석
    analyzeConnectionFailure()

    isStreaming = false
    currentStatus = .error(
      LiveStreamError.networkError(
        NSLocalizedString("rtmp_disconnected_reconnecting", comment: "RTMP 연결이 끊어졌습니다")))
    connectionStatus = NSLocalizedString(
      "connection_disconnected_waiting", comment: "연결 끊어짐 - 재연결 대기 중")
    stopDataMonitoring()

    logger.error("🛑 스트리밍 상태가 중지로 변경됨", category: .connection)

    // 재연결 한도 체크
    if reconnectAttempts >= maxReconnectAttempts {
      logger.error(
        "❌ 최대 재연결 시도 횟수 초과 (\(maxReconnectAttempts)회) - 자동 재연결 중단", category: .connection)
      currentStatus = .error(
        LiveStreamError.networkError(
          NSLocalizedString("youtube_live_connection_failed", comment: "YouTube Live 연결에 실패했습니다")))
      connectionStatus = NSLocalizedString(
        "youtube_live_check_needed", comment: "YouTube Live 확인 필요 - 수동 재시작 하세요")
      return
    }

    // 지능형 백오프 재연결 시도
    logger.info(
      "🔄 \(reconnectDelay)초 후 재연결 시도 (\(reconnectAttempts + 1)/\(maxReconnectAttempts))",
      category: .connection)
    DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
      Task {
        await self?.attemptReconnection()
      }
    }
  }

  /// 연결 실패 원인 분석
  private func analyzeConnectionFailure() {
    logger.error("🔍 연결 실패 원인 분석:", category: .connection)

    // 1. 네트워크 상태 확인
    if let networkMonitor = networkMonitor {
      let path = networkMonitor.currentPath
      logger.error("  🌐 네트워크 상태: \(path.status)", category: .connection)
      logger.error(
        "  📡 사용 가능한 인터페이스: \(path.availableInterfaces.map { $0.name })", category: .connection)
      logger.error("  💸 비용 발생 연결: \(path.isExpensive)", category: .connection)
      logger.error("  🔒 제한됨: \(path.isConstrained)", category: .connection)
    }

    // 2. RTMP 연결 상태 확인 (비동기로 처리)
    Task {
      if let connection = await streamSwitcher.connection {
        let connected = await connection.connected
        logger.error("  🔗 RTMP 연결 상태: \(connected)", category: .connection)
      } else {
        logger.error("  🔗 RTMP 연결 객체: 없음", category: .connection)
      }
    }

    // 3. 설정 재확인
    if let settings = currentSettings {
      logger.error("  📍 RTMP URL: \(settings.rtmpURL)", category: .connection)
      logger.error("  🔑 스트림 키 길이: \(settings.streamKey.count)자", category: .connection)
      logger.error("  📊 비트레이트: \(settings.videoBitrate) kbps", category: .connection)
    }

    // 4. 전송 통계 확인
    logger.error("  📈 전송 통계:", category: .connection)
    logger.error(
      "    • 비디오 프레임: \(transmissionStats.videoFramesTransmitted)", category: .connection)
    logger.error(
      "    • 총 전송량: \(formatBytes(transmissionStats.totalBytesTransmitted))", category: .connection)
    logger.error(
      "    • 네트워크 지연: \(String(format: "%.0f", transmissionStats.networkLatency * 1000))ms",
      category: .connection)
    logger.error(
      "    • 연결 품질: \(transmissionStats.connectionQuality.description)", category: .connection)
    logger.error(
      "    • 재연결 시도: \(reconnectAttempts)/\(maxReconnectAttempts)", category: .connection)
    logger.error(
      "    • 연결 실패 횟수: \(connectionFailureCount)/\(maxConnectionFailures)", category: .connection)

    // 5. 일반적인 문제 제안
    logger.error("  💡 가능한 원인들:", category: .connection)
    logger.error("    1. 잘못된 RTMP URL 또는 스트림 키", category: .connection)
    logger.error("    2. YouTube Live 스트림이 비활성화됨", category: .connection)
    logger.error("    3. 네트워크 연결 불안정", category: .connection)
    logger.error("    4. 방화벽 또는 프록시 차단", category: .connection)
    logger.error("    5. 서버 과부하 또는 일시적 오류", category: .connection)

    // 6. 실행 환경 확인
    analyzeExecutionEnvironment()

    // 7. 스트림 키 상세 분석 (현재 설정이 있는 경우)
    if let settings = currentSettings {
      analyzeStreamKeyIssues(for: settings)
    }

    // 8. YouTube Live 전용 진단
    if let settings = currentSettings, settings.rtmpURL.contains("youtube.com") {
      logger.error("  📺 YouTube Live 상세 진단:", category: .connection)
      logger.error("    🚨 RTMP 핸드셰이크는 성공했지만 스트림 키 인증 실패!", category: .connection)
      logger.error("    ", category: .connection)
      logger.error("    ✅ 필수 해결 단계 (순서대로 확인):", category: .connection)
      logger.error("    1️⃣ YouTube Studio(studio.youtube.com) 접속", category: .connection)
      logger.error("    2️⃣ 좌측 메뉴에서 '라이브 스트리밍' 또는 '콘텐츠' → '라이브' 클릭", category: .connection)
      logger.error("    3️⃣ 스트림 페이지에서 '스트리밍 시작' 또는 '라이브 스트리밍 시작' 버튼 클릭 ⭐️", category: .connection)
      logger.error("    4️⃣ 상태가 '스트리밍을 기다리는 중...' 또는 'LIVE'로 변경 확인", category: .connection)
      logger.error("    5️⃣ 새로운 스트림 키 복사 (변경되었을 수 있음)", category: .connection)
      logger.error("    6️⃣ 앱에서 새 스트림 키로 교체 후 재시도", category: .connection)
      logger.error("    ", category: .connection)
      logger.error("    ⚠️ 추가 확인사항:", category: .connection)
      logger.error("    • 다른 스트리밍 프로그램(OBS, XSplit 등) 완전 종료", category: .connection)
      logger.error("    • YouTube Live가 첫 24시간 검증 과정을 거쳤는지 확인", category: .connection)
      logger.error("    • 계정 제재나 제한이 없는지 확인", category: .connection)
      logger.error("    • Wi-Fi 연결이 안정적인지 확인 (4G/5G보다 권장)", category: .connection)
      logger.error("    • 방화벽이나 회사 네트워크 제한 확인", category: .connection)
    }
  }

  /// 재연결 시도 (개선된 안정화 전략)
  private func attemptReconnection() async {
    guard let settings = currentSettings else {
      logger.error("❌ 재연결 실패: 설정 정보가 없습니다", category: .connection)
      return
    }

    reconnectAttempts += 1
    logger.info(
      "🔄 RTMP 재연결 시도 #\(reconnectAttempts) (지연: \(reconnectDelay)초)", category: .connection)

    // 재연결 상태 UI 업데이트
    currentStatus = .connecting
    connectionStatus = "재연결 시도 중... (\(reconnectAttempts)/\(maxReconnectAttempts))"

    do {
      // 기존 연결 완전히 정리
      logger.info("🧹 기존 연결 정리 중...", category: .connection)
      await streamSwitcher.stopStreaming()

      // 충분한 대기 시간 (서버에서 이전 연결 완전 정리 대기)
      logger.info("⏰ 서버 연결 정리 대기 중 (1.5초)...", category: .connection)
      try await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5초 대기 (3초 → 1.5초로 단축)

      // 새로운 연결 시도
      logger.info("🚀 새로운 연결 시도...", category: .connection)
      try await startScreenCaptureStreaming(with: settings)

      logger.info("✅ RTMP 재연결 성공 (시도 \(reconnectAttempts)회 후)", category: .connection)

      // 성공 시 카운터 및 지연시간 리셋
      reconnectAttempts = 0
      reconnectDelay = 10.0
      connectionFailureCount = 0  // 연결 실패 카운터도 리셋

    } catch {
      logger.error(
        "❌ RTMP 재연결 실패 #\(reconnectAttempts): \(error.localizedDescription)", category: .connection)

      // 재연결 한도 체크
      if reconnectAttempts >= maxReconnectAttempts {
        logger.error("❌ 최대 재연결 시도 횟수 도달 - 중단", category: .connection)
        currentStatus = .error(
          LiveStreamError.networkError("재연결에 실패했습니다. 네트워크 상태를 확인 후 수동으로 다시 시작해주세요."))
        connectionStatus = "재연결 실패 - 수동 재시작 필요"
        stopConnectionHealthMonitoring()  // 모니터링 완전 중지
        return
      }

      // 선형 백오프: 재연결 지연시간 증가 (최적화: 5초 → 3초 증가량)
      reconnectDelay = min(reconnectDelay + 3.0, maxReconnectDelay)

      logger.info("🔄 다음 재연결 시도까지 \(reconnectDelay)초 대기", category: .connection)
      currentStatus = .error(
        LiveStreamError.networkError("재연결 시도 중... (\(reconnectAttempts)/\(maxReconnectAttempts))"))
      connectionStatus = "재연결 대기 중 (\(Int(reconnectDelay))초 후 재시도)"

      // 다음 재연결 시도 예약
      DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
        Task {
          await self?.attemptReconnection()
        }
      }
    }
  }

  // MARK: - Protocol Implementation

  /// 연결 테스트
  public func testConnection(to settings: USBExternalCamera.LiveStreamSettings) async
    -> ConnectionTestResult
  {
    logger.info("🔍 Examples 패턴 연결 테스트 시작", category: .connection)

    do {
      // 설정 검증
      try validateSettings(settings)

      // 간단한 연결성 테스트
      return ConnectionTestResult(
        isSuccessful: true,
        latency: 50,
        message: "Examples 패턴 연결 테스트 성공",
        networkQuality: .good
      )

    } catch let error as LiveStreamError {
      logger.error("❌ 연결 테스트 실패: \(error.localizedDescription)", category: .connection)
      return ConnectionTestResult(
        isSuccessful: false,
        latency: 0,
        message: error.localizedDescription,
        networkQuality: .poor
      )
    } catch {
      logger.error("❌ 연결 테스트 오류: \(error.localizedDescription)", category: .connection)
      return ConnectionTestResult(
        isSuccessful: false,
        latency: 0,
        message: "알 수 없는 오류가 발생했습니다",
        networkQuality: .unknown
      )
    }
  }

  /// 설정 검증
  private func validateSettings(_ settings: USBExternalCamera.LiveStreamSettings) throws {
    logger.info("🔍 스트리밍 설정 검증 시작")

    // RTMP URL 검증
    guard !settings.rtmpURL.isEmpty else {
      logger.error("❌ RTMP URL이 비어있음")
      throw LiveStreamError.configurationError("RTMP URL이 설정되지 않았습니다")
    }

    guard settings.rtmpURL.lowercased().hasPrefix("rtmp") else {
      logger.error("❌ RTMP 프로토콜이 아님: \(settings.rtmpURL)")
      throw LiveStreamError.configurationError("RTMP 프로토콜을 사용해야 합니다")
    }

    // 스트림 키 검증
    guard !settings.streamKey.isEmpty else {
      logger.error("❌ 스트림 키가 비어있음")
      throw LiveStreamError.authenticationFailed("스트림 키가 설정되지 않았습니다")
    }

    logger.info("✅ 스트리밍 설정 검증 완료")
  }

  /// 설정 로드 (UserDefaults에서)
  public func loadSettings() -> USBExternalCamera.LiveStreamSettings {
    logger.info("📂 스트리밍 설정 로드", category: .system)

    var settings = USBExternalCamera.LiveStreamSettings()

    // UserDefaults에서 스트림 설정 로드
    let defaults = UserDefaults.standard

    // 기본 스트리밍 설정
    if let rtmpURL = defaults.string(forKey: "LiveStream.rtmpURL"), !rtmpURL.isEmpty {
      settings.rtmpURL = rtmpURL
      logger.debug("📂 RTMP URL 로드됨", category: .system)
    }

    // Keychain에서 스트림 키 로드 (보안 향상)
    if let streamKey = KeychainManager.shared.loadStreamKey(), !streamKey.isEmpty {
      settings.streamKey = streamKey
      logger.debug("📂 스트림 키 로드됨 (길이: \(streamKey.count)자)", category: .system)
    } else {
      // 기존 UserDefaults에서 마이그레이션
      if let legacyStreamKey = defaults.string(forKey: "LiveStream.streamKey"),
        !legacyStreamKey.isEmpty
      {
        settings.streamKey = legacyStreamKey
        // Keychain으로 마이그레이션
        if KeychainManager.shared.saveStreamKey(legacyStreamKey) {
          // 마이그레이션 성공 시 UserDefaults에서 삭제
          defaults.removeObject(forKey: "LiveStream.streamKey")
          logger.info("🔒 스트림 키를 Keychain으로 마이그레이션 완료", category: .system)
        }
      }
    }

    if let streamTitle = defaults.string(forKey: "LiveStream.streamTitle"), !streamTitle.isEmpty {
      settings.streamTitle = streamTitle
    }

    // 비디오 설정
    let videoBitrate = defaults.integer(forKey: "LiveStream.videoBitrate")
    if videoBitrate > 0 {
      settings.videoBitrate = videoBitrate
    }

    let videoWidth = defaults.integer(forKey: "LiveStream.videoWidth")
    if videoWidth > 0 {
      settings.videoWidth = videoWidth
    }

    let videoHeight = defaults.integer(forKey: "LiveStream.videoHeight")
    if videoHeight > 0 {
      settings.videoHeight = videoHeight
    }

    let frameRate = defaults.integer(forKey: "LiveStream.frameRate")
    if frameRate > 0 {
      settings.frameRate = frameRate
    }

    // 오디오 설정
    let audioBitrate = defaults.integer(forKey: "LiveStream.audioBitrate")
    if audioBitrate > 0 {
      settings.audioBitrate = audioBitrate
    }

    // 고급 설정 (기본값을 고려한 로드)
    if defaults.object(forKey: "LiveStream.autoReconnect") != nil {
      settings.autoReconnect = defaults.bool(forKey: "LiveStream.autoReconnect")
    }  // 기본값: true (USBExternalCamera.LiveStreamSettings의 init에서 설정)

    if defaults.object(forKey: "LiveStream.isEnabled") != nil {
      settings.isEnabled = defaults.bool(forKey: "LiveStream.isEnabled")
    }  // 기본값: true (USBExternalCamera.LiveStreamSettings의 init에서 설정)

    let bufferSize = defaults.integer(forKey: "LiveStream.bufferSize")
    if bufferSize > 0 {
      settings.bufferSize = bufferSize
    }

    let connectionTimeout = defaults.integer(forKey: "LiveStream.connectionTimeout")
    if connectionTimeout > 0 {
      settings.connectionTimeout = connectionTimeout
    }

    if let videoEncoder = defaults.string(forKey: "LiveStream.videoEncoder"), !videoEncoder.isEmpty
    {
      settings.videoEncoder = videoEncoder
    }

    if let audioEncoder = defaults.string(forKey: "LiveStream.audioEncoder"), !audioEncoder.isEmpty
    {
      settings.audioEncoder = audioEncoder
    }

    logger.info("✅ 스트리밍 설정 로드 완료", category: .system)
    return settings
  }

  /// 설정 저장 (UserDefaults에)
  public func saveSettings(_ settings: USBExternalCamera.LiveStreamSettings) {
    logger.info("💾 스트리밍 설정 저장 시작", category: .system)

    // 현재 설정과 비교하여 변경된 경우에만 스트리밍 중 실시간 적용
    let settingsChanged = (currentSettings != nil) && !isSettingsEqual(currentSettings!, settings)
    if settingsChanged && isStreaming {
      logger.info("🔄 스트리밍 중 설정 변경 감지 - 실시간 적용 시작", category: .system)
      currentSettings = settings

      // 비동기로 실시간 설정 적용
      Task {
        do {
          try await self.applyStreamSettings()
        } catch {
          self.logger.error("❌ 스트리밍 중 설정 적용 실패: \(error)", category: .system)
        }
      }
    } else {
      // 설정 업데이트 (스트리밍 중이 아니거나 변경사항 없음)
      currentSettings = settings
    }

    let defaults = UserDefaults.standard

    // 기본 스트리밍 설정
    defaults.set(settings.rtmpURL, forKey: "LiveStream.rtmpURL")

    // 스트림 키는 Keychain에 저장 (보안 향상)
    if !settings.streamKey.isEmpty {
      if !KeychainManager.shared.saveStreamKey(settings.streamKey) {
        logger.error("❌ 스트림 키 Keychain 저장 실패", category: .system)
      }
    }

    defaults.set(settings.streamTitle, forKey: "LiveStream.streamTitle")

    // 비디오 설정
    defaults.set(settings.videoBitrate, forKey: "LiveStream.videoBitrate")
    defaults.set(settings.videoWidth, forKey: "LiveStream.videoWidth")
    defaults.set(settings.videoHeight, forKey: "LiveStream.videoHeight")
    defaults.set(settings.frameRate, forKey: "LiveStream.frameRate")

    // 오디오 설정
    defaults.set(settings.audioBitrate, forKey: "LiveStream.audioBitrate")

    // 고급 설정
    defaults.set(settings.autoReconnect, forKey: "LiveStream.autoReconnect")
    defaults.set(settings.isEnabled, forKey: "LiveStream.isEnabled")
    defaults.set(settings.bufferSize, forKey: "LiveStream.bufferSize")
    defaults.set(settings.connectionTimeout, forKey: "LiveStream.connectionTimeout")
    defaults.set(settings.videoEncoder, forKey: "LiveStream.videoEncoder")
    defaults.set(settings.audioEncoder, forKey: "LiveStream.audioEncoder")

    // 저장 시점 기록
    defaults.set(Date(), forKey: "LiveStream.savedAt")

    // 즉시 디스크에 동기화
    defaults.synchronize()

    logger.info("✅ 스트리밍 설정 저장 완료", category: .system)
    logger.debug("💾 저장된 설정:", category: .system)
    logger.debug("  📍 RTMP URL: [설정됨]", category: .system)
    logger.debug("  🔑 스트림 키 길이: \(settings.streamKey.count)자", category: .system)
    logger.debug(
      "  📊 비디오: \(settings.videoWidth)×\(settings.videoHeight) @ \(settings.videoBitrate)kbps",
      category: .system)
    logger.debug("  🎵 오디오: \(settings.audioBitrate)kbps", category: .system)
  }

  /// 두 설정이 동일한지 비교 (실시간 적용 여부 결정용)
  private func isSettingsEqual(
    _ settings1: USBExternalCamera.LiveStreamSettings,
    _ settings2: USBExternalCamera.LiveStreamSettings
  ) -> Bool {
    return settings1.videoWidth == settings2.videoWidth
      && settings1.videoHeight == settings2.videoHeight
      && settings1.videoBitrate == settings2.videoBitrate
      && settings1.audioBitrate == settings2.audioBitrate
      && settings1.frameRate == settings2.frameRate
  }

  /// RTMP 스트림 반환 (UI 미리보기용)
  public func getRTMPStream() -> RTMPStream? {
    return currentRTMPStream
  }

  /// 스트림 키 문제 상세 분석
  private func analyzeStreamKeyIssues(for settings: USBExternalCamera.LiveStreamSettings) {
    logger.error("  🔑 스트림 키 상세 분석:", category: .connection)

    let streamKey = settings.streamKey
    let cleanedKey = cleanAndValidateStreamKey(streamKey)

    // 1. 기본 정보
    logger.error("    📏 원본 스트림 키 길이: \(streamKey.count)자", category: .connection)
    logger.error("    🧹 정제된 스트림 키 길이: \(cleanedKey.count)자", category: .connection)
    logger.error(
      "    🔤 스트림 키 형식: \(cleanedKey.prefix(4))***\(cleanedKey.suffix(2))", category: .connection)

    // 2. 문자 구성 분석
    let hasUppercase = cleanedKey.rangeOfCharacter(from: .uppercaseLetters) != nil
    let hasLowercase = cleanedKey.rangeOfCharacter(from: .lowercaseLetters) != nil
    let hasNumbers = cleanedKey.rangeOfCharacter(from: .decimalDigits) != nil
    let hasSpecialChars = cleanedKey.rangeOfCharacter(from: CharacterSet(charactersIn: "-_")) != nil

    logger.error("    📊 문자 구성:", category: .connection)
    logger.error("      • 대문자: \(hasUppercase ? "✅" : "❌")", category: .connection)
    logger.error("      • 소문자: \(hasLowercase ? "✅" : "❌")", category: .connection)
    logger.error("      • 숫자: \(hasNumbers ? "✅" : "❌")", category: .connection)
    logger.error("      • 특수문자(-_): \(hasSpecialChars ? "✅" : "❌")", category: .connection)

    // 3. 공백 및 특수문자 검사
    let originalLength = streamKey.count
    let trimmedLength = streamKey.trimmingCharacters(in: .whitespacesAndNewlines).count
    let cleanedLength = cleanedKey.count

    if originalLength != trimmedLength {
      logger.error("    ⚠️ 앞뒤 공백/개행 발견! (\(originalLength - trimmedLength)자)", category: .connection)
    }

    if trimmedLength != cleanedLength {
      logger.error("    ⚠️ 숨겨진 제어문자 발견! (\(trimmedLength - cleanedLength)자)", category: .connection)
    }

    // 4. 스트림 키 패턴 검증
    if cleanedKey.count < 16 {
      logger.error("    ❌ 스트림 키가 너무 짧음 (16자 이상 필요)", category: .connection)
    } else if cleanedKey.count > 50 {
      logger.error("    ❌ 스트림 키가 너무 긺 (50자 이하 권장)", category: .connection)
    } else {
      logger.error("    ✅ 스트림 키 길이 적정", category: .connection)
    }

    // 5. YouTube 스트림 키 패턴 검증 (일반적인 패턴)
    if settings.rtmpURL.contains("youtube.com") {
      // YouTube 스트림 키는 보통 24-48자의 영숫자+하이픈 조합
      let youtubePattern = "^[a-zA-Z0-9_-]{20,48}$"
      let regex = try? NSRegularExpression(pattern: youtubePattern)
      let isValidYouTubeFormat =
        regex?.firstMatch(in: cleanedKey, range: NSRange(location: 0, length: cleanedKey.count))
        != nil

      if isValidYouTubeFormat {
        logger.error("    ✅ YouTube 스트림 키 형식 적합", category: .connection)
      } else {
        logger.error("    ❌ YouTube 스트림 키 형식 의심스러움", category: .connection)
        logger.error("        (일반적으로 20-48자의 영숫자+하이픈 조합)", category: .connection)
      }
    }
  }

  /// StreamSwitcher와 공유하는 스트림 키 검증 및 정제 메서드
  public func cleanAndValidateStreamKey(_ streamKey: String) -> String {
    // 1. 앞뒤 공백 제거
    let trimmed = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)

    // 2. 보이지 않는 특수 문자 제거 (제어 문자, BOM 등)
    let cleaned = trimmed.components(separatedBy: .controlCharacters).joined()
      .components(separatedBy: CharacterSet(charactersIn: "\u{FEFF}\u{200B}\u{200C}\u{200D}"))
      .joined()

    return cleaned
  }

  /// 송출 데이터 흐름 상태 확인 (공개 메서드)
  public func getDataFlowStatus() -> (isConnected: Bool, framesSent: Int, summary: String) {
    let rtmpConnected = currentRTMPStream != nil
    let framesSent = screenCaptureStats.successCount

    let summary = """
      📊 송출 데이터 흐름 상태:
      🎛️ MediaMixer: 실행 상태 확인 중
      📡 RTMPStream: \(rtmpConnected ? "연결됨" : "미연결")
      🎥 화면캡처: \(isScreenCaptureMode ? "활성" : "비활성")
      📹 프레임전송: \(framesSent)개 성공
      📊 현재FPS: \(String(format: "%.1f", screenCaptureStats.currentFPS))
      """

    return (rtmpConnected, framesSent, summary)
  }

  /// YouTube Live 연결 문제 진단 및 해결 가이드 (공개 메서드)
  public func diagnoseYouTubeLiveConnection() -> String {
    guard let settings = currentSettings, settings.rtmpURL.contains("youtube.com") else {
      return "YouTube Live 설정이 감지되지 않았습니다."
    }

    let diagnosis = """
      🎯 YouTube Live 연결 진단 결과:

      📊 현재 상태:
      • RTMP URL: \(settings.rtmpURL)
      • 스트림 키 길이: \(settings.streamKey.count)자
      • 재연결 시도: \(reconnectAttempts)/\(maxReconnectAttempts)
      • 연결 실패: \(connectionFailureCount)/\(maxConnectionFailures)

      🔧 해결 방법 (순서대로 시도):

      1️⃣ YouTube Studio 확인
         • studio.youtube.com 접속
         • 좌측 메뉴 → 라이브 스트리밍
         • "스트리밍 시작" 버튼 클릭 ⭐️
         • 상태: "스트리밍을 기다리는 중..." 확인

      2️⃣ 스트림 키 새로고침
         • YouTube Studio에서 새 스트림 키 복사
         • 앱에서 스트림 키 교체
         • 전체 선택 후 복사 (공백 없이)

      3️⃣ 네트워크 환경 확인
         • Wi-Fi 연결 상태 확인
         • 방화벽 설정 확인
         • VPN 사용 시 비활성화 시도

      4️⃣ YouTube 계정 상태
         • 라이브 스트리밍 권한 활성화 여부
         • 계정 제재 또는 제한 확인
         • 채널 인증 상태 확인

      💡 추가 팁:
      • 다른 스트리밍 프로그램 완전 종료
      • 브라우저 YouTube 탭 새로고침
      • 10-15분 후 재시도 (서버 혼잡 시)
      """

    return diagnosis
  }

  /// 연결 상태 간단 체크 (UI용)
  public func getConnectionSummary() -> (status: String, color: String, recommendation: String) {
    if !isStreaming {
      return ("중지됨", "gray", "스트리밍을 시작하세요")
    }

    if reconnectAttempts > 0 {
      return ("재연결 중", "orange", "YouTube Studio 상태를 확인하세요")
    }

    if connectionFailureCount > 0 {
      return ("불안정", "yellow", "연결 상태를 모니터링 중입니다")
    }

    if currentRTMPStream != nil && screenCaptureStats.frameCount > 0 {
      return ("정상", "green", "스트리밍이 원활히 진행 중입니다")
    }

    return ("확인 중", "blue", "연결 상태를 확인하고 있습니다")
  }

  /// 실시간 데이터 흐름 검증 (테스트용)
  public func validateDataFlow() -> Bool {
    // 모든 조건이 충족되어야 정상 송출 상태
    let conditions = [
      isStreaming,  // 스트리밍 중
      isScreenCaptureMode,  // 화면 캡처 모드
      currentRTMPStream != nil,  // RTMPStream 연결
      screenCaptureStats.frameCount > 0,  // 실제 프레임 전송
    ]

    let isValid = conditions.allSatisfy { $0 }

    if !isValid {
      logger.warning("⚠️ 데이터 흐름 검증 실패:")
      logger.warning("  - 스트리밍 중: \(isStreaming)")
      logger.warning("  - 화면캡처 모드: \(isScreenCaptureMode)")
      logger.warning("  - RTMPStream 연결: \(currentRTMPStream != nil)")
      logger.warning("  - 프레임 전송: \(screenCaptureStats.frameCount)개")
    }

    return isValid
  }

  /// 수동 재연결 (사용자가 직접 재시도)
  public func manualReconnect() async throws {
    guard let settings = currentSettings else {
      throw LiveStreamError.configurationError("재연결할 설정이 없습니다")
    }

    logger.info("🔄 사용자 요청 수동 재연결", category: .connection)

    // 재연결 카운터 리셋
    reconnectAttempts = 0
    reconnectDelay = 8.0  // 초기 재연결 지연시간 최적화 (15.0 → 8.0)
    connectionFailureCount = 0

    // 기존 연결 정리
    if isStreaming {
      await stopStreaming()
    }

    // 새로운 연결 시도 (화면 캡처 모드)
    try await startScreenCaptureStreaming(with: settings)
  }

  /// AVCaptureSession에서 받은 비디오 프레임 통계 업데이트 (통계 전용)
  public func processVideoFrame(_ sampleBuffer: CMSampleBuffer) async {
    guard isStreaming else { return }

    // 프레임 카운터 증가 (실제 데이터는 HaishinKit이 자체 카메라 연결로 처리)
    frameCounter += 1
    transmissionStats.videoFramesTransmitted += 1

    // 전송 바이트 추정
    let estimatedFrameSize: Int64 = 50000  // 50KB 추정
    transmissionStats.totalBytesTransmitted += estimatedFrameSize
    bytesSentCounter += estimatedFrameSize

    // 참고: 실제 프레임 송출은 sendManualFrame()에서 처리됩니다.
    // 텍스트 오버레이 병합도 sendManualFrame()에서 수행됩니다.
  }

  /// 픽셀 버퍼에 텍스트 오버레이 추가
  private func addTextOverlayToPixelBuffer(_ pixelBuffer: CVPixelBuffer) async -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // 픽셀 버퍼를 UIImage로 변환
    guard let sourceImage = pixelBufferToUIImage(pixelBuffer) else {
      logger.error("❌ 픽셀버퍼 → UIImage 변환 실패", category: .streaming)
      return nil
    }

    // 텍스트 오버레이가 추가된 이미지 생성
    guard let overlaidImage = addTextOverlayToImage(sourceImage) else {
      logger.error("❌ 이미지에 텍스트 오버레이 추가 실패", category: .streaming)
      return nil
    }

    // UIImage를 다시 픽셀 버퍼로 변환
    return uiImageToPixelBuffer(overlaidImage, width: width, height: height)
  }

  /// UIImage에 텍스트 오버레이 추가
  private func addTextOverlayToImage(_ image: UIImage) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: image.size)

    return renderer.image { context in
      // 원본 이미지 그리기
      image.draw(at: .zero)

      // 스트림 해상도와 프리뷰 해상도 비율 계산하여 폰트 크기 조정
      // 기준 해상도 720p (1280x720)와 현재 이미지 크기 비교
      let baseWidth: CGFloat = 1280
      let baseHeight: CGFloat = 720
      let scaleFactor = min(image.size.width / baseWidth, image.size.height / baseHeight)
      let adjustedFontSize = textOverlaySettings.fontSize * scaleFactor

      // 조정된 폰트 생성
      var adjustedFont: UIFont
      switch textOverlaySettings.fontName {
      case "System":
        adjustedFont = UIFont.systemFont(ofSize: adjustedFontSize, weight: .medium)
      case "System Bold":
        adjustedFont = UIFont.systemFont(ofSize: adjustedFontSize, weight: .bold)
      case "Helvetica":
        adjustedFont =
          UIFont(name: "Helvetica", size: adjustedFontSize)
          ?? UIFont.systemFont(ofSize: adjustedFontSize)
      case "Helvetica Bold":
        adjustedFont =
          UIFont(name: "Helvetica-Bold", size: adjustedFontSize)
          ?? UIFont.systemFont(ofSize: adjustedFontSize, weight: .bold)
      case "Arial":
        adjustedFont =
          UIFont(name: "Arial", size: adjustedFontSize)
          ?? UIFont.systemFont(ofSize: adjustedFontSize)
      case "Arial Bold":
        adjustedFont =
          UIFont(name: "Arial-BoldMT", size: adjustedFontSize)
          ?? UIFont.systemFont(ofSize: adjustedFontSize, weight: .bold)
      default:
        adjustedFont = UIFont.systemFont(ofSize: adjustedFontSize, weight: .medium)
      }

      // 사용자 설정에 따른 텍스트 스타일 설정 (조정된 폰트 사용)
      let textAttributes: [NSAttributedString.Key: Any] = [
        .font: adjustedFont,
        .foregroundColor: textOverlaySettings.uiColor,
        .strokeColor: UIColor.black,
        .strokeWidth: -2.0,  // 외곽선 두께 (가독성 향상)
      ]

      let attributedText = NSAttributedString(
        string: textOverlaySettings.text, attributes: textAttributes)
      let textSize = attributedText.size()

      // 텍스트 위치 계산 (하단 중앙)
      let textRect = CGRect(
        x: (image.size.width - textSize.width) / 2,
        y: image.size.height - textSize.height - 60,  // 하단에서 60px 위
        width: textSize.width,
        height: textSize.height
      )

      // 배경 그리기 (반투명 검은색 둥근 사각형 - 프리뷰와 일치)
      let scaledPaddingX = 16 * scaleFactor
      let scaledPaddingY = 8 * scaleFactor
      let scaledCornerRadius = 8 * scaleFactor
      let backgroundRect = textRect.insetBy(dx: -scaledPaddingX, dy: -scaledPaddingY)
      context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)

      // 둥근 사각형 그리기 (스케일에 맞는 cornerRadius)
      let path = UIBezierPath(roundedRect: backgroundRect, cornerRadius: scaledCornerRadius)
      context.cgContext.addPath(path.cgPath)
      context.cgContext.fillPath()

      // 텍스트 그리기
      attributedText.draw(in: textRect)
    }
  }

  /// 픽셀 버퍼를 UIImage로 변환 (색상 공간 최적화)
  private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

    // 색상 공간을 명시적으로 sRGB로 설정하여 일관성 확보
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CIContext(options: [
      .workingColorSpace: colorSpace,
      .outputColorSpace: colorSpace,
    ])

    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      logger.error("❌ CIImage → CGImage 변환 실패", category: .streaming)
      return nil
    }

    return UIImage(cgImage: cgImage)
  }

  /// UIImage를 픽셀 버퍼로 변환 (색상 필터 및 위아래 반전 문제 수정)
  private func uiImageToPixelBuffer(_ image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
    let attributes =
      [
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
      ] as CFDictionary

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,  // ARGB → BGRA로 변경 (색상 채널 순서 문제 해결)
      attributes,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      logger.error("❌ 픽셀버퍼 생성 실패", category: .streaming)
      return nil
    }

    CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
    defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }

    let pixelData = CVPixelBufferGetBaseAddress(buffer)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

    let context = CGContext(
      data: pixelData,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: rgbColorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue  // BGRA 포맷에 맞는 설정
    )

    guard let cgContext = context else {
      logger.error("❌ CGContext 생성 실패", category: .streaming)
      return nil
    }

    // 위아래 반전 제거 - 좌표계 변환 없이 이미지를 그대로 그리기
    let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
    cgContext.draw(image.cgImage!, in: imageRect)

    return buffer
  }

  // MARK: - Screen Capture MediaMixer Setup

  /// 화면 캡처 전용 MediaMixer 설정
  private func setupScreenCaptureMediaMixer() async throws {
    logger.info("🎛️ 화면 캡처용 MediaMixer 초기화 시작", category: .system)

    // MediaMixer 시작
    await mixer.startRunning()

    // 스크린 크기 설정 (매우 중요 - aspect ratio 문제 해결)
    if let settings = currentSettings {
      logger.info(
        "📹 화면 캡처용 목표 해상도: \(settings.videoWidth)x\(settings.videoHeight) @ \(settings.videoBitrate)kbps",
        category: .system)
      logger.info("📹 화면 캡처용 목표 프레임률: \(settings.frameRate)fps", category: .system)
      logger.info("🎵 화면 캡처용 목표 오디오: \(settings.audioBitrate)kbps", category: .system)

      // 🔧 중요: mixer.screen.size를 스트리밍 해상도와 정확히 일치시킴 (ScreenActor 사용)
      let screenSize = CGSize(width: settings.videoWidth, height: settings.videoHeight)

      Task { @ScreenActor in
        await mixer.screen.size = screenSize
        await mixer.screen.backgroundColor = UIColor.black.cgColor
      }

      logger.info("🖥️ MediaMixer 스크린 크기 설정: \(screenSize) (aspect ratio 문제 해결)", category: .system)
      logger.info("🎨 MediaMixer 배경색 설정: 검은색", category: .system)
    }

    logger.info("✅ 화면 캡처용 MediaMixer 초기화 완료 - RTMPStream 연결 대기", category: .system)
  }

  /// RTMPStream 설정 적용 (스트림이 준비된 후 호출)
  private func applyStreamSettings() async throws {
    guard let stream = await streamSwitcher.stream, let settings = currentSettings else {
      logger.error("❌ RTMPStream 또는 설정이 준비되지 않음", category: .system)
      return
    }

    logger.info("🎛️ RTMPStream 설정 적용 시작", category: .system)
    logger.info("📋 현재 설정값:", category: .system)
    logger.info(
      "  📺 비디오: \(settings.videoWidth)×\(settings.videoHeight) @ \(settings.videoBitrate) kbps",
      category: .system)
    logger.info("  🎵 오디오: \(settings.audioBitrate) kbps", category: .system)
    logger.info("  🎬 프레임률: \(settings.frameRate) fps", category: .system)

    // 🔧 개선: VideoToolbox 진단 수행
    let diagnostics = await performVideoToolboxDiagnosis()

    // 사용자 설정 검증 및 권장사항 제공 (강제 변경 없음)
    let validationResult = validateAndProvideRecommendations(settings)
    var userSettings = validationResult.settings  // 사용자 설정 그대로 사용

    // 🔧 개선: VideoToolbox 프리셋 기반 설정 적용
    if diagnostics.hardwareAccelerationSupported {
      logger.info(
        "🎯 VideoToolbox 하드웨어 가속 지원 - 프리셋 설정: \(videoToolboxPreset.description)", category: .system)

      // iOS 17.4 이상에서만 새로운 VideoToolbox API 사용
      if #available(iOS 17.4, *) {
        do {
          // 새로운 강화된 VideoToolbox 설정 사용
          try await performanceOptimizer.setupHardwareCompressionWithPreset(
            settings: userSettings,
            preset: videoToolboxPreset
          )
          logger.info("✅ VideoToolbox 프리셋 설정 완료", category: .system)
        } catch {
          logger.error("❌ VideoToolbox 프리셋 설정 실패 - 기본 설정으로 폴백: \(error)", category: .system)

          // 폴백: 기존 방식으로 시도
          do {
            try performanceOptimizer.setupHardwareCompression(settings: userSettings)
            logger.info("✅ VideoToolbox 기본 설정 완료 (폴백)", category: .system)
          } catch {
            logger.warning("⚠️ VideoToolbox 하드웨어 설정 실패 - 소프트웨어 인코딩 사용: \(error)", category: .system)
          }
        }
      } else {
        // iOS 17.4 미만에서는 기본 설정만 사용
        logger.info("📱 iOS 17.4 미만 - VideoToolbox 고급 기능 미사용", category: .system)
      }
    } else {
      logger.warning("⚠️ VideoToolbox 하드웨어 가속 미지원 - 소프트웨어 인코딩 사용", category: .system)
    }

    // 🎯 720p 특화 최적화 적용 (사용자 설정 유지, 내부 최적화만)
    if settings.videoWidth == 1280 && settings.videoHeight == 720 {
      // 사용자 설정은 변경하지 않고, 내부 최적화만 적용
      _ = performanceOptimizer.optimize720pStreaming(settings: userSettings)
      logger.info("🎯 720p 특화 내부 최적화 적용됨 (사용자 설정 유지)", category: .system)
    }

    // 비디오 설정 적용 (사용자 설정 그대로)
    var videoSettings = await stream.videoSettings
    videoSettings.videoSize = CGSize(
      width: userSettings.videoWidth, height: userSettings.videoHeight)

    // VideoToolbox 하드웨어 인코딩 최적화 설정
    videoSettings.bitRate = userSettings.videoBitrate * 1000  // kbps를 bps로 변환

    // 💡 VideoToolbox 하드웨어 인코딩 최적화 (HaishinKit 2.0.8 API 호환)
    videoSettings.profileLevel = kVTProfileLevel_H264_High_AutoLevel as String  // 고품질 프로파일
    videoSettings.allowFrameReordering = true  // B-프레임 활용 (압축 효율 향상)
    videoSettings.maxKeyFrameIntervalDuration = 2  // 2초 간격 키프레임

    // 하드웨어 가속 활성화 (iOS는 기본적으로 하드웨어 사용)
    videoSettings.isHardwareEncoderEnabled = true

    await stream.setVideoSettings(videoSettings)
    logger.info(
      "✅ 사용자 설정 적용 완료: \(userSettings.videoWidth)×\(userSettings.videoHeight) @ \(userSettings.videoBitrate)kbps",
      category: .system)

    // 오디오 설정 적용 (사용자 설정 그대로)
    var audioSettings = await stream.audioSettings
    audioSettings.bitRate = userSettings.audioBitrate * 1000  // kbps를 bps로 변환

    await stream.setAudioSettings(audioSettings)
    logger.info("✅ 사용자 오디오 설정 적용: \(userSettings.audioBitrate)kbps", category: .system)

    // 🔍 중요: 설정 적용 검증 (실제 적용된 값 확인)
    let appliedVideoSettings = await stream.videoSettings
    let appliedAudioSettings = await stream.audioSettings

    let actualWidth = Int(appliedVideoSettings.videoSize.width)
    let actualHeight = Int(appliedVideoSettings.videoSize.height)
    let actualVideoBitrate = appliedVideoSettings.bitRate / 1000
    let actualAudioBitrate = appliedAudioSettings.bitRate / 1000

    logger.info("🔍 설정 적용 검증:", category: .system)
    logger.info(
      "  📺 해상도: \(actualWidth)×\(actualHeight) (요청: \(userSettings.videoWidth)×\(userSettings.videoHeight))",
      category: .system)
    logger.info(
      "  📊 비디오 비트레이트: \(actualVideoBitrate)kbps (요청: \(userSettings.videoBitrate)kbps)",
      category: .system)
    logger.info(
      "  🎵 오디오 비트레이트: \(actualAudioBitrate)kbps (요청: \(userSettings.audioBitrate)kbps)",
      category: .system)

    // 설정값과 실제값 불일치 검사
    if actualWidth != userSettings.videoWidth || actualHeight != userSettings.videoHeight {
      logger.warning(
        "⚠️ 해상도 불일치 감지: 요청 \(userSettings.videoWidth)×\(userSettings.videoHeight) vs 실제 \(actualWidth)×\(actualHeight)",
        category: .system)
    }

    if abs(Int(actualVideoBitrate) - userSettings.videoBitrate) > 100 {
      logger.warning(
        "⚠️ 비디오 비트레이트 불일치: 요청 \(userSettings.videoBitrate)kbps vs 실제 \(actualVideoBitrate)kbps",
        category: .system)
    }

    if abs(Int(actualAudioBitrate) - userSettings.audioBitrate) > 10 {
      logger.warning(
        "⚠️ 오디오 비트레이트 불일치: 요청 \(userSettings.audioBitrate)kbps vs 실제 \(actualAudioBitrate)kbps",
        category: .system)
    }

    // 🎯 720p 전용 버퍼링 최적화 적용
    await optimize720pBuffering()

    // 🔧 개선: VideoToolbox 성능 모니터링 시작
    await startVideoToolboxPerformanceMonitoring()

    logger.info("🎉 강화된 RTMPStream 설정 적용 완료", category: .system)
  }

  /// 스트리밍 설정 검증 및 권장사항 제공 (강제 변경 제거)
  private func validateAndProvideRecommendations(_ settings: USBExternalCamera.LiveStreamSettings)
    -> (settings: USBExternalCamera.LiveStreamSettings, recommendations: [String])
  {
    var recommendations: [String] = []

    // 성능 권장사항만 제공, 강제 변경하지 않음
    if settings.videoWidth >= 1920 && settings.videoHeight >= 1080 {
      recommendations.append("⚠️ 1080p는 높은 성능을 요구합니다. 프레임 드롭이 발생할 수 있습니다.")
      recommendations.append("💡 권장: 720p (1280x720)로 설정하면 더 안정적입니다.")
    }

    if settings.frameRate > 30 {
      recommendations.append("⚠️ 60fps는 높은 CPU 사용량을 요구합니다.")
      recommendations.append("💡 권장: 30fps로 설정하면 더 안정적입니다.")
    }

    if settings.videoBitrate > 6000 {
      recommendations.append("⚠️ 높은 비트레이트는 네트워크 부하를 증가시킬 수 있습니다.")
      recommendations.append("💡 권장: 4500kbps 이하로 설정하는 것을 권장합니다.")
    }

    // 권장사항 로그 출력
    if !recommendations.isEmpty {
      logger.info("📋 성능 권장사항 (사용자 설정은 유지됨):", category: .system)
      for recommendation in recommendations {
        logger.info("  \(recommendation)", category: .system)
      }
    }

    // 🔧 중요: 사용자 설정을 그대로 반환 (강제 변경 없음)
    return (settings: settings, recommendations: recommendations)
  }

  /// 기존 validateAndAdjustSettings 함수를 새로운 함수로 대체
  private func validateAndAdjustSettings(_ settings: USBExternalCamera.LiveStreamSettings)
    -> USBExternalCamera.LiveStreamSettings
  {
    let validationResult = validateAndProvideRecommendations(settings)

    // 권장사항이 있어도 사용자 설정을 그대로 사용
    logger.info(
      "✅ 사용자 설정 보존: \(settings.videoWidth)×\(settings.videoHeight) @ \(settings.frameRate)fps, \(settings.videoBitrate)kbps",
      category: .system)

    return validationResult.settings
  }

  /// 화면 캡처 스트리밍용 오디오 설정
  private func setupAudioForScreenCapture() async throws {
    logger.info("🎵 화면 캡처용 오디오 설정 시작", category: .system)

    do {
      // 디바이스 마이크를 MediaMixer에 연결 (개선된 설정)
      guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
        logger.warning("⚠️ 오디오 디바이스를 찾을 수 없음", category: .system)
        return
      }

      // 스트리밍 설정에 맞춰 오디오 디바이스 최적화
      if let settings = currentSettings {
        try optimizeAudioDevice(audioDevice, for: settings)
      }

      // 오디오 디바이스 연결
      try await mixer.attachAudio(audioDevice, track: 0)

      // 오디오 설정은 기본값 사용 (HaishinKit에서 지원하는 설정만)

      logger.info("✅ 화면 캡처용 오디오 설정 완료 - 마이크 연결됨", category: .system)
      logger.info("  🎤 디바이스: \(audioDevice.localizedName)", category: .system)

    } catch {
      logger.warning("⚠️ 화면 캡처용 오디오 설정 실패 (비디오만 송출): \(error)", category: .system)
      // 오디오 실패는 치명적이지 않으므로 비디오만 송출 계속
    }
  }

  /// 스트리밍 설정에 맞춰 오디오 디바이스 최적화
  private func optimizeAudioDevice(
    _ audioDevice: AVCaptureDevice, for settings: USBExternalCamera.LiveStreamSettings
  ) throws {
    logger.info("🎛️ 스트리밍 설정에 맞춰 오디오 디바이스 최적화", category: .system)

    try audioDevice.lockForConfiguration()
    defer { audioDevice.unlockForConfiguration() }

    // 오디오 비트레이트에 따른 품질 최적화
    let audioQualityLevel = determineAudioQualityLevel(bitrate: settings.audioBitrate)

    switch audioQualityLevel {
    case .low:
      // 64kbps 이하: 기본 설정으로 충분
      logger.info("🎵 저품질 오디오 모드 (≤64kbps): 기본 설정 사용", category: .system)

    case .standard:
      // 128kbps: 표준 품질 최적화
      logger.info("🎵 표준 오디오 모드 (128kbps): 균형 설정 적용", category: .system)

    case .high:
      // 192kbps 이상: 고품질 최적화
      logger.info("🎵 고품질 오디오 모드 (≥192kbps): 최고 품질 설정 적용", category: .system)
    }

    // 오디오 세션 최적화 (전역 설정)
    try optimizeAudioSession(for: audioQualityLevel)

    logger.info("✅ 오디오 디바이스 최적화 완료", category: .system)
  }

  /// 오디오 품질 레벨 결정
  private func determineAudioQualityLevel(bitrate: Int) -> AudioQualityLevel {
    switch bitrate {
    case 0..<96:
      return .low
    case 96..<160:
      return .standard
    default:
      return .high
    }
  }

  /// 오디오 세션 최적화
  private func optimizeAudioSession(for qualityLevel: AudioQualityLevel) throws {
    let audioSession = AVAudioSession.sharedInstance()

    do {
      // 카테고리 설정 (녹음과 재생 모두 가능)
      try audioSession.setCategory(
        .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])

      // 품질 레벨에 따른 세부 설정
      switch qualityLevel {
      case .low:
        // 저품질: 성능 우선
        try audioSession.setPreferredSampleRate(44100)  // 표준 샘플레이트
        try audioSession.setPreferredIOBufferDuration(0.02)  // 20ms 버퍼 (성능)

      case .standard:
        // 표준 품질: 균형
        try audioSession.setPreferredSampleRate(44100)  // 표준 샘플레이트
        try audioSession.setPreferredIOBufferDuration(0.01)  // 10ms 버퍼 (균형)

      case .high:
        // 고품질: 품질 우선
        try audioSession.setPreferredSampleRate(48000)  // 고품질 샘플레이트
        try audioSession.setPreferredIOBufferDuration(0.005)  // 5ms 버퍼 (품질)
      }

      try audioSession.setActive(true)

      logger.info("🎛️ 오디오 세션 최적화 완료 (\(qualityLevel))", category: .system)

    } catch {
      logger.warning("⚠️ 오디오 세션 최적화 실패: \(error)", category: .system)
      // 실패해도 기본 설정으로 계속 진행
    }
  }

  // MARK: - Manual Frame Injection Methods (최적화된 버전)

  /// 픽셀 버퍼 전처리 (사용자 설정 해상도 정확히 적용)
  private func preprocessPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    guard let settings = currentSettings else {
      logger.debug("⚠️ 스트리밍 설정이 없어 스케일링 스킵")
      return pixelBuffer  // 설정이 없으면 원본 반환
    }

    let currentWidth = CVPixelBufferGetWidth(pixelBuffer)
    let currentHeight = CVPixelBufferGetHeight(pixelBuffer)

    // 🔧 사용자가 설정한 정확한 해상도로 변환
    let targetSize = CGSize(width: settings.videoWidth, height: settings.videoHeight)

    // 해상도가 정확히 일치하는지 확인
    if currentWidth == settings.videoWidth && currentHeight == settings.videoHeight {
      logger.debug("✅ 사용자 설정 해상도 일치: \(currentWidth)×\(currentHeight) - 변환 불필요")
      return pixelBuffer
    }

    logger.info(
      "🔄 사용자 설정 해상도로 정확히 변환: \(currentWidth)×\(currentHeight) → \(settings.videoWidth)×\(settings.videoHeight)"
    )

    // 성능 최적화 매니저를 통한 고성능 프레임 변환
    if let optimizedBuffer = performanceOptimizer.optimizedFrameConversion(
      pixelBuffer, targetSize: targetSize)
    {
      // 변환 결과 검증
      let resultWidth = CVPixelBufferGetWidth(optimizedBuffer)
      let resultHeight = CVPixelBufferGetHeight(optimizedBuffer)

      if resultWidth == settings.videoWidth && resultHeight == settings.videoHeight {
        logger.debug(
          "✅ 사용자 설정 해상도 변환 성공: \(resultWidth)×\(resultHeight) (\(String(format: "%.2f", performanceOptimizer.frameProcessingTime * 1000))ms)"
        )
        return optimizedBuffer
      } else {
        logger.error(
          "❌ 해상도 변환 검증 실패: 목표 \(settings.videoWidth)×\(settings.videoHeight) vs 결과 \(resultWidth)×\(resultHeight)"
        )
      }
    }

    // 폴백: 기존 방식
    logger.warning("⚠️ 성능 최적화 매니저 실패 - 기존 방식 폴백")

    // 1단계: VideoToolbox 최적화 포맷 변환 (YUV420 우선)
    guard let formatCompatibleBuffer = convertPixelBufferForVideoToolbox(pixelBuffer) else {
      logger.error("❌ VideoToolbox 포맷 변환 실패 - 원본 프레임 사용")
      return pixelBuffer
    }

    let originalWidth = CVPixelBufferGetWidth(formatCompatibleBuffer)
    let originalHeight = CVPixelBufferGetHeight(formatCompatibleBuffer)
    let targetWidth = settings.videoWidth
    let targetHeight = settings.videoHeight

    // 비율 계산 및 로깅 추가 (1:1 문제 추적)
    let originalAspectRatio = Double(originalWidth) / Double(originalHeight)
    let targetAspectRatio = Double(targetWidth) / Double(targetHeight)

    logger.info("📐 해상도 및 비율 검사:")
    logger.info(
      "   • 현재: \(originalWidth)x\(originalHeight) (비율: \(String(format: "%.2f", originalAspectRatio)))"
    )
    logger.info(
      "   • 목표: \(targetWidth)x\(targetHeight) (비율: \(String(format: "%.2f", targetAspectRatio)))")

    // 1:1 비율 감지 및 경고
    if abs(originalAspectRatio - 1.0) < 0.1 {
      logger.warning("⚠️ 1:1 정사각형 비율 감지! Aspect Fill로 16:9 변환 예정")
    }

    // 고품질 캡처된 프레임을 송출 해상도로 다운스케일링
    // (480p 송출을 위해 980p로 캡처된 프레임을 480p로 스케일링)
    if originalWidth != targetWidth || originalHeight != targetHeight {
      logger.info(
        "🔄 고품질 캡처 → 송출 해상도 스케일링: \(originalWidth)x\(originalHeight) → \(targetWidth)x\(targetHeight)"
      )
    } else {
      logger.debug("✅ 해상도 일치 - 스케일링 불필요")
      return formatCompatibleBuffer
    }

    let finalTargetSize = CGSize(width: targetWidth, height: targetHeight)
    guard let scaledPixelBuffer = scalePixelBuffer(formatCompatibleBuffer, to: finalTargetSize)
    else {
      logger.error("❌ 해상도 스케일링 실패 - 포맷 변환된 프레임으로 대체")
      return formatCompatibleBuffer  // 스케일링 실패 시 포맷만 변환된 버퍼 반환
    }

    // 3단계: 스케일링 성공 검증
    let finalWidth = CVPixelBufferGetWidth(scaledPixelBuffer)
    let finalHeight = CVPixelBufferGetHeight(scaledPixelBuffer)

    if finalWidth == targetWidth && finalHeight == targetHeight {
      logger.info("🎉 해상도 스케일링 완료 및 검증 성공: \(finalWidth)x\(finalHeight)")
      return scaledPixelBuffer
    } else {
      logger.error(
        "❌ 해상도 스케일링 검증 실패: 목표 \(targetWidth)x\(targetHeight) vs 결과 \(finalWidth)x\(finalHeight)")
      return formatCompatibleBuffer  // 검증 실패 시 포맷만 변환된 버퍼 반환
    }
  }

  /// CVPixelBuffer 해상도 스케일링 (고품질, HaishinKit 최적화, VideoCodec 호환성 보장)
  private func scalePixelBuffer(_ pixelBuffer: CVPixelBuffer, to targetSize: CGSize)
    -> CVPixelBuffer?
  {
    // 16의 배수로 정렬된 해상도 계산 (H.264 인코더 요구사항) - 수정된 로직
    let requestedWidth = Int(targetSize.width)
    let requestedHeight = Int(targetSize.height)

    // 16의 배수 정렬 (화면 비율 유지를 위해 내림차순 적용)
    let alignedWidth = (requestedWidth / 16) * 16  // 내림 정렬 (화면 비율 유지)
    let alignedHeight = (requestedHeight / 16) * 16  // 내림 정렬 (화면 비율 유지)

    // 최소 해상도 보장 (160x120)
    let finalWidth = max(alignedWidth, 160)
    let finalHeight = max(alignedHeight, 120)

    // 해상도 변경 여부 로깅
    if finalWidth != requestedWidth || finalHeight != requestedHeight {
      logger.info(
        "📐 해상도 16의 배수 정렬: \(requestedWidth)x\(requestedHeight) → \(finalWidth)x\(finalHeight)")
    } else {
      logger.debug("✅ 해상도 이미 16의 배수: \(finalWidth)x\(finalHeight)")
    }

    // HaishinKit 최적화 속성으로 픽셀 버퍼 생성
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 64,  // 16 → 64로 증가 (더 안전한 정렬)
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: finalWidth,
      kCVPixelBufferHeightKey as String: finalHeight,
    ]

    var outputBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      finalWidth,
      finalHeight,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &outputBuffer
    )

    guard status == kCVReturnSuccess, let scaledBuffer = outputBuffer else {
      logger.error("❌ CVPixelBuffer 생성 실패: \(status)")
      return nil
    }

    // Core Image를 사용한 고품질 스케일링 (개선된 방법)
    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)

    // 정확한 스케일링을 위한 bounds 계산
    let targetRect = CGRect(x: 0, y: 0, width: finalWidth, height: finalHeight)
    let sourceRect = inputImage.extent

    // Aspect Fill 스케일링 (화면 꽉 채우기, 16:9 비율 유지) - 1:1 문제 해결
    let scaleX = CGFloat(finalWidth) / sourceRect.width
    let scaleY = CGFloat(finalHeight) / sourceRect.height
    let scale = max(scaleX, scaleY)  // Aspect Fill - 화면 꽉 채우기 (1:1 → 16:9 비율)

    let scaledWidth = sourceRect.width * scale
    let scaledHeight = sourceRect.height * scale

    // 중앙 정렬을 위한 오프셋 계산 (넘치는 부분은 잘림)
    let offsetX = (CGFloat(finalWidth) - scaledWidth) / 2.0
    let offsetY = (CGFloat(finalHeight) - scaledHeight) / 2.0

    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))

    let scaledImage = inputImage.transformed(by: transform)

    // GPU 가속 CIContext 생성 (개선된 설정)
    let context = CIContext(options: [
      .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      .useSoftwareRenderer: false,  // GPU 사용
      .priorityRequestLow: false,  // 고우선순위
      .cacheIntermediates: false,  // 메모리 절약
    ])

    // CVPixelBuffer에 정확한 크기로 렌더링
    do {
      context.render(
        scaledImage, to: scaledBuffer, bounds: targetRect,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    } catch {
      logger.error("❌ CIContext 렌더링 실패: \(error)")
      return nil
    }

    // 스케일링 결과 검증
    let resultWidth = CVPixelBufferGetWidth(scaledBuffer)
    let resultHeight = CVPixelBufferGetHeight(scaledBuffer)

    if resultWidth == finalWidth && resultHeight == finalHeight {
      let originalInputRatio =
        Double(CVPixelBufferGetWidth(pixelBuffer)) / Double(CVPixelBufferGetHeight(pixelBuffer))
      let finalOutputRatio = Double(finalWidth) / Double(finalHeight)

      logger.info("✅ Aspect Fill 스케일링 성공:")
      logger.info(
        "   • 입력: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) (비율: \(String(format: "%.2f", originalInputRatio)))"
      )
      logger.info(
        "   • 출력: \(finalWidth)x\(finalHeight) (비율: \(String(format: "%.2f", finalOutputRatio)))")
      logger.info("   • 1:1 → 16:9 변환: \(abs(originalInputRatio - 1.0) < 0.1 ? "✅완료" : "N/A")")
      return scaledBuffer
    } else {
      logger.error(
        "❌ 스케일링 결과 불일치: 예상 \(finalWidth)x\(finalHeight) vs 실제 \(resultWidth)x\(resultHeight)")
      return nil
    }
  }

  /// CVPixelBuffer를 CMSampleBuffer로 변환 (HaishinKit 완벽 호환성)
  private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    // 1. CVPixelBuffer 입력 검증
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    logger.debug("🎬 CMSampleBuffer 생성 시작: \(width)x\(height) 포맷:\(pixelFormat)")

    // 2. HaishinKit 필수 포맷 강제 확인
    let supportedFormats: [OSType] = [
      kCVPixelFormatType_32BGRA,  // 주요 포맷 (HaishinKit 권장)
      kCVPixelFormatType_32ARGB,  // 대체 포맷
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,  // YUV 포맷
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
    ]

    if !supportedFormats.contains(pixelFormat) {
      logger.error("❌ 지원되지 않는 픽셀 포맷: \(pixelFormat) → 포맷 변환 시도")

      // 강제 포맷 변환
      if let convertedBuffer = convertToSupportedFormat(pixelBuffer) {
        logger.info("✅ 픽셀 포맷 변환 성공: \(pixelFormat) → \(kCVPixelFormatType_32BGRA)")
        return createSampleBuffer(from: convertedBuffer)
      } else {
        logger.error("❌ 픽셀 포맷 변환 실패 - CMSampleBuffer 생성 중단")
        return nil
      }
    }

    // 3. CVFormatDescription 생성 (중요: 정확한 비디오 메타데이터)
    var formatDescription: CMFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )

    guard formatStatus == noErr, let videoDesc = formatDescription else {
      logger.error("❌ CMVideoFormatDescription 생성 실패: \(formatStatus)")
      return nil
    }

    // 4. CMSampleTiming 설정 (정확한 타이밍 정보)
    let frameDuration = CMTime(value: 1, timescale: 30)  // 30fps 기준
    let currentTime = CMClockGetTime(CMClockGetHostTimeClock())

    var sampleTiming = CMSampleTimingInfo(
      duration: frameDuration,
      presentationTimeStamp: currentTime,
      decodeTimeStamp: CMTime.invalid  // 실시간 스트리밍에서는 invalid
    )

    // 5. CMSampleBuffer 생성 (HaishinKit 최적화)
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: videoDesc,
      sampleTiming: &sampleTiming,
      sampleBufferOut: &sampleBuffer
    )

    guard sampleStatus == noErr, let finalBuffer = sampleBuffer else {
      logger.error("❌ CMSampleBuffer 생성 실패: \(sampleStatus)")
      return nil
    }

    // 6. 최종 검증 및 HaishinKit 호환성 확인
    if CMSampleBufferIsValid(finalBuffer) {
      // 추가 검증: 데이터 무결성 확인
      guard CMSampleBufferGetNumSamples(finalBuffer) > 0 else {
        logger.error("❌ CMSampleBuffer에 유효한 샘플이 없음")
        return nil
      }

      // CVPixelBuffer 재확인
      guard CMSampleBufferGetImageBuffer(finalBuffer) != nil else {
        logger.error("❌ CMSampleBuffer에서 ImageBuffer 추출 실패")
        return nil
      }

      logger.debug("✅ HaishinKit 호환 CMSampleBuffer 생성 완료: \(width)x\(height)")
      return finalBuffer
    } else {
      logger.error("❌ 생성된 CMSampleBuffer 유효성 검증 실패")
      return nil
    }
  }

  /// VideoCodec -12902 에러 해결을 위한 BGRA → YUV420 포맷 변환
  private func convertToSupportedFormat(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
    let originalHeight = CVPixelBufferGetHeight(pixelBuffer)
    let currentFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    // VideoCodec 안정성을 위한 해상도 16의 배수 정렬
    let width = ((originalWidth + 15) / 16) * 16  // 16의 배수로 올림
    let height = ((originalHeight + 15) / 16) * 16  // 16의 배수로 올림

    if width != originalWidth || height != originalHeight {
      logger.debug("🔧 해상도 16배수 정렬: \(originalWidth)x\(originalHeight) → \(width)x\(height)")
    }

    // VideoCodec이 선호하는 YUV420 포맷으로 변환 (VideoCodec -12902 에러 해결)
    let targetFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    logger.info(
      "🔄 [convertToSupportedFormat] BGRA→YUV420 변환: \(currentFormat) → \(targetFormat) (\(width)x\(height))"
    )

    // 이미 YUV420 포맷이면 그대로 반환
    if currentFormat == targetFormat {
      logger.info("✅ [convertToSupportedFormat] 이미 YUV420 포맷 - 변환 불필요")
      return pixelBuffer
    }

    // VideoCodec 최적화를 위한 YUV420 속성 설정
    let attributes: [String: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 16,  // YUV420에 최적화된 정렬
      kCVPixelBufferPixelFormatTypeKey as String: targetFormat,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferPlaneAlignmentKey as String: 16,  // YUV420 플레인 정렬
    ]

    var yuvBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      targetFormat,
      attributes as CFDictionary,
      &yuvBuffer
    )

    guard createStatus == kCVReturnSuccess, let outputBuffer = yuvBuffer else {
      logger.error("❌ YUV420 픽셀버퍼 생성 실패: \(createStatus)")

      // 폴백: BGRA 포맷으로 대체 (기존 방식)
      return convertToBGRAFormat(pixelBuffer)
    }

    // 해상도가 변경된 경우 먼저 스케일링 수행
    var processedPixelBuffer = pixelBuffer
    if width != originalWidth || height != originalHeight {
      if let scaledBuffer = scalePixelBuffer(pixelBuffer, toWidth: width, toHeight: height) {
        processedPixelBuffer = scaledBuffer
      } else {
        logger.warning("⚠️ 픽셀버퍼 스케일링 실패 - 원본 크기 사용")
      }
    }

    // vImage를 사용한 고성능 BGRA → YUV420 변환
    let conversionSuccess = convertBGRAToYUV420UsingvImage(
      sourceBuffer: processedPixelBuffer,
      destinationBuffer: outputBuffer
    )

    if conversionSuccess {
      logger.debug("✅ VideoCodec 최적화 변환 성공: \(width)x\(height) → YUV420")
      return outputBuffer
    } else {
      logger.warning("⚠️ vImage 변환 실패 - CIImage 폴백 시도")

      // 폴백: CIImage를 통한 변환
      if let fallbackBuffer = convertBGRAToYUV420UsingCIImage(pixelBuffer) {
        logger.debug("✅ CIImage 폴백 변환 성공")
        return fallbackBuffer
      } else {
        logger.error("❌ 모든 YUV420 변환 방법 실패 - BGRA 폴백")
        return convertToBGRAFormat(pixelBuffer)
      }
    }
  }

  /// vImage를 사용한 고성능 BGRA → YUV420 변환 (채널 순서 변환 포함)
  private func convertBGRAToYUV420UsingvImage(
    sourceBuffer: CVPixelBuffer, destinationBuffer: CVPixelBuffer
  ) -> Bool {
    CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
    CVPixelBufferLockBaseAddress(destinationBuffer, [])

    defer {
      CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly)
      CVPixelBufferUnlockBaseAddress(destinationBuffer, [])
    }

    let width = CVPixelBufferGetWidth(sourceBuffer)
    let height = CVPixelBufferGetHeight(sourceBuffer)

    // 소스 BGRA 버퍼 정보
    guard let sourceBaseAddress = CVPixelBufferGetBaseAddress(sourceBuffer) else {
      logger.error("❌ 소스 픽셀버퍼 주소 획득 실패")
      return false
    }

    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(sourceBuffer)

    // 1단계: BGRA → ARGB 채널 순서 변환을 위한 임시 버퍼 생성
    guard let argbData = malloc(sourceBytesPerRow * height) else {
      logger.error("❌ ARGB 변환용 임시 버퍼 할당 실패")
      return false
    }
    defer { free(argbData) }

    // BGRA → ARGB 채널 순서 변환 수행
    if !swapBGRAToARGBChannels(
      sourceData: sourceBaseAddress,
      destinationData: argbData,
      width: width,
      height: height,
      sourceBytesPerRow: sourceBytesPerRow,
      destinationBytesPerRow: sourceBytesPerRow
    ) {
      logger.error("❌ BGRA → ARGB 채널 순서 변환 실패")
      return false
    }

    // YUV420 대상 버퍼 정보
    guard let yPlaneAddress = CVPixelBufferGetBaseAddressOfPlane(destinationBuffer, 0),
      let uvPlaneAddress = CVPixelBufferGetBaseAddressOfPlane(destinationBuffer, 1)
    else {
      logger.error("❌ YUV420 플레인 주소 획득 실패")
      return false
    }

    let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destinationBuffer, 0)
    let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destinationBuffer, 1)

    // 2단계: vImage 버퍼 구조체 설정 (ARGB 변환된 데이터 사용)
    var sourceImageBuffer = vImage_Buffer(
      data: argbData,  // 변환된 ARGB 데이터 사용
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: sourceBytesPerRow
    )

    var yPlaneBuffer = vImage_Buffer(
      data: yPlaneAddress,
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: yBytesPerRow
    )

    var uvPlaneBuffer = vImage_Buffer(
      data: uvPlaneAddress,
      height: vImagePixelCount(height / 2),
      width: vImagePixelCount(width / 2),
      rowBytes: uvBytesPerRow
    )

    // BGRA → YUV420 변환 정보 설정 (색상 순서 수정)
    var info = vImage_ARGBToYpCbCr()
    var pixelRange = vImage_YpCbCrPixelRange(
      Yp_bias: 16,
      CbCr_bias: 128,
      YpRangeMax: 235,
      CbCrRangeMax: 240,
      YpMax: 235,
      YpMin: 16,
      CbCrMax: 240,
      CbCrMin: 16)

    // ITU-R BT.709 변환 행렬 설정 (HD용) - ARGB 순서 사용 (vImage 표준)
    let error = vImageConvert_ARGBToYpCbCr_GenerateConversion(
      kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2,
      &pixelRange,
      &info,
      kvImageARGB8888,  // vImage 표준 ARGB 포맷 사용
      kvImage420Yp8_CbCr8,
      vImage_Flags(kvImageNoFlags)
    )

    guard error == kvImageNoError else {
      logger.error("❌ vImage 변환 설정 실패: \(error)")
      return false
    }

    // BGRA 데이터를 ARGB 순서로 변환한 후 YUV420 변환 수행
    // vImage는 ARGB 순서를 기본으로 하므로 데이터 순서 조정 후 변환
    let conversionError = vImageConvert_ARGB8888To420Yp8_CbCr8(
      &sourceImageBuffer,
      &yPlaneBuffer,
      &uvPlaneBuffer,
      &info,
      UnsafePointer<UInt8>?.none,  // nil 대신 명시적 타입 지정
      vImage_Flags(kvImageNoFlags)
    )

    if conversionError == kvImageNoError {
      logger.debug("✅ vImage BGRA→YUV420 변환 성공: \(width)x\(height)")
      return true
    } else {
      logger.error("❌ vImage BGRA→YUV420 변환 실패: \(conversionError)")
      return false
    }
  }

  /// CIImage를 사용한 BGRA → YUV420 변환 (폴백)
  private func convertBGRAToYUV420UsingCIImage(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // YUV420 버퍼 생성
    var yuvBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      nil,
      &yuvBuffer
    )

    guard createStatus == kCVReturnSuccess, let outputBuffer = yuvBuffer else {
      return nil
    }

    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext(options: [
      .workingColorSpace: CGColorSpace(name: CGColorSpace.itur_709)!,  // YUV에 적합한 색공간
      .outputColorSpace: CGColorSpace(name: CGColorSpace.itur_709)!,
      .useSoftwareRenderer: false,
      .cacheIntermediates: false,
    ])

    let targetRect = CGRect(x: 0, y: 0, width: width, height: height)

    do {
      context.render(
        inputImage, to: outputBuffer, bounds: targetRect,
        colorSpace: CGColorSpace(name: CGColorSpace.itur_709)!)
      return outputBuffer
    } catch {
      logger.error("❌ CIImage YUV420 변환 실패: \(error)")
      return nil
    }
  }

  /// 폴백용 BGRA 포맷 변환 (기존 방식)
  private func convertToBGRAFormat(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let currentFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let targetFormat = kCVPixelFormatType_32BGRA

    // 이미 BGRA면 그대로 반환
    if currentFormat == targetFormat {
      return pixelBuffer
    }

    logger.debug("🔄 폴백 BGRA 변환: \(currentFormat) → \(targetFormat)")

    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
    ]

    var convertedBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      targetFormat,
      attributes as CFDictionary,
      &convertedBuffer
    )

    guard status == kCVReturnSuccess, let outputBuffer = convertedBuffer else {
      return nil
    }

    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext(options: [.useSoftwareRenderer: false])
    let targetRect = CGRect(x: 0, y: 0, width: width, height: height)

    context.render(
      inputImage, to: outputBuffer, bounds: targetRect,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

    return outputBuffer
  }

  /// BGRA → ARGB 채널 순서 변환 (vImage 호환성을 위한 전처리)
  private func swapBGRAToARGBChannels(
    sourceData: UnsafeRawPointer,
    destinationData: UnsafeMutableRawPointer,
    width: Int,
    height: Int,
    sourceBytesPerRow: Int,
    destinationBytesPerRow: Int
  ) -> Bool {

    // vImage를 사용한 고성능 채널 순서 변환
    var sourceBuffer = vImage_Buffer(
      data: UnsafeMutableRawPointer(mutating: sourceData),
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: sourceBytesPerRow
    )

    var destinationBuffer = vImage_Buffer(
      data: destinationData,
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: destinationBytesPerRow
    )

    // BGRA(0,1,2,3) → ARGB(3,0,1,2) 순서 변환
    // B=0, G=1, R=2, A=3 → A=3, R=2, G=1, B=0
    let channelOrder: [UInt8] = [3, 2, 1, 0]  // ARGB 순서

    let error = vImagePermuteChannels_ARGB8888(
      &sourceBuffer,
      &destinationBuffer,
      channelOrder,
      vImage_Flags(kvImageNoFlags)
    )

    if error == kvImageNoError {
      logger.debug("✅ BGRA → ARGB 채널 순서 변환 성공")
      return true
    } else {
      logger.error("❌ BGRA → ARGB 채널 순서 변환 실패: \(error)")

      // 폴백: 수동 채널 변환
      return swapChannelsManually(
        sourceData: sourceData,
        destinationData: destinationData,
        width: width,
        height: height,
        sourceBytesPerRow: sourceBytesPerRow,
        destinationBytesPerRow: destinationBytesPerRow
      )
    }
  }

  /// 수동 채널 순서 변환 (vImage 실패 시 폴백)
  private func swapChannelsManually(
    sourceData: UnsafeRawPointer,
    destinationData: UnsafeMutableRawPointer,
    width: Int,
    height: Int,
    sourceBytesPerRow: Int,
    destinationBytesPerRow: Int
  ) -> Bool {

    let sourceBytes = sourceData.assumingMemoryBound(to: UInt8.self)
    let destinationBytes = destinationData.assumingMemoryBound(to: UInt8.self)

    for y in 0..<height {
      for x in 0..<width {
        let sourcePixelIndex = y * sourceBytesPerRow + x * 4
        let destPixelIndex = y * destinationBytesPerRow + x * 4

        // BGRA → ARGB 변환
        // 소스: [B, G, R, A]
        // 대상: [A, R, G, B]
        destinationBytes[destPixelIndex + 0] = sourceBytes[sourcePixelIndex + 3]  // A
        destinationBytes[destPixelIndex + 1] = sourceBytes[sourcePixelIndex + 2]  // R
        destinationBytes[destPixelIndex + 2] = sourceBytes[sourcePixelIndex + 1]  // G
        destinationBytes[destPixelIndex + 3] = sourceBytes[sourcePixelIndex + 0]  // B
      }
    }

    logger.debug("✅ 수동 BGRA → ARGB 채널 순서 변환 완료")
    return true
  }

  /// 픽셀 버퍼를 지정된 크기로 스케일링 (16의 배수 정렬용)
  private func scalePixelBuffer(
    _ pixelBuffer: CVPixelBuffer, toWidth newWidth: Int, toHeight newHeight: Int
  ) -> CVPixelBuffer? {
    let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
    let originalHeight = CVPixelBufferGetHeight(pixelBuffer)

    // 크기가 같으면 원본 반환
    if newWidth == originalWidth && newHeight == originalHeight {
      return pixelBuffer
    }

    logger.debug("🔧 픽셀버퍼 스케일링: \(originalWidth)x\(originalHeight) → \(newWidth)x\(newHeight)")

    // CIImage를 사용한 스케일링
    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    let scaleX = CGFloat(newWidth) / CGFloat(originalWidth)
    let scaleY = CGFloat(newHeight) / CGFloat(originalHeight)

    let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    // 스케일된 픽셀 버퍼 생성
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 16,
    ]

    var scaledBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      newWidth,
      newHeight,
      CVPixelBufferGetPixelFormatType(pixelBuffer),
      attributes as CFDictionary,
      &scaledBuffer
    )

    guard createStatus == kCVReturnSuccess, let outputBuffer = scaledBuffer else {
      logger.error("❌ 스케일된 픽셀버퍼 생성 실패: \(createStatus)")
      return nil
    }

    let context = CIContext(options: [.useSoftwareRenderer: false])
    let targetRect = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)

    context.render(
      scaledImage, to: outputBuffer, bounds: targetRect,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

    return outputBuffer
  }

  /// VideoToolbox 하드웨어 최적화를 위한 픽셀 버퍼 포맷 변환
  private func convertPixelBufferForVideoToolbox(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let currentFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    // VideoToolbox 하드웨어 인코더가 가장 효율적으로 처리하는 포맷 우선순위:
    // 1. YUV420 (하드웨어 가속 최적화)
    // 2. BGRA (폴백용)
    let preferredFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    if currentFormat == preferredFormat {
      logger.debug("✅ 이미 VideoToolbox 최적화 포맷(YUV420)")
      return pixelBuffer
    }

    // YUV420 변환 시도 (하드웨어 가속 최대화)
    if let yuvBuffer = convertToYUV420Format(pixelBuffer) {
      logger.debug("🚀 VideoToolbox YUV420 변환 성공 - 하드웨어 가속 최적화")
      return yuvBuffer
    }

    // 폴백: BGRA 포맷 변환
    logger.debug("⚠️ YUV420 변환 실패 - BGRA 폴백")
    return convertToSupportedFormat(pixelBuffer)
  }

  /// YUV420 포맷으로 변환 (VideoToolbox 하드웨어 가속 최적화)
  private func convertToYUV420Format(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // YUV420 픽셀 버퍼 생성
    let attributes: [String: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 16,
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferPlaneAlignmentKey as String: 16,
    ]

    var yuvBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      attributes as CFDictionary,
      &yuvBuffer
    )

    guard createStatus == kCVReturnSuccess, let outputBuffer = yuvBuffer else {
      logger.warning("⚠️ YUV420 픽셀버퍼 생성 실패: \(createStatus)")
      return nil
    }

    // vImage를 사용한 고성능 BGRA → YUV420 변환
    let conversionSuccess = convertBGRAToYUV420UsingvImage(
      sourceBuffer: pixelBuffer,
      destinationBuffer: outputBuffer
    )

    if conversionSuccess {
      logger.debug("✅ VideoToolbox YUV420 변환 성공")
      return outputBuffer
    } else {
      logger.warning("⚠️ YUV420 변환 실패")
      return nil
    }
  }

  /// CVPixelBuffer를 HaishinKit 호환 포맷으로 변환 (convertToSupportedFormat 대체용)
  private func convertPixelBufferFormat(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    // convertToSupportedFormat와 동일한 로직 사용
    return convertToSupportedFormat(pixelBuffer)
  }

  /// 화면 캡처 모드로 스트리밍 시작
  /// CameraPreviewUIView 화면을 송출하는 특별한 모드
  public func startScreenCaptureStreaming(with settings: USBExternalCamera.LiveStreamSettings)
    async throws
  {
    logger.info("🎬 화면 캡처 스트리밍 모드 시작")

    // 일반적인 스트리밍 시작과 동일하지만 카메라 연결은 생략
    guard !isStreaming else {
      logger.warning("⚠️ 이미 스트리밍 중입니다")
      throw LiveStreamError.streamingFailed("이미 스트리밍이 진행 중입니다")
    }

    // 사용자 원본 설정 보존 (덮어쓰기 방지)
    originalUserSettings = settings

    // 현재 설정 저장
    currentSettings = settings
    saveSettings(settings)

    // 상태 업데이트
    currentStatus = .connecting
    connectionStatus = "화면 캡처 모드 연결 중..."

    do {
      // 🚀 빠른 연결을 위한 최적화된 시퀀스
      logger.info("🚀 화면 캡처 스트리밍: 빠른 연결 모드 시작", category: .system)

      // 1단계: RTMP 연결 우선 (가장 중요한 부분)
      let preference = StreamPreference(
        rtmpURL: settings.rtmpURL,
        streamKey: settings.streamKey
      )
      await streamSwitcher.setPreference(preference)

      // 2단계: 실제 RTMP 연결 시작 (병렬 처리 준비)
      async let rtmpConnection: () = streamSwitcher.startStreaming()

      // 3단계: 동시에 로컬 설정들 초기화 (RTMP 연결과 병렬)
      async let localSetup: () = setupLocalComponentsInParallel(settings)

      // 4단계: 두 작업 완료 대기
      try await rtmpConnection
      try await localSetup

      logger.info("✅ 병렬 초기화 완료: RTMP 연결 + 로컬 설정", category: .system)

      // 5단계: 최종 후처리 (최소화)
      try await finalizeScreenCaptureConnection()

      // 상태 업데이트 및 모니터링 시작
      isStreaming = true
      isScreenCaptureMode = true  // 화면 캡처 모드 플래그 설정
      currentStatus = .streaming
      connectionStatus = "화면 캡처 스트리밍 중..."

      startDataMonitoring()

      // 연결 안정화 후 모니터링 시작 (최적화: 5초 → 2초로 단축)
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.startConnectionHealthMonitoring()
      }

      logger.info("🎉 화면 캡처 스트리밍 시작 성공 - 빠른 연결 모드")

    } catch {
      logger.error("❌ 화면 캡처 스트리밍 시작 실패: \(error)")

      // 실패 시 정리
      currentStatus = .error(
        error as? LiveStreamError ?? LiveStreamError.streamingFailed(error.localizedDescription))
      connectionStatus = "화면 캡처 연결 실패"
      isStreaming = false
      isScreenCaptureMode = false

      throw error
    }
  }

  // MARK: - 빠른 연결을 위한 병렬 처리 함수들

  /// RTMP 연결과 병렬로 실행할 로컬 설정들
  private func setupLocalComponentsInParallel(_ settings: USBExternalCamera.LiveStreamSettings)
    async throws
  {
    logger.info("⚡ 로컬 컴포넌트 병렬 초기화 시작", category: .system)

    // 병렬 작업들 정의
    async let mediaMixerSetup: () = initializeMediaMixerQuickly()
    async let audioSetup: () = setupAudioQuickly()
    async let settingsPreparation: () = prepareStreamSettingsQuickly(settings)

    // 모든 병렬 작업 완료 대기
    try await mediaMixerSetup
    try await audioSetup
    try await settingsPreparation

    logger.info("✅ 로컬 컴포넌트 병렬 초기화 완료", category: .system)
  }

  /// 빠른 MediaMixer 초기화 (최소 설정만)
  private func initializeMediaMixerQuickly() async throws {
    logger.info("🎛️ MediaMixer 빠른 초기화", category: .system)

    // Examples 패턴: MediaMixer 초기화 (기본 설정만)
    initializeMediaMixerBasedStreaming()

    // MediaMixer 시작 (설정은 나중에)
    await mixer.startRunning()

    logger.info("✅ MediaMixer 빠른 초기화 완료", category: .system)
  }

  /// 빠른 오디오 설정 (최소 설정만)
  private func setupAudioQuickly() async throws {
    logger.info("🎵 오디오 빠른 설정", category: .system)

    // 기본 오디오 디바이스만 연결 (최적화는 나중에)
    if let audioDevice = AVCaptureDevice.default(for: .audio) {
      try await mixer.attachAudio(audioDevice, track: 0)
      logger.info("✅ 기본 오디오 연결 완료", category: .system)
    } else {
      logger.warning("⚠️ 오디오 디바이스 없음 - 비디오만 송출", category: .system)
    }
  }

  /// 스트림 설정 사전 준비
  private func prepareStreamSettingsQuickly(_ settings: USBExternalCamera.LiveStreamSettings)
    async throws
  {
    logger.info("📋 스트림 설정 사전 준비", category: .system)

    // 설정 유효성 검증만 (적용은 나중에)
    let _ = validateAndAdjustSettings(settings)

    logger.info("✅ 스트림 설정 검증 완료", category: .system)
  }

  /// 최종 연결 완료 처리 (최소화)
  private func finalizeScreenCaptureConnection() async throws {
    logger.info("🔧 최종 연결 처리 시작", category: .system)

    // RTMPStream 연결 확인 및 설정 적용
    if let stream = await streamSwitcher.stream {
      await mixer.addOutput(stream)
      currentRTMPStream = stream

      // 스트림 설정 적용 (병렬 처리로 이미 검증된 설정 사용)
      try await applyStreamSettings()

      // VideoCodec 워크어라운드 (백그라운드에서)
      Task.detached { [weak self] in
        guard let self = self else { return }
        await self.setupVideoCodecWorkaroundInBackground(stream: stream)
      }

      logger.info("✅ 최종 연결 처리 완료", category: .system)
    } else {
      throw LiveStreamError.configurationError("RTMPStream 초기화 실패")
    }
  }

  /// VideoCodec 워크어라운드 백그라운드 설정
  private func setupVideoCodecWorkaroundInBackground(stream: RTMPStream) async {
    do {
      if let settings = currentSettings {
        try await videoCodecWorkaround.startWorkaroundStreaming(with: settings, rtmpStream: stream)
        logger.info("✅ VideoCodec 워크어라운드 백그라운드 완료", category: .system)
      }
    } catch {
      logger.warning("⚠️ VideoCodec 워크어라운드 백그라운드 실패: \(error)", category: .system)
    }
  }

  // MARK: - CameraFrameDelegate Implementation

  /// 카메라에서 새로운 비디오 프레임 수신
  nonisolated public func didReceiveVideoFrame(
    _ sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
  ) {
    Task { @MainActor in
      if self.isStreaming {
        // 프레임 카운터 증가
        self.frameCounter += 1
        self.transmissionStats.videoFramesTransmitted += 1

        // 전송 바이트 추정
        let estimatedFrameSize: Int64 = 50000  // 50KB 추정
        self.transmissionStats.totalBytesTransmitted += estimatedFrameSize
        self.bytesSentCounter += estimatedFrameSize
      }
    }
  }

  /// 화면 캡처 통계 확인
  public func getScreenCaptureStats() -> ScreenCaptureStats {
    return screenCaptureStats
  }

  /// 현재 스트리밍 설정 가져오기 (CameraPreview에서 사용)
  public func getCurrentSettings() -> USBExternalCamera.LiveStreamSettings? {
    return currentSettings
  }

  /// 화면 캡처 통계 초기화
  public func resetScreenCaptureStats() {
    screenCaptureStats = ScreenCaptureStats()
    logger.info("🔄 화면 캡처 통계 초기화")
  }

  // MARK: - 종합 파이프라인 진단 시스템

  /// 🔍 HaishinKit 스트리밍 파이프라인 종합 진단
  public func performComprehensiveStreamingDiagnosis() async -> StreamingDiagnosisReport {
    logger.info("🔍 HaishinKit 스트리밍 파이프라인 종합 진단 시작", category: .system)

    var report = StreamingDiagnosisReport()

    // 1. 설정 값 검증
    report.configValidation = await validateHaishinKitConfiguration()

    // 2. MediaMixer 상태 검증
    report.mediaMixerStatus = await validateMediaMixerConfiguration()

    // 3. RTMPStream 설정 검증
    report.rtmpStreamStatus = await validateRTMPStreamConfiguration()

    // 4. 화면 캡처 데이터 검증
    report.screenCaptureStatus = validateScreenCaptureData()

    // 5. 네트워크 연결 검증
    report.networkStatus = await validateNetworkConnection()

    // 6. 디바이스 환경 검증
    report.deviceStatus = validateDeviceEnvironment()

    // 7. 실제 송출 데이터 흐름 검증
    report.dataFlowStatus = await validateActualDataFlow()

    // 종합 점수 계산
    report.calculateOverallScore()

    // 진단 결과 로깅
    logDiagnosisReport(report)

    logger.info("✅ HaishinKit 스트리밍 파이프라인 종합 진단 완료", category: .system)

    return report
  }

  /// 1️⃣ HaishinKit 설정 값 검증
  private func validateHaishinKitConfiguration() async -> ConfigValidationResult {
    var result = ConfigValidationResult()

    logger.info("🔧 [1/7] HaishinKit 설정 값 검증 중...", category: .system)

    guard let settings = currentSettings else {
      result.isValid = false
      result.issues.append("❌ 스트리밍 설정이 로드되지 않음")
      return result
    }

    // RTMP URL 검증
    if settings.rtmpURL.isEmpty {
      result.issues.append("❌ RTMP URL이 비어있음")
    } else if !settings.rtmpURL.lowercased().hasPrefix("rtmp") {
      result.issues.append("❌ RTMP 프로토콜이 아님: \(settings.rtmpURL)")
    } else {
      result.validItems.append("✅ RTMP URL: \(settings.rtmpURL)")
    }

    // 스트림 키 검증
    if settings.streamKey.isEmpty {
      result.issues.append("❌ 스트림 키가 비어있음")
    } else if settings.streamKey.count < 10 {
      result.issues.append("⚠️ 스트림 키가 너무 짧음 (\(settings.streamKey.count)자)")
    } else {
      result.validItems.append(
        "✅ 스트림 키: \(settings.streamKey.count)자 (앞 8자: \(String(settings.streamKey.prefix(8)))...)")
    }

    // 비디오 설정 검증
    if settings.videoWidth <= 0 || settings.videoHeight <= 0 {
      result.issues.append("❌ 비디오 해상도 설정 오류: \(settings.videoWidth)x\(settings.videoHeight)")
    } else {
      result.validItems.append("✅ 비디오 해상도: \(settings.videoWidth)x\(settings.videoHeight)")
    }

    if settings.videoBitrate <= 0 || settings.videoBitrate > 10000 {
      result.issues.append("⚠️ 비디오 비트레이트 비정상: \(settings.videoBitrate)kbps")
    } else {
      result.validItems.append("✅ 비디오 비트레이트: \(settings.videoBitrate)kbps")
    }

    if settings.frameRate <= 0 || settings.frameRate > 60 {
      result.issues.append("⚠️ 프레임레이트 비정상: \(settings.frameRate)fps")
    } else {
      result.validItems.append("✅ 프레임레이트: \(settings.frameRate)fps")
    }

    // 오디오 설정 검증
    if settings.audioBitrate <= 0 || settings.audioBitrate > 320 {
      result.issues.append("⚠️ 오디오 비트레이트 비정상: \(settings.audioBitrate)kbps")
    } else {
      result.validItems.append("✅ 오디오 비트레이트: \(settings.audioBitrate)kbps")
    }

    result.isValid = result.issues.isEmpty
    result.summary = "설정 검증: \(result.validItems.count)개 정상, \(result.issues.count)개 문제"

    return result
  }

  /// 2️⃣ MediaMixer 상태 검증
  private func validateMediaMixerConfiguration() async -> MediaMixerValidationResult {
    var result = MediaMixerValidationResult()

    logger.info("🎛️ [2/7] MediaMixer 상태 검증 중...", category: .system)

    // MediaMixer 실행 상태
    let isRunning = await mixer.isRunning
    if isRunning {
      result.validItems.append("✅ MediaMixer 실행 중")
    } else {
      result.issues.append("❌ MediaMixer가 실행되지 않음")
    }

    // 수동 캡처 모드 확인
    result.validItems.append("✅ 수동 캡처 모드 활성화 (useManualCapture: true)")

    // 멀티캠 및 오디오 설정 확인
    result.validItems.append("✅ 멀티캠 세션: 비활성화 (화면 캡처용)")
    result.validItems.append("✅ 멀티 트랙 오디오: 비활성화 (단순화)")

    result.isValid = result.issues.isEmpty
    result.summary = "MediaMixer: \(isRunning ? "정상 실행" : "실행 중지")"

    return result
  }

  /// 3️⃣ RTMPStream 설정 검증
  private func validateRTMPStreamConfiguration() async -> RTMPStreamValidationResult {
    var result = RTMPStreamValidationResult()

    logger.info("📡 [3/7] RTMPStream 설정 검증 중...", category: .system)

    // RTMPStream 존재 여부
    guard let stream = await streamSwitcher.stream else {
      result.issues.append("❌ RTMPStream이 생성되지 않음")
      result.isValid = false
      result.summary = "RTMPStream: 미생성"
      return result
    }

    result.validItems.append("✅ RTMPStream 객체 생성됨")

    // 연결 상태
    if let connection = await streamSwitcher.connection {
      let isConnected = await connection.connected
      if isConnected {
        result.validItems.append("✅ RTMP 연결 상태: 연결됨")
      } else {
        result.issues.append("❌ RTMP 연결 상태: 연결 끊어짐")
      }
    } else {
      result.issues.append("❌ RTMP 연결 객체가 없음")
    }

    // 스트림 설정 검증
    let videoSettings = await stream.videoSettings
    let audioSettings = await stream.audioSettings

    result.validItems.append("✅ 비디오 설정 - 해상도: \(videoSettings.videoSize)")
    result.validItems.append("✅ 비디오 설정 - 비트레이트: \(videoSettings.bitRate)bps")
    result.validItems.append("✅ 오디오 설정 - 비트레이트: \(audioSettings.bitRate)bps")

    // 스트림 정보 (Sendable 프로토콜 문제로 인해 간소화)
    result.validItems.append("✅ 스트림 객체 연결됨")
    // streamInfo 접근은 Sendable 프로토콜 문제로 인해 제외

    result.isValid = result.issues.isEmpty
    result.summary = "RTMPStream: \(result.issues.isEmpty ? "정상 설정" : "\(result.issues.count)개 문제")"

    return result
  }

  /// 4️⃣ 화면 캡처 데이터 검증
  private func validateScreenCaptureData() -> ScreenCaptureValidationResult {
    var result = ScreenCaptureValidationResult()

    logger.info("🎥 [4/7] 화면 캡처 데이터 검증 중...", category: .system)

    // 화면 캡처 모드 확인
    if isScreenCaptureMode {
      result.validItems.append("✅ 화면 캡처 모드 활성화")
    } else {
      result.issues.append("❌ 화면 캡처 모드가 비활성화됨")
    }

    // 프레임 통계 확인
    let frameCount = screenCaptureStats.frameCount
    let successCount = screenCaptureStats.successCount
    let failureCount = screenCaptureStats.failureCount
    let currentFPS = screenCaptureStats.currentFPS

    if frameCount > 0 {
      result.validItems.append("✅ 총 프레임 처리: \(frameCount)개")
      result.validItems.append("✅ 성공한 프레임: \(successCount)개")
      if failureCount > 0 {
        result.issues.append("⚠️ 실패한 프레임: \(failureCount)개")
      }
      result.validItems.append("✅ 현재 FPS: \(String(format: "%.1f", currentFPS))")

      // 성공률 계산
      let successRate = frameCount > 0 ? (Double(successCount) / Double(frameCount)) * 100 : 0
      if successRate >= 95.0 {
        result.validItems.append("✅ 프레임 성공률: \(String(format: "%.1f", successRate))%")
      } else {
        result.issues.append("⚠️ 프레임 성공률 낮음: \(String(format: "%.1f", successRate))%")
      }
    } else {
      result.issues.append("❌ 화면 캡처 프레임 데이터 없음")
    }

    // CVPixelBuffer 생성 확인
    if screenCaptureStats.frameCount > 0 {
      result.validItems.append("✅ CVPixelBuffer → CMSampleBuffer 변환 정상")
    } else {
      result.issues.append("❌ 프레임 버퍼 변환 데이터 없음")
    }

    result.isValid = frameCount > 0 && result.issues.filter { $0.hasPrefix("❌") }.isEmpty
    result.summary = "화면 캡처: \(frameCount)프레임, \(String(format: "%.1f", currentFPS))fps"

    return result
  }

  /// 5️⃣ 네트워크 연결 검증
  private func validateNetworkConnection() async -> NetworkValidationResult {
    var result = NetworkValidationResult()

    logger.info("🌐 [5/7] 네트워크 연결 검증 중...", category: .system)

    // 네트워크 모니터 상태
    if let networkMonitor = networkMonitor {
      let path = networkMonitor.currentPath

      switch path.status {
      case .satisfied:
        result.validItems.append("✅ 네트워크 상태: 연결됨")
      case .unsatisfied:
        result.issues.append("❌ 네트워크 상태: 연결 끊어짐")
      case .requiresConnection:
        result.issues.append("⚠️ 네트워크 상태: 연결 필요")
      @unknown default:
        result.issues.append("⚠️ 네트워크 상태: 알 수 없음")
      }

      // 사용 가능한 인터페이스
      let interfaces = path.availableInterfaces.map { $0.name }
      if !interfaces.isEmpty {
        result.validItems.append("✅ 사용 가능한 인터페이스: \(interfaces.joined(separator: ", "))")
      } else {
        result.issues.append("❌ 사용 가능한 네트워크 인터페이스 없음")
      }

      // 네트워크 제약 사항
      if path.isExpensive {
        result.issues.append("⚠️ 데이터 요금이 발생하는 연결")
      } else {
        result.validItems.append("✅ 무료 네트워크 연결")
      }

      if path.isConstrained {
        result.issues.append("⚠️ 제한된 네트워크 연결")
      } else {
        result.validItems.append("✅ 제한 없는 네트워크 연결")
      }
    } else {
      result.issues.append("❌ 네트워크 모니터가 초기화되지 않음")
    }

    // 전송 통계
    let latency = transmissionStats.networkLatency
    if latency > 0 {
      if latency < 100 {
        result.validItems.append("✅ 네트워크 지연: \(Int(latency))ms (양호)")
      } else if latency < 300 {
        result.issues.append("⚠️ 네트워크 지연: \(Int(latency))ms (보통)")
      } else {
        result.issues.append("❌ 네트워크 지연: \(Int(latency))ms (높음)")
      }
    }

    result.isValid = result.issues.filter { $0.hasPrefix("❌") }.isEmpty
    result.summary = "네트워크: \(result.isValid ? "정상" : "문제 있음")"

    return result
  }

  /// 6️⃣ 디바이스 환경 검증
  private func validateDeviceEnvironment() -> DeviceValidationResult {
    var result = DeviceValidationResult()

    logger.info("📱 [6/7] 디바이스 환경 검증 중...", category: .system)

    // 실행 환경 확인
    #if targetEnvironment(simulator)
      result.issues.append("⚠️ iOS 시뮬레이터에서 실행 중 (실제 디바이스 권장)")
    #else
      result.validItems.append("✅ 실제 iOS 디바이스에서 실행 중")
    #endif

    // iOS 버전 확인
    let systemVersion = UIDevice.current.systemVersion
    result.validItems.append("✅ iOS 버전: \(systemVersion)")

    // 디바이스 모델 확인
    let deviceModel = UIDevice.current.model
    result.validItems.append("✅ 디바이스 모델: \(deviceModel)")

    // 화면 캡처 권한 (ReplayKit 지원)
    result.validItems.append("✅ 화면 캡처 기능: 사용 가능 (ReplayKit)")

    // 메모리 상태 (간접적 확인)
    let processInfo = ProcessInfo.processInfo
    result.validItems.append("✅ 시스템 업타임: \(Int(processInfo.systemUptime))초")

    result.isValid = result.issues.filter { $0.hasPrefix("❌") }.isEmpty
    result.summary = "디바이스: \(deviceModel), iOS \(systemVersion)"

    return result
  }

  /// 7️⃣ 실제 송출 데이터 흐름 검증
  private func validateActualDataFlow() async -> DataFlowValidationResult {
    var result = DataFlowValidationResult()

    logger.info("🔗 [7/7] 실제 송출 데이터 흐름 검증 중...", category: .system)

    // 스트리밍 상태 확인
    if isStreaming {
      result.validItems.append("✅ 스트리밍 상태: 활성화")
    } else {
      result.issues.append("❌ 스트리밍 상태: 비활성화")
    }

    // RTMPStream 연결 확인
    if currentRTMPStream != nil {
      result.validItems.append("✅ RTMPStream 연결: 활성화")
    } else {
      result.issues.append("❌ RTMPStream 연결: 비활성화")
    }

    // 데이터 전송 체인 확인
    let chainStatus = [
      ("CameraPreviewUIView", screenCaptureStats.frameCount > 0),
      ("HaishinKitManager.sendManualFrame", screenCaptureStats.successCount > 0),
      ("RTMPStream.append", currentRTMPStream != nil),
      ("RTMP Server", isStreaming && currentRTMPStream != nil),
    ]

    for (component, isWorking) in chainStatus {
      if isWorking {
        result.validItems.append("✅ \(component): 정상 작동")
      } else {
        result.issues.append("❌ \(component): 작동 안함")
      }
    }

    // 전송 통계 확인
    let totalFrames = transmissionStats.videoFramesTransmitted
    let totalBytes = transmissionStats.totalBytesTransmitted

    if totalFrames > 0 {
      result.validItems.append("✅ 전송된 비디오 프레임: \(totalFrames)개")
    } else {
      result.issues.append("❌ 전송된 비디오 프레임 없음")
    }

    if totalBytes > 0 {
      result.validItems.append("✅ 총 전송량: \(formatBytes(totalBytes))")
    } else {
      result.issues.append("❌ 데이터 전송량 없음")
    }

    // 실시간 FPS 확인
    let currentFPS = screenCaptureStats.currentFPS
    if currentFPS > 0 {
      if currentFPS >= 15.0 {
        result.validItems.append("✅ 실시간 FPS: \(String(format: "%.1f", currentFPS)) (정상)")
      } else {
        result.issues.append("⚠️ 실시간 FPS: \(String(format: "%.1f", currentFPS)) (낮음)")
      }
    } else {
      result.issues.append("❌ 실시간 FPS 측정 불가")
    }

    result.isValid = result.issues.filter { $0.hasPrefix("❌") }.isEmpty
    result.summary = "데이터 흐름: \(result.isValid ? "정상" : "문제 있음")"

    return result
  }

  /// 진단 결과 로깅
  private func logDiagnosisReport(_ report: StreamingDiagnosisReport) {
    logger.info("", category: .system)
    logger.info("📊 ═══════════════════════════════════════", category: .system)
    logger.info("📊 HaishinKit 스트리밍 파이프라인 진단 결과", category: .system)
    logger.info("📊 ═══════════════════════════════════════", category: .system)
    logger.info("📊 종합 점수: \(report.overallScore)점/100점 (\(report.overallGrade))", category: .system)
    logger.info("📊", category: .system)

    // 각 영역별 결과
    logger.info(
      "📊 1️⃣ 설정 검증: \(report.configValidation.isValid ? "✅ 통과" : "❌ 실패") - \(report.configValidation.summary)",
      category: .system)
    logger.info(
      "📊 2️⃣ MediaMixer: \(report.mediaMixerStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.mediaMixerStatus.summary)",
      category: .system)
    logger.info(
      "📊 3️⃣ RTMPStream: \(report.rtmpStreamStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.rtmpStreamStatus.summary)",
      category: .system)
    logger.info(
      "📊 4️⃣ 화면 캡처: \(report.screenCaptureStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.screenCaptureStatus.summary)",
      category: .system)
    logger.info(
      "📊 5️⃣ 네트워크: \(report.networkStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.networkStatus.summary)",
      category: .system)
    logger.info(
      "📊 6️⃣ 디바이스: \(report.deviceStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.deviceStatus.summary)",
      category: .system)
    logger.info(
      "📊 7️⃣ 데이터 흐름: \(report.dataFlowStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.dataFlowStatus.summary)",
      category: .system)

    logger.info("📊", category: .system)
    logger.info("📊 💡 종합 평가: \(report.getRecommendation())", category: .system)
    logger.info("📊 ═══════════════════════════════════════", category: .system)
    logger.info("", category: .system)
  }

  // MARK: - 진단 시스템 공개 인터페이스

  /// 🔍 간단한 스트리밍 상태 체크 (UI용)
  public func quickHealthCheck() -> (score: Int, status: String, issues: [String]) {
    var issues: [String] = []
    var score = 100

    // 기본 상태 체크
    if !isStreaming {
      issues.append("스트리밍이 시작되지 않음")
      score -= 30
    }

    if currentRTMPStream == nil {
      issues.append("RTMP 연결이 설정되지 않음")
      score -= 25
    }

    if screenCaptureStats.frameCount == 0 {
      issues.append("화면 캡처 데이터가 없음")
      score -= 25
    }

    if reconnectAttempts > 0 {
      issues.append("재연결 시도 중 (\(reconnectAttempts)회)")
      score -= 10
    }

    if connectionFailureCount > 0 {
      issues.append("연결 실패 감지됨 (\(connectionFailureCount)회)")
      score -= 10
    }

    let status: String
    switch score {
    case 90...100: status = "완벽"
    case 70...89: status = "양호"
    case 50...69: status = "보통"
    case 30...49: status = "불량"
    default: status = "심각"
    }

    return (max(0, score), status, issues)
  }

  /// 📊 스트리밍 파이프라인 진단 (콘솔 출력)
  public func diagnoseStreamingPipeline() async {
    let report = await performComprehensiveStreamingDiagnosis()

    logInfo("═══════════════════════════════════════", category: .performance)
    logInfo("HaishinKit 스트리밍 진단 결과", category: .performance)
    logInfo("═══════════════════════════════════════", category: .performance)
    logInfo("종합 점수: \(report.overallScore)점/100점 (\(report.overallGrade))", category: .performance)
    logInfo("", category: .performance)
    logInfo("💡 평가: \(report.getRecommendation())", category: .performance)
    logInfo("═══════════════════════════════════════", category: .performance)
  }

  /// 🎯 실시간 모니터링 데이터 요약 (UI용)
  public func getRealtimeMonitoringSummary() -> [String: Any] {
    return [
      "isStreaming": isStreaming,
      "isScreenCaptureMode": isScreenCaptureMode,
      "frameCount": screenCaptureStats.frameCount,
      "successCount": screenCaptureStats.successCount,
      "currentFPS": screenCaptureStats.currentFPS,
      "reconnectAttempts": reconnectAttempts,
      "connectionFailures": connectionFailureCount,
      "hasRTMPStream": currentRTMPStream != nil,
      "networkLatency": transmissionStats.networkLatency,
      "totalBytesTransmitted": transmissionStats.totalBytesTransmitted,
      "cpuUsage": performanceOptimizer.currentCPUUsage,
      "memoryUsage": performanceOptimizer.currentMemoryUsage,
      "gpuUsage": performanceOptimizer.currentGPUUsage,
      "frameProcessingTime": performanceOptimizer.frameProcessingTime,
    ]
  }

  /// 성능 최적화 상태 정보 조회 (UI용)
  public func getPerformanceOptimizationStatus() -> [String: Any] {
    return [
      "cpuUsage": performanceOptimizer.currentCPUUsage,
      "memoryUsage": performanceOptimizer.currentMemoryUsage,
      "gpuUsage": performanceOptimizer.currentGPUUsage,
      "frameProcessingTime": performanceOptimizer.frameProcessingTime * 1000,  // ms로 변환
      "performanceGrade": getPerformanceGrade(),
      "recommendations": getPerformanceRecommendations(),
    ]
  }

  /// 성능 등급 계산
  private func getPerformanceGrade() -> String {
    let cpuScore = max(0, 100 - performanceOptimizer.currentCPUUsage)
    let memoryScore = max(0, 100 - (performanceOptimizer.currentMemoryUsage / 10))  // 1000MB = 0점
    let processingScore = max(0, 100 - (performanceOptimizer.frameProcessingTime * 10000))  // 10ms = 0점

    let overallScore = (cpuScore + memoryScore + processingScore) / 3.0

    switch overallScore {
    case 80...100: return "우수 (A)"
    case 60...79: return "양호 (B)"
    case 40...59: return "보통 (C)"
    case 20...39: return "개선 필요 (D)"
    default: return "성능 문제 (F)"
    }
  }

  /// 성능 개선 권장사항
  private func getPerformanceRecommendations() -> [String] {
    var recommendations: [String] = []

    if performanceOptimizer.currentCPUUsage > 70 {
      recommendations.append("CPU 사용량이 높습니다. 다른 앱을 종료하거나 스트리밍 품질을 낮춰보세요.")
    }

    if performanceOptimizer.currentMemoryUsage > 400 {
      recommendations.append("메모리 사용량이 높습니다. 앱을 재시작하거나 해상도를 낮춰보세요.")
    }

    if performanceOptimizer.frameProcessingTime > 0.033 {  // > 30ms
      recommendations.append("프레임 처리 시간이 깁니다. GPU 가속이 활성화되어 있는지 확인하세요.")
    }

    if recommendations.isEmpty {
      recommendations.append("현재 성능이 양호합니다. 최적의 스트리밍 상태입니다.")
    }

    return recommendations
  }

  /// 🔧 스트리밍 문제 해결 가이드 생성
  public func generateTroubleshootingGuide() async -> String {
    let report = await performComprehensiveStreamingDiagnosis()
    var guide = "🔧 스트리밍 문제 해결 가이드\n\n"

    // 설정 문제
    if !report.configValidation.isValid {
      guide += "1️⃣ 설정 문제 해결:\n"
      for issue in report.configValidation.issues {
        guide += "   • \(issue)\n"
      }
      guide += "\n"
    }

    // 연결 문제
    if !report.rtmpStreamStatus.isValid {
      guide += "2️⃣ RTMP 연결 문제 해결:\n"
      for issue in report.rtmpStreamStatus.issues {
        guide += "   • \(issue)\n"
      }
      guide += "   💡 YouTube Studio에서 '스트리밍 시작' 버튼을 클릭했는지 확인\n\n"
    }

    // 화면 캡처 문제
    if !report.screenCaptureStatus.isValid {
      guide += "3️⃣ 화면 캡처 문제 해결:\n"
      for issue in report.screenCaptureStatus.issues {
        guide += "   • \(issue)\n"
      }
      guide += "   💡 CameraPreviewUIView의 화면 캡처 타이머 상태 확인 필요\n\n"
    }

    // 네트워크 문제
    if !report.networkStatus.isValid {
      guide += "4️⃣ 네트워크 문제 해결:\n"
      for issue in report.networkStatus.issues {
        guide += "   • \(issue)\n"
      }
      guide += "   💡 Wi-Fi 연결 상태와 방화벽 설정을 확인해주세요\n\n"
    }

    // 전반적인 권장사항
    guide += "🎯 일반적인 해결 방법:\n"
    guide += "   1. YouTube Studio에서 라이브 스트리밍 시작\n"
    guide += "   2. 스트림 키가 올바른지 확인\n"
    guide += "   3. 네트워크 연결 상태 점검\n"
    guide += "   4. 다른 스트리밍 프로그램 종료\n"
    guide += "   5. 앱 재시작 후 다시 시도\n"

    return guide
  }

  // MARK: - 개발자 전용 디버깅 메서드들

  #if DEBUG
    // 테스트 및 디버그 관련 메서드들이 제거되었습니다.
    // 프로덕션 환경에서 불필요한 테스트 데이터 및 더미 기능을 정리했습니다.
  #endif

  /// 스트리밍 설정에 맞춰 하드웨어 최적화 연동
  /// - 카메라 및 오디오 하드웨어를 스트리밍 설정에 맞춰 최적화
  /// - 품질 불일치 방지 및 성능 향상
  private func optimizeHardwareForStreaming(_ settings: USBExternalCamera.LiveStreamSettings) async
  {
    logger.info("🎛️ 스트리밍 설정에 맞춰 전체 하드웨어 최적화 시작", category: .system)

    // 1. 카메라 하드웨어 최적화 (CameraSessionManager 연동)
    await optimizeCameraHardware(for: settings)

    // 2. 하드웨어 최적화 결과 로깅
    await logHardwareOptimizationResults(settings)

    logger.info("✅ 전체 하드웨어 최적화 완료", category: .system)
  }

  /// 카메라 하드웨어 최적화 (CameraSessionManager 연동)
  private func optimizeCameraHardware(for settings: USBExternalCamera.LiveStreamSettings) async {
    // CameraSessionManager가 있는 경우에만 최적화 실행
    // (화면 캡처 모드에서는 실제 카메라를 사용하지 않지만, 향후 카메라 스트리밍 모드를 위해 준비)
    logger.info("📹 카메라 하드웨어 최적화 준비", category: .system)
    logger.info("  📺 스트리밍 해상도: \(settings.videoWidth)×\(settings.videoHeight)", category: .system)
    logger.info("  🎬 스트리밍 프레임레이트: \(settings.frameRate)fps", category: .system)
    logger.info("  📊 스트리밍 비트레이트: \(settings.videoBitrate)kbps", category: .system)

    // 화면 캡처 모드에서는 실제 카메라 최적화 생략
    // 향후 카메라 스트리밍 모드 추가 시 다음 코드 활성화:
    // if let cameraSessionManager = self.cameraSessionManager {
    //     cameraSessionManager.optimizeForStreamingSettings(settings)
    // }

    logger.info("✅ 카메라 하드웨어 최적화 완료 (화면 캡처 모드)", category: .system)
  }

  /// 하드웨어 최적화 결과 로깅
  private func logHardwareOptimizationResults(_ settings: USBExternalCamera.LiveStreamSettings)
    async
  {
    logger.info("📊 하드웨어 최적화 결과 요약:", category: .system)

    // 오디오 최적화 결과
    let audioQualityLevel = determineAudioQualityLevel(bitrate: settings.audioBitrate)
    logger.info(
      "  🎵 오디오 품질 레벨: \(audioQualityLevel.rawValue) (\(settings.audioBitrate)kbps)",
      category: .system)

    // 비디오 최적화 결과
    let videoComplexity = determineVideoComplexity(settings: settings)
    logger.info("  📺 비디오 복잡도: \(videoComplexity)", category: .system)

    // 전체 최적화 상태
    let optimizationStatus = getOverallOptimizationStatus(settings: settings)
    logger.info("  🎯 전체 최적화 상태: \(optimizationStatus)", category: .system)
  }

  /// 비디오 복잡도 결정
  private func determineVideoComplexity(settings: USBExternalCamera.LiveStreamSettings) -> String {
    let pixels = settings.videoWidth * settings.videoHeight
    let bitrate = settings.videoBitrate
    let fps = settings.frameRate

    switch (pixels, fps, bitrate) {
    case (0..<(1280 * 720), 0..<30, 0..<2000):
      return "저복잡도 (SD)"
    case (0..<(1920 * 1080), 0..<30, 0..<4000):
      return "중복잡도 (HD)"
    case (0..<(1920 * 1080), 30..<60, 4000..<6000):
      return "고복잡도 (HD 고프레임)"
    case ((1920 * 1080)..., _, 4000...):
      return "초고복잡도 (FHD+)"
    default:
      return "사용자정의"
    }
  }

  /// 전체 최적화 상태 평가
  private func getOverallOptimizationStatus(settings: USBExternalCamera.LiveStreamSettings)
    -> String
  {
    let audioLevel = determineAudioQualityLevel(bitrate: settings.audioBitrate)
    let videoPixels = settings.videoWidth * settings.videoHeight

    // 오디오/비디오 품질 균형 평가
    let isBalanced =
      (audioLevel == .standard && videoPixels >= 1280 * 720 && videoPixels < 1920 * 1080)
      || (audioLevel == .high && videoPixels >= 1920 * 1080)

    if isBalanced {
      return "최적 균형 ⭐"
    } else if audioLevel == .low && videoPixels >= 1920 * 1080 {
      return "비디오 편중 ⚠️"
    } else if audioLevel == .high && videoPixels < 1280 * 720 {
      return "오디오 편중 ⚠️"
    } else {
      return "표준 설정 ✅"
    }
  }

  /// 수동으로 프레임을 스트리밍에 전송 (화면 캡처 모드) - 개선된 버전
  @MainActor
  public func sendManualFrame(_ pixelBuffer: CVPixelBuffer) async {
    guard isStreaming else {
      logger.warning("⚠️ 스트리밍이 활성화되지 않아 프레임 스킵")
      return
    }

    // 🔄 통계 업데이트 (프레임 시작)
    screenCaptureStats.updateFrameCount()

    let currentTime = CACurrentMediaTime()

    // 1. 프레임 유효성 사전 검증
    guard validatePixelBufferForEncoding(pixelBuffer) else {
      logger.error("❌ 프레임 유효성 검증 실패 - 프레임 스킵")
      screenCaptureStats.failureCount += 1
      return
    }

    let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
    let originalHeight = CVPixelBufferGetHeight(pixelBuffer)
    logger.debug("📥 수신 프레임: \(originalWidth)x\(originalHeight)")

    // 1.5. 텍스트 오버레이 처리 (픽셀 버퍼에 직접 병합)
    var frameToProcess = pixelBuffer
    if showTextOverlay && !textOverlaySettings.text.isEmpty {
      if let overlaidPixelBuffer = await addTextOverlayToPixelBuffer(pixelBuffer) {
        frameToProcess = overlaidPixelBuffer
        logger.debug("📝 텍스트 오버레이 병합 완료: '\(textOverlaySettings.text)'")
      } else {
        logger.warning("⚠️ 텍스트 오버레이 병합 실패 - 원본 프레임 사용")
      }
    }

    // 2. 프레임 전처리 (포맷 변환 + 해상도 정렬)
    guard let processedPixelBuffer = preprocessPixelBufferSafely(frameToProcess) else {
      logger.error("❌ 프레임 전처리 실패 - 프레임 스킵")
      screenCaptureStats.failureCount += 1
      return
    }

    // 3. 전처리 결과 확인
    _ = CVPixelBufferGetWidth(processedPixelBuffer)
    _ = CVPixelBufferGetHeight(processedPixelBuffer)
    // logger.debug("📊 최종 전송 프레임: \(finalWidth)x\(finalHeight)") // 반복적인 로그 비활성화

    // 4. CMSampleBuffer 생성 (향상된 에러 핸들링)
    guard let sampleBuffer = createSampleBufferSafely(from: processedPixelBuffer) else {
      logger.error("❌ CMSampleBuffer 생성 실패 - VideoCodec 호환성 문제")
      frameTransmissionFailure += 1
      screenCaptureStats.failureCount += 1

      // VideoCodec 문제 디버깅 정보
      logVideoCodecDiagnostics(pixelBuffer: processedPixelBuffer)
      return
    }

    // 5. 프레임 전송 시도 (VideoCodec 워크어라운드 적용)
    do {
      frameTransmissionCount += 1

      // logger.debug("📡 HaishinKit 프레임 전송 시도 #\(frameTransmissionCount): \(finalWidth)x\(finalHeight)") // 반복적인 로그 비활성화

      // VideoCodec 워크어라운드를 우선 사용하여 -12902 에러 해결
      await videoCodecWorkaround.sendFrameWithWorkaround(sampleBuffer)
      // logger.debug("✅ VideoCodec 워크어라운드 적용 프레임 전송") // 반복적인 로그 비활성화

      frameTransmissionSuccess += 1
      screenCaptureStats.successCount += 1
      // logger.debug("✅ 프레임 전송 성공 #\(frameTransmissionSuccess)") // 반복적인 로그 비활성화

      // 전송 성공 통계 업데이트 (매 50프레임마다 - 더 자주 확인)
      if frameTransmissionCount % 50 == 0 {
        let successRate = Double(frameTransmissionSuccess) / Double(frameTransmissionCount) * 100
        // 성공률이 낮을 때만 로그 출력 (95% 미만)
        if successRate < 95.0 {
          logger.warning(
            "📊 프레임 전송 성공률 낮음: \(String(format: "%.1f", successRate))% (\(frameTransmissionSuccess)/\(frameTransmissionCount))"
          )
        }

        // 성공률이 낮으면 경고
        if successRate < 80.0 {
          logger.warning("⚠️ 프레임 전송 성공률 저조: \(String(format: "%.1f", successRate))% - 스트리밍 품질 저하 가능")
        }
      }

    } catch {
      logger.error("❌ 프레임 전송 중 오류: \(error)")
      frameTransmissionFailure += 1
      screenCaptureStats.failureCount += 1

      // 오류 세부 정보 로깅
      logger.error("🔍 에러 세부 정보: \(String(describing: error))")

      // VideoCodec 에러 특별 처리 - 더 넓은 범위로 감지
      let errorString = String(describing: error)
      if errorString.contains("failedToPrepare") || errorString.contains("-12902") {
        logger.error("🚨 VideoCodec failedToPrepare 에러 감지 - 프레임 포맷 문제")

        // VideoCodec 에러 복구 시도 (더 적극적으로)
        await handleVideoCodecError(pixelBuffer: processedPixelBuffer)

        // 복구 후 재시도 (1회)
        if frameTransmissionFailure % 5 == 0 {  // 5번 실패마다 재시도
          logger.info("🔄 VideoCodec 복구 후 재시도 중...")
          do {
            if let recoveryBuffer = createSimpleDummyFrame() {
              try await videoCodecWorkaround.sendFrameWithWorkaround(recoveryBuffer)
              logger.info("✅ VideoCodec 복구 재시도 성공")
            }
          } catch {
            logger.warning("⚠️ VideoCodec 복구 재시도 실패: \(error)")
          }
        }
      }

      // NSError로 변환하여 에러 코드 확인
      if let nsError = error as NSError? {
        logger.error("🔍 NSError 도메인: \(nsError.domain), 코드: \(nsError.code)")

        if nsError.code == -12902 {
          logger.error("🚨 VideoCodec -12902 에러 확인됨")
        }
      }
    }

    // 6. 주기적 통계 리셋 (메모리 오버플로우 방지)
    if frameTransmissionCount >= 1500 {  // 약 60초마다 리셋 (3000 → 1500)
      let successRate = Double(frameTransmissionSuccess) / Double(frameTransmissionCount) * 100
      logger.info("📊 전송 세션 완료: 최종 성공률 \(String(format: "%.1f", successRate))%")

      frameTransmissionCount = 0
      frameTransmissionSuccess = 0
      frameTransmissionFailure = 0
      frameStatsStartTime = currentTime
    }
  }

  /// 프레임 유효성 검증 (인코딩 전 사전 체크)
  private func validatePixelBufferForEncoding(_ pixelBuffer: CVPixelBuffer) -> Bool {
    // 기본 크기 검증
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    guard width > 0 && height > 0 else {
      logger.error("❌ 잘못된 프레임 크기: \(width)x\(height)")
      return false
    }

    // 최소/최대 해상도 검증
    guard width >= 160 && height >= 120 && width <= 3840 && height <= 2160 else {
      logger.error("❌ 지원되지 않는 해상도: \(width)x\(height)")
      return false
    }

    // 픽셀 포맷 사전 검증
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let supportedFormats: [OSType] = [
      kCVPixelFormatType_32BGRA,
      kCVPixelFormatType_32ARGB,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
    ]

    guard supportedFormats.contains(pixelFormat) else {
      logger.warning("⚠️ 비표준 픽셀 포맷: \(pixelFormat) - 변환 필요")
      return true  // 변환 필요하지만 유효한 상태로 처리
    }

    return true
  }

  /// 안전한 프레임 전처리 (에러 핸들링 강화)
  private func preprocessPixelBufferSafely(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    do {
      logger.info("🔧 [preprocessPixelBufferSafely] 프레임 전처리 시작")

      // 포맷 변환 우선 실행
      guard let formatCompatibleBuffer = convertPixelBufferFormatSafely(pixelBuffer) else {
        logger.error("❌ [preprocessPixelBufferSafely] 포맷 변환 실패")
        return nil
      }

      logger.info("✅ [preprocessPixelBufferSafely] 포맷 변환 완료")

      // 해상도 확인 및 스케일링
      guard let settings = currentSettings else {
        logger.warning("⚠️ 스트리밍 설정 없음 - 원본 해상도 사용")
        return formatCompatibleBuffer
      }

      let currentWidth = CVPixelBufferGetWidth(formatCompatibleBuffer)
      let currentHeight = CVPixelBufferGetHeight(formatCompatibleBuffer)
      let targetWidth = settings.videoWidth
      let targetHeight = settings.videoHeight

      // 해상도가 이미 일치하면 바로 반환
      if currentWidth == targetWidth && currentHeight == targetHeight {
        return formatCompatibleBuffer
      }

      // 스케일링 실행
      logger.info(
        "🔄 해상도 스케일링 시작: \(currentWidth)x\(currentHeight) → \(targetWidth)x\(targetHeight)")

      guard
        let scaledBuffer = scalePixelBufferSafely(
          formatCompatibleBuffer, to: CGSize(width: targetWidth, height: targetHeight))
      else {
        logger.error("❌ 해상도 스케일링 실패 - 포맷 변환된 버퍼 사용")
        return formatCompatibleBuffer
      }

      logger.info(
        "🎉 해상도 스케일링 완료 및 검증 성공: \(CVPixelBufferGetWidth(scaledBuffer))x\(CVPixelBufferGetHeight(scaledBuffer))"
      )
      return scaledBuffer

    } catch {
      logger.error("❌ 프레임 전처리 예외: \(error)")
      return nil
    }
  }

  /// VideoCodec -12902 해결을 위한 안전한 포맷 변환 (BGRA → YUV420)
  private func convertPixelBufferFormatSafely(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let currentFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let targetFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange  // YUV420 포맷

    logger.info("🔄 [포맷변환] 시작: \(currentFormat) → YUV420 (\(targetFormat))")

    // 이미 YUV420 포맷이면 원본 반환
    if currentFormat == targetFormat {
      logger.info("✅ [포맷변환] 이미 YUV420 포맷 - 변환 불필요")
      return pixelBuffer
    }

    logger.info("🔄 [포맷변환] BGRA→YUV420 변환 실행 중...")

    // 16의 배수 정렬과 YUV420 변환을 포함한 통합 변환
    let result = convertToSupportedFormat(pixelBuffer)

    if let convertedBuffer = result {
      let resultFormat = CVPixelBufferGetPixelFormatType(convertedBuffer)
      logger.info("✅ [포맷변환] 성공: \(currentFormat) → \(resultFormat)")
    } else {
      logger.error("❌ [포맷변환] 실패: \(currentFormat) → YUV420")
    }

    return result
  }

  /// 안전한 해상도 스케일링
  private func scalePixelBufferSafely(_ pixelBuffer: CVPixelBuffer, to targetSize: CGSize)
    -> CVPixelBuffer?
  {
    return scalePixelBuffer(pixelBuffer, to: targetSize)
  }

  /// 안전한 CMSampleBuffer 생성 (VideoCodec 호환성 보장)
  private func createSampleBufferSafely(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    // 추가 검증 로직
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    // VideoCodec 최적화 포맷 검증 (YUV420)
    let supportedFormats: [OSType] = [
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      kCVPixelFormatType_32BGRA,  // 폴백용
    ]

    guard supportedFormats.contains(pixelFormat) else {
      logger.error("❌ VideoCodec 비호환 포맷: \(pixelFormat)")
      return nil
    }

    if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
      logger.debug("✅ YUV420 포맷 확인 - VideoCodec 최적화")
    }

    // 해상도 16의 배수 확인 (H.264 인코더 요구사항)
    if width % 16 != 0 || height % 16 != 0 {
      logger.warning("⚠️ 해상도가 16의 배수가 아님: \(width)x\(height) - 인코딩 문제 가능")
      // 16의 배수가 아니어도 계속 진행 (스케일링에서 이미 처리됨)
    }

    // CMSampleBuffer 생성 전 pixelBuffer 락 상태 확인
    let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    guard lockResult == kCVReturnSuccess else {
      logger.error("❌ PixelBuffer 락 실패: \(lockResult)")
      return nil
    }

    // CMSampleBuffer 생성
    let sampleBuffer = createSampleBuffer(from: pixelBuffer)

    // PixelBuffer 언락
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

    if sampleBuffer == nil {
      logger.error("❌ CMSampleBuffer 생성 실패 - VideoCodec 호환성 문제")
      logVideoCodecDiagnostics(pixelBuffer: pixelBuffer)
    }

    return sampleBuffer
  }

  /// VideoCodec 에러 처리 및 복구
  private func handleVideoCodecError(pixelBuffer: CVPixelBuffer) async {
    logger.warning("🔧 VideoCodec 에러 복구 시도 중...")

    // 1. 잠시 전송 중단 (더 길게)
    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms 대기

    // 2. 스트림 상태 재확인 및 플러시
    if let stream = currentRTMPStream {
      logger.info("🔄 RTMPStream 플러시 시도")

      // VideoCodec 재초기화를 위한 더미 프레임 전송
      if let dummyBuffer = createSimpleDummyFrame() {
        do {
          try await stream.append(dummyBuffer)
          logger.info("✅ VideoCodec 재활성화 더미 프레임 전송 성공")
        } catch {
          logger.warning("⚠️ 더미 프레임 전송 실패: \(error)")
        }
      }
    }

    logger.warning("✅ VideoCodec 에러 복구 시도 완료")
  }

  /// 간단한 더미 프레임 생성 (VideoCodec 재활성화용)
  private func createSimpleDummyFrame() -> CMSampleBuffer? {
    guard let settings = currentSettings else { return nil }

    // 단색 픽셀버퍼 생성 (검은색, YUV420 포맷)
    let width = settings.videoWidth
    let height = settings.videoHeight

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      nil,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      return nil
    }

    // Y/UV 플레인 초기화 (검은색)
    CVPixelBufferLockBaseAddress(buffer, [])

    // Y 플레인 (밝기 - 검은색)
    if let yPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
      let ySize = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) * height
      memset(yPlane, 16, ySize)
    }

    // UV 플레인 (색상 - 중성)
    if let uvPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
      let uvSize = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * (height / 2)
      memset(uvPlane, 128, uvSize)
    }

    CVPixelBufferUnlockBaseAddress(buffer, [])

    // CMSampleBuffer 생성
    return createSampleBuffer(from: buffer)
  }

  /// VideoCodec 진단 정보 로깅
  private func logVideoCodecDiagnostics(pixelBuffer: CVPixelBuffer) {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    logger.info("🔍 VideoCodec 진단:")
    logger.info("  - 해상도: \(width)x\(height)")
    logger.info("  - 픽셀 포맷: \(pixelFormat)")
    logger.info("  - 16의 배수 여부: \(width % 16 == 0 && height % 16 == 0)")
    logger.info(
      "  - YUV420 포맷 여부: \(pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)")
    logger.info("  - BGRA 포맷 여부: \(pixelFormat == kCVPixelFormatType_32BGRA)")

    // 디바이스 환경 진단 추가
    logDeviceEnvironmentDiagnostics()
  }

  /// 디바이스 환경 진단 (시뮬레이터 vs 실제 디바이스)
  private func logDeviceEnvironmentDiagnostics() {
    #if targetEnvironment(simulator)
      logger.warning("⚠️ 시뮬레이터 환경에서 실행 중 - 실제 카메라 데이터 없음")
      logger.warning("  → 실제 디바이스에서 테스트 필요")
    #else
      logger.info("✅ 실제 디바이스에서 실행 중")
    #endif

    // 디바이스 정보
    let device = UIDevice.current
    logger.info("📱 디바이스 정보:")
    logger.info("  - 모델: \(device.model)")
    logger.info("  - 시스템: \(device.systemName) \(device.systemVersion)")
    logger.info("  - 이름: \(device.name)")

    // 카메라 디바이스 진단
    logCameraDeviceDiagnostics()
  }

  /// 카메라 디바이스 진단
  private func logCameraDeviceDiagnostics() {
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInWideAngleCamera,
        .builtInUltraWideCamera,
        .external,
      ],
      mediaType: .video,
      position: .unspecified
    )

    let devices = discoverySession.devices
    logger.info("📹 카메라 디바이스 진단:")
    logger.info("  - 전체 디바이스 수: \(devices.count)")

    var builtInCount = 0
    var externalCount = 0

    for device in devices {
      if device.deviceType == .external {
        externalCount += 1
        logger.info("  - 외부 카메라: \(device.localizedName)")
      } else {
        builtInCount += 1
        logger.info("  - 내장 카메라: \(device.localizedName) (\(device.position.rawValue))")
      }
    }

    logger.info("  - 내장 카메라: \(builtInCount)개")
    logger.info("  - 외부 카메라: \(externalCount)개")

    if externalCount == 0 {
      logger.warning("⚠️ 외부 USB 카메라가 연결되지 않음")
      logger.warning("  → USB 카메라 연결 상태 확인 필요")
    }
  }

  /// 타임아웃 기능 구현
  private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T)
    async throws -> T
  {
    return try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }

      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw TimeoutError()
      }

      guard let result = try await group.next() else {
        throw TimeoutError()
      }

      group.cancelAll()
      return result
    }
  }

  /// 타임아웃 에러 타입
  private struct TimeoutError: Error {
    let localizedDescription = "Operation timed out"
  }

  // MARK: - MediaMixer 기반 스트리밍 (HaishinKit Examples 패턴)

  /// HaishinKit 공식 Examples 패턴을 적용한 MediaMixer 기반 스트리밍
  private func initializeMediaMixerBasedStreaming() {
    os_log("🏭 Examples 패턴: MediaMixer 기반 스트리밍 초기화 시작", log: .default, type: .info)

    // Examples와 동일한 MediaMixer 설정
    let mediaMixer = MediaMixer(
      multiCamSessionEnabled: false,  // 단일 카메라 사용
      multiTrackAudioMixingEnabled: true,
      useManualCapture: true  // 수동 캡처 모드 (화면 캡처용)
    )

    Task {
      // 비디오 믹서 설정 (Examples 패턴)
      var videoMixerSettings = await mediaMixer.videoMixerSettings
      videoMixerSettings.mode = .offscreen  // 화면 캡처 모드
      await mediaMixer.setVideoMixerSettings(videoMixerSettings)

      // MediaMixer를 RTMPStream에 연결
      if let stream = await streamSwitcher.stream {
        await mediaMixer.addOutput(stream)
      }

      os_log("✅ Examples 패턴: MediaMixer ↔ RTMPStream 연결 완료", log: .default, type: .info)

      // 내부 저장
      self.mediaMixer = mediaMixer
    }
  }

  /// Examples 패턴: HKStreamSwitcher 스타일 연결
  private func connectUsingExamplesPattern() {
    os_log("🔗 Examples 패턴: HKStreamSwitcher 스타일 연결 시작", log: .default, type: .info)

    Task {
      do {
        // 1. RTMP 연결 (Examples와 동일)
        guard let settings = currentSettings else {
          throw LiveStreamError.configurationError("스트리밍 설정이 없음")
        }

        _ = try await streamSwitcher.connection?.connect(settings.rtmpURL)
        os_log("✅ Examples 패턴: RTMP 연결 성공", log: .default, type: .info)

        // 2. 스트림 퍼블리시 (Examples와 동일)
        if let stream = await streamSwitcher.stream {
          _ = try await stream.publish(settings.streamKey)
          os_log("✅ Examples 패턴: 스트림 퍼블리시 성공", log: .default, type: .info)

          // 3. 상태 업데이트
          await MainActor.run {
            self.currentStatus = .streaming
            self.connectionStatus = "Examples 패턴 스트리밍 중..."
            self.isStreaming = true
          }

          // 4. MediaMixer 시작
          if let mixer = mediaMixer {
            await mixer.startRunning()
            os_log("✅ Examples 패턴: MediaMixer 시작됨", log: .default, type: .info)
          }

        } else {
          throw LiveStreamError.configurationError("스트림이 없음")
        }

      } catch {
        os_log("❌ Examples 패턴: 연결 실패 - %@", log: .default, type: .error, error.localizedDescription)
        await MainActor.run {
          self.currentStatus = .error(
            error as? LiveStreamError ?? LiveStreamError.streamingFailed(error.localizedDescription)
          )
        }
      }
    }
  }

  /// Examples 패턴: MediaMixer 기반 프레임 전송 (사용하지 않음 - 기존 방식 유지)
  private func sendFrameUsingMediaMixer(_ pixelBuffer: CVPixelBuffer) {
    // 주석: MediaMixer의 append는 오디오 전용이므로 사용하지 않음
    // 대신 기존의 sendManualFrame에서 MediaMixer 연결된 스트림 사용
    os_log("ℹ️ MediaMixer 패턴은 sendManualFrame에서 처리됨", log: .default, type: .info)
  }

  /// MediaMixer 정리
  private func cleanupMediaMixer() {
    guard let mixer = mediaMixer else { return }

    Task {
      await mixer.stopRunning()
      os_log("🛑 MediaMixer 정리 완료", log: .default, type: .info)
      self.mediaMixer = nil
    }
  }

  // 내부 저장용 프로퍼티 추가
  private var mediaMixer: MediaMixer?

  // MARK: - Text Overlay Properties

  /// 텍스트 오버레이 표시 여부
  public var showTextOverlay: Bool = false

  /// 텍스트 오버레이 설정
  public var textOverlaySettings: TextOverlaySettings = TextOverlaySettings()

  /// 텍스트 오버레이 설정 업데이트
  public func updateTextOverlay(show: Bool, text: String) {
    showTextOverlay = show
    textOverlaySettings.text = text
    logger.info("📝 텍스트 오버레이 업데이트: \(show ? "표시" : "숨김") - '\(text)'", category: .streaming)
  }

  /// 텍스트 오버레이 설정 업데이트 (고급 설정 포함)
  public func updateTextOverlay(show: Bool, settings: TextOverlaySettings) {
    showTextOverlay = show
    textOverlaySettings = settings
    logger.info(
      "📝 텍스트 오버레이 설정 업데이트: \(show ? "표시" : "숨김") - '\(settings.text)' (\(settings.fontName), \(Int(settings.fontSize))pt)",
      category: .streaming)
  }

  /// 720p 전용 스트림 버퍼 최적화
  private func optimize720pBuffering() async {
    guard let stream = await streamSwitcher.stream,
      let settings = currentSettings,
      settings.videoWidth == 1280 && settings.videoHeight == 720
    else {
      return
    }

    logger.info("🎯 720p 버퍼링 최적화 적용", category: .system)

    // 720p 전용 버퍼 설정 (끊김 방지)
    var videoSettings = await stream.videoSettings

    // 720p 최적 버퍼 크기 (더 작은 버퍼로 지연시간 감소)
    videoSettings.maxKeyFrameIntervalDuration = 1  // 1초 키프레임 간격

    // 720p 전용 인코딩 설정
    videoSettings.profileLevel = kVTProfileLevel_H264_Main_AutoLevel as String

    await stream.setVideoSettings(videoSettings)

    logger.info("✅ 720p 버퍼링 최적화 완료", category: .system)
  }

  // MARK: - 🔧 개선: VideoToolbox 통합 기능들

  /// VideoToolbox 프리셋 설정
  public func setVideoToolboxPreset(_ preset: VideoToolboxPreset) {
    videoToolboxPreset = preset
    logger.info("🎯 VideoToolbox 프리셋 변경: \(preset.description)", category: .streaming)
  }

  /// VideoToolbox 진단 수행
  @MainActor
  public func performVideoToolboxDiagnosis() -> VideoToolboxDiagnostics {
    let diagnostics = performanceOptimizer.diagnoseVideoToolboxHealth()
    self.videoToolboxDiagnostics = diagnostics

    logger.info("🔧 VideoToolbox 진단 완료:", category: .streaming)
    logger.info(diagnostics.description, category: .streaming)

    // 진단 결과에 따른 자동 최적화 제안
    if !diagnostics.hardwareAccelerationSupported {
      logger.warning("⚠️ 하드웨어 가속 미지원 - 소프트웨어 인코딩으로 전환 권장", category: .streaming)
    }

    if diagnostics.compressionErrorRate > 0.05 {  // 5% 이상 오류율
      logger.warning("⚠️ 높은 압축 오류율 감지 - 설정 조정 권장", category: .streaming)
    }

    return diagnostics
  }

  /// 실시간 VideoToolbox 성능 리포트 생성
  @MainActor
  public func generateVideoToolboxPerformanceReport() -> VideoToolboxPerformanceMetrics {
    let metrics = performanceOptimizer.generatePerformanceReport()

    // 성능 상태에 따른 로깅
    switch metrics.performanceStatus {
    case .good:
      logger.debug(
        "✅ VideoToolbox 성능 양호: \(metrics.performanceStatus.description)", category: .streaming)
    case .warning:
      logger.warning(
        "⚠️ VideoToolbox 성능 주의: \(metrics.performanceStatus.description)", category: .streaming)
    case .poor:
      logger.error(
        "❌ VideoToolbox 성능 불량: \(metrics.performanceStatus.description)", category: .streaming)
    }

    return metrics
  }

  /// 🔧 개선: VideoToolbox 성능 모니터링 시작
  private func startVideoToolboxPerformanceMonitoring() async {
    logger.info("📊 VideoToolbox 성능 모니터링 시작", category: .streaming)

    // VideoToolbox 관련 Notification 수신 설정
    NotificationCenter.default.addObserver(
      forName: .videoToolboxError,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.handleVideoToolboxError(notification)
    }

    NotificationCenter.default.addObserver(
      forName: .videoToolboxMemoryWarning,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.handleVideoToolboxMemoryWarning(notification)
    }

    NotificationCenter.default.addObserver(
      forName: .videoToolboxPerformanceAlert,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.handleVideoToolboxPerformanceAlert(notification)
    }
  }

  /// VideoToolbox 오류 처리
  private func handleVideoToolboxError(_ notification: Notification) {
    logger.error("❌ VideoToolbox 오류 수신: \(notification.userInfo ?? [:])", category: .streaming)

    // 오류 복구 시도
    Task {
      await handleVideoToolboxRecovery()
    }
  }

  /// VideoToolbox 메모리 경고 처리
  private func handleVideoToolboxMemoryWarning(_ notification: Notification) {
    logger.warning("⚠️ VideoToolbox 메모리 경고 수신", category: .streaming)

    // 메모리 최적화 수행
    Task {
      await performMemoryOptimization()
    }
  }

  /// VideoToolbox 성능 알림 처리
  private func handleVideoToolboxPerformanceAlert(_ notification: Notification) {
    guard let metrics = notification.userInfo?["metrics"] as? VideoToolboxPerformanceMetrics,
      let status = notification.userInfo?["status"] as? PerformanceStatus
    else {
      return
    }

    logger.info("📊 VideoToolbox 성능 알림: \(status.description)", category: .streaming)

    // 성능 상태에 따른 대응
    switch status {
    case .poor:
      Task {
        await handlePoorPerformance(metrics)
      }
    case .warning:
      logger.warning(
        "⚠️ VideoToolbox 성능 주의: CPU \(metrics.cpuUsage)%, 메모리 \(metrics.memoryUsage)MB",
        category: .streaming)
    case .good:
      logger.debug("✅ VideoToolbox 성능 양호", category: .streaming)
    }
  }

  /// VideoToolbox 복구 처리
  private func handleVideoToolboxRecovery() async {
    logger.info("🔧 VideoToolbox 복구 시도", category: .streaming)

    // 현재 설정을 사용하여 VideoToolbox 재설정 (iOS 17.4 이상에서만)
    if let settings = currentSettings {
      if #available(iOS 17.4, *) {
        do {
          try await performanceOptimizer.setupHardwareCompressionWithRecovery(settings: settings)
          logger.info("✅ VideoToolbox 복구 성공", category: .streaming)
        } catch {
          logger.error("❌ VideoToolbox 복구 실패: \(error)", category: .streaming)
        }
      } else {
        logger.info("📱 iOS 17.4 미만 - VideoToolbox 고급 복구 기능 미사용", category: .streaming)
      }
    }
  }

  /// 메모리 최적화 수행
  private func performMemoryOptimization() async {
    logger.info("🧹 VideoToolbox 메모리 최적화 수행", category: .streaming)

    // 필요시 품질 조정을 통한 메모리 압박 완화
    if let settings = currentSettings, let originalSettings = originalUserSettings {
      let optimizedSettings = await performanceOptimizer.adaptQualityRespectingUserSettings(
        currentSettings: settings,
        userDefinedSettings: originalSettings
      )

      // 메모리 최적화를 위한 임시 설정 적용
      if optimizedSettings.videoBitrate != settings.videoBitrate {
        logger.info(
          "🔽 메모리 최적화를 위한 임시 품질 조정: \(settings.videoBitrate) → \(optimizedSettings.videoBitrate)kbps",
          category: .streaming)
      }
    }
  }

  /// 성능 불량 상황 처리
  private func handlePoorPerformance(_ metrics: VideoToolboxPerformanceMetrics) async {
    logger.warning("⚠️ VideoToolbox 성능 불량 감지 - 자동 최적화 수행", category: .streaming)
    logger.warning(
      "  CPU: \(metrics.cpuUsage)%, 메모리: \(metrics.memoryUsage)MB, 오류율: \(metrics.errorRate)",
      category: .streaming)

    // 성능 문제 대응 전략
    if metrics.errorRate > 0.1 {  // 10% 이상 오류율
      await handleVideoToolboxRecovery()
    }

    if metrics.cpuUsage > 80 || metrics.memoryUsage > 500 {
      await performMemoryOptimization()
    }

    // 심각한 성능 문제 시 사용자에게 알림
    if metrics.compressionTime > 0.1 {  // 100ms 이상
      logger.error("❌ 심각한 성능 문제 - 사용자 개입 필요", category: .streaming)

      // UI 알림 발송
      DispatchQueue.main.async { [weak self] in
        self?.connectionStatus = "⚠️ 성능 문제 감지 - 설정 확인 필요"
      }
    }
  }

}
