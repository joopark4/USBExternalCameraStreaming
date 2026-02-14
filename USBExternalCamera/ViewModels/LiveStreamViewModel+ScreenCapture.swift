import AVFoundation
import Combine
import Foundation
import LiveStreamingCore
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Screen Capture Streaming Private Methods
  /// 화면 캡처 스트리밍 시작 실행 (내부 메서드)
  ///
  /// **실행 단계:**
  /// 1. 스트리밍 서비스 유효성 검사
  /// 2. HaishinKit 초기화 및 서버 연결
  /// 3. 데이터 모니터링 시작
  /// **예외 처리:**
  /// - 서비스 미초기화: LiveStreamError.configurationError
  /// - 네트워크 연결 실패: LiveStreamError.networkError
  /// - 기타 오류: 원본 에러 전파
  /// - Throws: LiveStreamError 또는 기타 스트리밍 관련 에러
  func performScreenCaptureStreamingStart() async throws {
    guard let haishinKitManager = liveStreamService as? HaishinKitManager else {
      throw LiveStreamError.configurationError("HaishinKitManager가 초기화되지 않았습니다")
    }

    try await prepareAudioCapturePrerequisites()

    logDebug("🔄 [화면캡처] 화면 캡처 스트리밍 시작 중...", category: .streaming)
    // 화면 캡처 전용 스트리밍 시작 (일반 스트리밍과 다른 메서드 사용)
    try await haishinKitManager.startScreenCaptureStreaming(with: settings)
    // 데이터 모니터링 시작 (네트워크 상태, FPS 등)
    startDataMonitoring()
    logInfo("✅ [화면캡처] 화면 캡처 스트리밍 서비스 시작 완료", category: .streaming)
  }
  /// 화면 캡처 스트리밍 시작 성공 후처리 (내부 메서드)
  /// **수행 작업:**
  /// 1. 스트리밍 상태를 'streaming'으로 변경
  /// 2. CameraPreviewView에 화면 캡처 시작 알림 전송
  /// 3. 성공 메시지 표시
  /// **알림 시스템:**
  /// NotificationCenter를 통해 CameraPreviewView와 통신하여
  /// 30fps 화면 캡처 타이머를 시작시킵니다.
  func handleScreenCaptureStreamingStartSuccess() async {
    logInfo("✅ [화면캡처] 스트리밍 시작 성공", category: .streaming)
    logInfo(
      "요청 설정값: \(settings.videoWidth)×\(settings.videoHeight) @ \(settings.frameRate)fps, "
        + "\(settings.videoBitrate)kbps",
      category: .streaming)
    if let haishinKitManager = liveStreamService as? HaishinKitManager,
       let activeSettings = haishinKitManager.getCurrentSettings()
    {
      logInfo(
        "매니저 반영 설정값: \(activeSettings.videoWidth)×\(activeSettings.videoHeight) @ \(activeSettings.frameRate)fps, "
          + "\(activeSettings.videoBitrate)kbps",
        category: .streaming)
      if activeSettings.videoWidth != settings.videoWidth || activeSettings.videoHeight != settings.videoHeight {
        logWarning(
          "요청 설정과 매니저 반영 설정이 다릅니다: 요청 \(settings.videoWidth)×\(settings.videoHeight) / 반영 \(activeSettings.videoWidth)×\(activeSettings.videoHeight)",
          category: .streaming)
      }
    } else {
      logWarning("매니저에서 현재 설정 조회 실패", category: .streaming)
    }
    // 상태를 'streaming'으로 업데이트
    await updateStatus(.streaming, message: "화면 캡처 송출 중")
    // CameraPreviewView에 화면 캡처 시작 신호 전송
    // 이 알림을 받으면 CameraPreviewUIView에서 30fps 타이머 시작
    DispatchQueue.main.async { [self] in
      let userInfo: [String: Any] = [
        "videoWidth": self.settings.videoWidth,
        "videoHeight": self.settings.videoHeight,
      ]
      NotificationCenter.default.post(name: .startScreenCapture, object: nil, userInfo: userInfo)
    }
    logInfo("📡 [화면캡처] 화면 캡처 시작 신호 전송 완료", category: .streaming)
  }

  /// 화면 캡처 스트리밍 시작 실패 처리 (내부 메서드)
  /// **복구 작업:**
  /// 1. 상태를 'error'로 변경
  /// 2. 사용자에게 구체적인 오류 메시지 표시
  /// 3. 관련 리소스 정리
  /// **에러 메시지 매핑:**
  /// - 네트워크 오류: "네트워크 연결을 확인해주세요"
  /// - 설정 오류: "스트리밍 설정을 확인해주세요"
  /// - 기타 오류: 원본 에러 메시지 표시
  /// - Parameter error: 발생한 오류 정보
  func handleScreenCaptureStreamingStartFailure(_ error: Error) async {
    logError("❌ [화면캡처] 스트리밍 시작 실패: \(error.localizedDescription)", category: .streaming)
    // 사용자 친화적인 에러 메시지 생성
    let userMessage: String
    if let liveStreamError = error as? LiveStreamError {
      switch liveStreamError {
      case .networkError(let message):
        userMessage = "네트워크 연결 오류: \(message)"
      case .configurationError(let message):
        userMessage = "설정 오류: \(message)"
      case .streamingFailed(let message):
        userMessage = "스트리밍 실패: \(message)"
      case .initializationFailed(let message):
        userMessage = "초기화 실패: \(message)"
      case .deviceNotFound(let message):
        userMessage = "디바이스 없음: \(message)"
      case .authenticationFailed(let message):
        userMessage = "인증 실패: \(message)"
      case .permissionDenied(let message):
        userMessage = "권한 거부: \(message)"
      case .incompatibleSettings(let message):
        userMessage = "설정 호환 불가: \(message)"
      case .connectionTimeout:
        userMessage = "연결 시간 초과"
      case .serverError(let code, let message):
        userMessage = "서버 오류 (\(code)): \(message)"
      case .unknown(let message):
        userMessage = "알 수 없는 오류: \(message)"
      }
    } else {
      userMessage = "화면 캡처 스트리밍 시작 실패: \(error.localizedDescription)"
    }
    // 에러 상태로 변경 및 메시지 표시
    await updateStatus(.error(.streamingFailed(userMessage)), message: userMessage)
  }

  /// 화면 캡처 스트리밍 중지 실행 (내부 메서드)
  /// **중지 단계:**
  /// 1. CameraPreviewView에 화면 캡처 중지 신호 전송
  /// 2. 스트리밍 서비스 연결 해제
  /// 3. 데이터 모니터링 중지
  /// **중지 순서 중요성:**
  /// 먼저 화면 캡처를 중지해야 HaishinKit으로 전송되는 프레임이 중단되고,
  /// 그 다음 서비스 연결을 해제하여 안전하게 종료됩니다.
  func performScreenCaptureStreamingStop() async throws {
    logDebug("🔄 [화면캡처] 스트리밍 서비스 중지 중...", category: .streaming)
    // Step 1: CameraPreviewView에 화면 캡처 중지 신호 전송
    // 30fps 타이머 중지 및 프레임 캡처 종료
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .stopScreenCapture, object: nil)
    }
    // Step 2: HaishinKit 스트리밍 서비스 중지
    await liveStreamService.stopStreaming()
    logInfo("✅ [화면캡처] 스트리밍 서비스 중지 완료", category: .streaming)
  }

  /// 화면 캡처 스트리밍 중지 성공 후처리 (내부 메서드)
  /// **정리 작업:**
  /// 1. 상태를 'idle'로 초기화
  /// 2. 성공 메시지 표시
  /// 3. 관련 상태 변수 초기화
  /// **상태 초기화:**
  /// 다음 화면 캡처 스트리밍을 위해 모든 상태를 초기값으로 복원합니다.
  func handleScreenCaptureStreamingStopSuccess() async {
    logInfo("✅ [화면캡처] 스트리밍 중지 성공", category: .streaming)
    // 상태를 'idle'로 초기화
    await updateStatus(.idle, message: "화면 캡처 스트리밍 준비 완료")
    logInfo("🏁 [화면캡처] 모든 리소스 정리 완료", category: .streaming)
  }

  /// 화면 캡처 스트리밍 중지 실패 처리 (내부 메서드)
  /// **안전장치 역할:**
  /// 스트리밍 중지 중 오류가 발생해도 강제로 상태를 초기화하여
  /// 사용자가 다시 스트리밍을 시작할 수 있도록 합니다.
  /// **강제 정리:**
  /// - 화면 캡처 중지 신호 재전송
  /// - 상태 강제 초기화
  /// - 모든 모니터링 중지
  func handleScreenCaptureStreamingStopFailure(_ error: Error) async {
    logError("❌ [화면캡처] 스트리밍 중지 실패: \(error.localizedDescription)", category: .streaming)
    // 강제로 화면 캡처 중지 신호 재전송 (안전장치)
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .stopScreenCapture, object: nil)
    }
    // 강제로 상태 초기화 (사용자가 다시 시도할 수 있도록)
    await updateStatus(.idle, message: "스트리밍 중지됨 (오류 복구)")
    logWarning("⚠️ [화면캡처] 강제 상태 초기화 완료", category: .streaming)
  }

  /// 화면 캡처 시작 전 오디오 캡처 사전 조건 준비
  private func prepareAudioCapturePrerequisites() async throws {
    try await ensureMicrophonePermission()
    configureAudioSessionForStreamingIfPossible()
  }

  /// 마이크 권한을 확인하고 필요 시 요청
  private func ensureMicrophonePermission() async throws {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return

    case .notDetermined:
      let granted = await AVCaptureDevice.requestAccess(for: .audio)
      if !granted {
        throw LiveStreamError.permissionDenied("마이크 권한이 없어 오디오 송출을 시작할 수 없습니다")
      }

    case .denied, .restricted:
      throw LiveStreamError.permissionDenied("마이크 권한이 필요합니다. 설정에서 마이크 권한을 허용해주세요")

    @unknown default:
      throw LiveStreamError.permissionDenied("마이크 권한 상태를 확인할 수 없습니다")
    }
  }

  /// 오디오 세션을 스트리밍에 맞게 선제 구성 (실패 시 비디오 송출은 계속)
  private func configureAudioSessionForStreamingIfPossible() {
    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(
        .playAndRecord,
        mode: .videoRecording,
        options: [.defaultToSpeaker, .allowBluetoothHFP]
      )
      try audioSession.setPreferredSampleRate(44_100)
      try audioSession.setPreferredIOBufferDuration(0.01)
      try audioSession.setActive(true)
      logInfo("🎵 화면 캡처 전 오디오 세션 준비 완료", category: .streaming)
    } catch {
      logWarning("오디오 세션 선제 구성 실패: \(error.localizedDescription)", category: .streaming)
    }
  }
}
