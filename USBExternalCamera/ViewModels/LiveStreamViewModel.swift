//
//  LiveStreamViewModel.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 6/5/25.
//
import AVFoundation
import Combine
import Foundation
import LiveStreamingCore
import SwiftData
import SwiftUI
/// 라이브 스트리밍 뷰모델 (MVVM 아키텍처)
/// Services Layer를 통해 Data와 Network Layer에 접근하여 UI 상태를 관리합니다.
@MainActor
final class LiveStreamViewModel: ObservableObject {
  // MARK: - Constants
  enum Constants {
    static let dataMonitoringInterval: TimeInterval = 5.0
    static let statusTransitionDelay: UInt64 = 500_000_000  // 0.5초
    static let minimumStreamKeyLength = 16
    static let youtubeRTMPURL = "rtmp://a.rtmp.youtube.com/live2/"
    static let defaultVideoBitrate = 2500
    static let defaultAudioBitrate = 128
    static let defaultVideoWidth = 1280
    static let defaultVideoHeight = 720
    static let defaultFrameRate = 30
  }
  // MARK: - Published Properties
  /// 현재 라이브 스트리밍 설정
  @Published var settings: LiveStreamSettings
  /// 스트리밍 상태
  @Published var status: LiveStreamStatus = .idle
  /// 상태 메시지
  @Published var statusMessage: String = ""
  /// 스트림 통계 정보
  @Published var streamStats: StreamStats = StreamStats()
  /// 설정 뷰 표시 여부
  @Published var showingSettings: Bool = false
  /// 오류 알림 표시 여부
  @Published var showingErrorAlert: Bool = false
  /// 현재 오류 메시지
  @Published var currentErrorMessage: String = ""
  /// 스트리밍 가능 여부
  @Published var canStartStreaming: Bool = false
  /// 네트워크 권장 설정
  @Published var networkRecommendations: StreamingRecommendations?
  /// 연결 정보
  @Published var connectionInfo: ConnectionInfo?
  /// 연결 테스트 결과
  @Published var connectionTestResult: String = ""
  /// 실시간 데이터 송출 통계 (실제 HaishinKitManager에서 가져옴)
  @Published var transmissionStats: DataTransmissionStats = DataTransmissionStats()
  /// 네트워크 품질 상태
  @Published var networkQuality: NetworkQuality = .unknown
  /// 로딩 상태 (스트리밍 시작/중지 중)
  @Published var isLoading: Bool = false
  /// 실시간 마이크 피크 레벨(0.0~1.0)
  @Published var microphonePeakLevel: Float = 0.0
  /// 실시간 마이크 피크 dBFS 값(-80~0)
  @Published var microphonePeakDecibels: Float = -80.0
  /// 마이크 음소거 상태
  @Published var isMicrophoneMuted: Bool = false
  /// 사용 가능한 마이크 입력 목록 (자동 포함)
  @Published var availableMicrophoneInputs: [MicrophoneInputOption] = []
  /// 선택된 마이크 입력 ID
  @Published var selectedMicrophoneInputID: String = MicrophoneInputOption.automaticID
  /// 현재 활성화된 오디오 입력 이름
  @Published var activeMicrophoneInputName: String = ""
  /// 오디오 피크 샘플 수신 카운트 (진단용)
  @Published var audioPeakSampleCount: Int = 0
  /// 오디오 피크 진단 메시지
  @Published var audioPeakDiagnosticMessage: String = ""
  /// 적응형 품질 조정 활성화 여부 (사용자 설정 보장을 위해 기본값: false)
  @Published var adaptiveQualityEnabled: Bool = false {
    didSet {
      if let haishinKitManager = liveStreamService as? HaishinKitManager {
        haishinKitManager.setAdaptiveQualityEnabled(adaptiveQualityEnabled)
      }
    }
  }
  /// 현재 스트리밍 중인지 여부
  var isStreaming: Bool {
    return status == .streaming
  }
  // MARK: - Computed Properties
  var streamingStatus: LiveStreamStatus {
    return status
  }
  // 기존 일반 스트리밍 버튼 관련 속성들 제거 - 화면 캡처 스트리밍만 사용
  // MARK: - Dependencies
  /// 라이브 스트리밍 서비스 (Services Layer)
  /// - Note: 초기화 시점에 반드시 할당되므로 안전하게 사용 가능
  internal let liveStreamService: HaishinKitManagerProtocol
  /// 라이브 스트리밍 서비스 접근자 (카메라 연결용)
  public var streamingService: HaishinKitManagerProtocol? {
    return liveStreamService
  }
  /// 스트림 오디오 피크 분석용 출력 옵저버
  var audioPeakObserver: StreamAudioPeakOutputObserver?
  /// 피크 미터의 자연 감쇠 타이머
  var audioPeakDecayTimer: Timer?
  /// 오디오 피크 마지막 샘플 수신 시각
  var audioPeakLastSampleAt: Date?
  /// 오디오 피크 헬스체크 태스크
  var audioPeakHealthCheckTask: Task<Void, Never>?
  /// 대기 상태 오디오 피크 모니터(로컬 마이크 입력)
  var idleMicrophonePeakMonitor: IdleMicrophonePeakMonitor?
  /// 스트리밍 전환 중 대기 모니터 일시중지 플래그
  var isIdleMicrophonePeakMonitoringSuspended: Bool = false
  /// 오디오 라우트 변경 감지 옵저버
  var audioRouteChangeObserver: NSObjectProtocol?
  /// Combine 구독 저장소
  var cancellables = Set<AnyCancellable>()
  // MARK: - Initialization
  /// 라이브 스트리밍 뷰모델 초기화
  /// - Parameters:
  ///   - modelContext: SwiftData 모델 컨텍스트
  ///   - liveStreamService: 스트리밍 서비스 (테스트 시 Mock 주입 가능, 기본값: HaishinKitManager)
  init(modelContext: ModelContext, liveStreamService: HaishinKitManagerProtocol? = nil) {
    self.settings = Self.createDefaultSettings()
    self.liveStreamService = liveStreamService ?? HaishinKitManager()
    setupBindings()
    startMicrophonePeakDecayTimerIfNeeded()
    setupMicrophoneInputMonitoring()
    updateStreamingAvailability()
    startIdleMicrophonePeakMonitoringIfNeeded()
    loadInitialSettings()
    logInitializationInfo()
  }

  deinit {
    audioPeakDecayTimer?.invalidate()
    audioPeakDecayTimer = nil
    audioPeakHealthCheckTask?.cancel()
    audioPeakHealthCheckTask = nil
    idleMicrophonePeakMonitor?.stop()
    idleMicrophonePeakMonitor = nil

    if let audioRouteChangeObserver {
      NotificationCenter.default.removeObserver(audioRouteChangeObserver)
      self.audioRouteChangeObserver = nil
    }
  }
  // MARK: - Public Methods - Streaming Control
  // 기존 일반 스트리밍 시작/중지 메서드들 제거 - 화면 캡처 스트리밍만 사용
  // 기존 일반 스트리밍 toggleStreaming 메서드 제거 - 화면 캡처 스트리밍만 사용
  // MARK: - Screen Capture Streaming Methods
  /// 🎬 화면 캡처 스트리밍 기능 섹션
  ///
  /// **화면 캡처 스트리밍이란?**
  /// CameraPreviewContainerView의 화면(카메라 영상 + UI 오버레이)을
  /// 실시간으로 캡처하여 스트리밍 서버로 송출하는 기능입니다.
  ///
  /// **일반 스트리밍과의 차이점:**
  /// - 일반 스트리밍: 카메라 영상만 전송
  /// - 화면 캡처 스트리밍: 카메라 영상 + UI 요소(버튼, 라벨, 워터마크 등) 합성 전송
  ///
  /// **기술적 구현:**
  /// 1. 실시간 카메라 프레임 캡처 (CVPixelBuffer)
  /// 2. UI 레이어 렌더링 (CALayer → UIImage)
  /// 3. 카메라 프레임과 UI 합성 (Core Graphics)
  /// 4. 30fps로 HaishinKit을 통해 서버 전송
  /// 화면 캡처 스트리밍 시작
  ///
  /// **동작 과정:**
  /// 1. 스트리밍 서비스 초기화 및 서버 연결
  /// 2. CameraPreviewView에 화면 캡처 시작 신호 전송
  /// 3. 30fps 타이머 기반 실시간 화면 캡처 시작
  /// 4. 캡처된 프레임을 HaishinKit을 통해 서버로 전송
  ///
  /// **상태 변화:**
  /// idle → connecting → connected → streaming
  ///
  /// **에러 처리:**
  /// - 서비스 초기화 실패 시 자동으로 중지 상태로 복원
  /// - 네트워크 오류 시 사용자에게 알림 표시
  func startScreenCaptureStreaming() async {
    logInfo("🎬 Starting screen capture streaming mode...", category: .streaming)
    suspendIdleMicrophonePeakMonitoringForStreaming()
    // UI 로딩 상태 시작
    isLoading = true
    await updateStatus(
      .connecting,
      message: NSLocalizedString("screen_capture_connecting", comment: "화면 캡처 스트리밍 연결 중..."))
    do {
      // Step 1: 스트리밍 서비스 초기화 및 서버 연결
      try await performScreenCaptureStreamingStart()
      // Step 2: 성공 시 후처리 (화면 캡처 시작 신호 전송)
      await handleScreenCaptureStreamingStartSuccess()
    } catch {
      // Step 3: 실패 시 복구 처리
      await handleScreenCaptureStreamingStartFailure(error)
    }
    // UI 로딩 상태 종료
    isLoading = false
  }
  /// 화면 캡처 스트리밍 토글 (시작/중지)
  ///
  /// 사용자가 사이드바의 "스트리밍 시작 - 캡처" 버튼을 눌렀을 때 호출됩니다.
  /// 현재 상태에 따라 시작 또는 중지 동작을 수행합니다.
  ///
  /// **상태별 동작:**
  /// - idle/error: 화면 캡처 스트리밍 시작
  /// - connected/streaming: 화면 캡처 스트리밍 중지
  /// - connecting/disconnecting: 무시 (이미 상태 변경 중)
  ///
  /// **Thread Safety:**
  /// 비동기 처리를 통해 UI 블록킹을 방지합니다.
  func toggleScreenCaptureStreaming() {
    logDebug(
      "🎮 [TOGGLE] Screen capture streaming toggle - Current status: \(status)", category: .streaming
    )
    switch status {
    case .idle, .error:
      // 화면 캡처 스트리밍 시작
      Task { await startScreenCaptureStreaming() }
    case .connected, .streaming:
      // 화면 캡처 스트리밍 중지
      Task { await stopScreenCaptureStreaming() }
    case .connecting, .disconnecting:
      // 이미 상태 변경 중이므로 무시
      logDebug(
        "🎮 [TOGGLE] Ignoring toggle - already in transition state: \(status)", category: .streaming)
    }
  }
  /// 화면 캡처 스트리밍 중지
  ///
  /// **동작 과정:**
  /// 1. CameraPreviewView에 화면 캡처 중지 신호 전송
  /// 2. 스트리밍 서버 연결 해제
  /// 3. 관련 리소스 정리 및 상태 초기화
  ///
  /// **상태 변화:**
  /// streaming → disconnecting → idle
  ///
  /// **리소스 정리:**
  /// - 화면 캡처 타이머 중지
  /// - 캡처된 프레임 메모리 해제
  /// - HaishinKit 연결 해제
  func stopScreenCaptureStreaming() async {
    logInfo("🎬 Stopping screen capture streaming...", category: .streaming)
    isLoading = true
    await updateStatus(
      .disconnecting,
      message: NSLocalizedString("screen_capture_disconnecting", comment: "화면 캡처 중지 중"))
    do {
      // Step 1: 스트리밍 서비스 중지 및 화면 캡처 중지 신호 전송
      try await performScreenCaptureStreamingStop()
      // Step 2: 성공 시 상태 초기화
      await handleScreenCaptureStreamingStopSuccess()
    } catch {
      // Step 3: 실패 시에도 강제로 상태 초기화 (안전장치)
      await handleScreenCaptureStreamingStopFailure(error)
    }
    isLoading = false
  }
  /// 화면 캡처 스트리밍이 활성 상태인지 확인
  var isScreenCaptureStreaming: Bool {
    if status == .streaming {
      return true
    }
    guard let haishinKitManager = liveStreamService as? HaishinKitManager else { return false }
    return haishinKitManager.isScreenCaptureMode && haishinKitManager.isStreaming
  }
  /// 화면 캡처 스트리밍 버튼 텍스트
  var screenCaptureButtonText: String {
    if isScreenCaptureStreaming {
      return NSLocalizedString("screen_capture_stop", comment: "화면 캡처 중지")
    } else {
      return StreamingButtonHelper.screenCaptureButtonText(for: status)
    }
  }
  /// 화면 캡처 스트리밍 버튼 색상
  var screenCaptureButtonColor: Color {
    if isScreenCaptureStreaming {
      return .red
    } else {
      return StreamingButtonHelper.buttonColor(for: status)
    }
  }
  /// 스트리밍 버튼 텍스트
  var streamingButtonText: String {
    if isScreenCaptureStreaming {
      return NSLocalizedString("screen_capture_stop", comment: "화면 캡처 중지")
    } else {
      return StreamingButtonHelper.streamingButtonText(for: status)
    }
  }
  /// 스트리밍 버튼 색상
  var streamingButtonColor: Color {
    if isScreenCaptureStreaming {
      return .red
    } else {
      return StreamingButtonHelper.buttonColor(for: status)
    }
  }
  /// 화면 캡처 스트리밍 버튼 활성화 상태
  var isScreenCaptureButtonEnabled: Bool {
    switch status {
    case .connecting, .disconnecting:
      return false
    default:
      return canStartStreaming || isScreenCaptureStreaming
    }
  }
}
