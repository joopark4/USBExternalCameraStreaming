import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI
import LiveStreamingCore

extension LiveStreamViewModel {
  // MARK: - Screen Capture Streaming Private Methods

  /// 화면 캡처 스트리밍 시작 실행 (내부 메서드)
  ///
  /// **실행 단계:**
  /// 1. 스트리밍 서비스 유효성 검사
  /// 2. HaishinKit 초기화 및 서버 연결
  /// 3. 데이터 모니터링 시작
  ///
  /// **예외 처리:**
  /// - 서비스 미초기화: LiveStreamError.configurationError
  /// - 네트워크 연결 실패: LiveStreamError.networkError
  /// - 기타 오류: 원본 에러 전파
  ///
  /// - Throws: LiveStreamError 또는 기타 스트리밍 관련 에러
  private func performScreenCaptureStreamingStart() async throws {
    guard let haishinKitManager = liveStreamService as? HaishinKitManager else {
      throw LiveStreamError.configurationError("HaishinKitManager가 초기화되지 않았습니다")
    }

    logDebug("🔄 [화면캡처] 화면 캡처 스트리밍 시작 중...", category: .streaming)

    // 화면 캡처 전용 스트리밍 시작 (일반 스트리밍과 다른 메서드 사용)
    try await haishinKitManager.startScreenCaptureStreaming(with: settings)

    // 데이터 모니터링 시작 (네트워크 상태, FPS 등)
    startDataMonitoring()

    logInfo("✅ [화면캡처] 화면 캡처 스트리밍 서비스 시작 완료", category: .streaming)
  }

  /// 화면 캡처 스트리밍 시작 성공 후처리 (내부 메서드)
  ///
  /// **수행 작업:**
  /// 1. 스트리밍 상태를 'streaming'으로 변경
  /// 2. CameraPreviewView에 화면 캡처 시작 알림 전송
  /// 3. 성공 메시지 표시
  ///
  /// **알림 시스템:**
  /// NotificationCenter를 통해 CameraPreviewView와 통신하여
  /// 30fps 화면 캡처 타이머를 시작시킵니다.
  private func handleScreenCaptureStreamingStartSuccess() async {
    logInfo("✅ [화면캡처] 스트리밍 시작 성공", category: .streaming)

    // 상태를 'streaming'으로 업데이트
    await updateStatus(.streaming, message: "화면 캡처 송출 중")

    // CameraPreviewView에 화면 캡처 시작 신호 전송
    // 이 알림을 받으면 CameraPreviewUIView에서 30fps 타이머 시작
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: NSNotification.Name("startScreenCapture"), object: nil)
    }

    logInfo("📡 [화면캡처] 화면 캡처 시작 신호 전송 완료", category: .streaming)
  }

  /// 화면 캡처 스트리밍 시작 실패 처리 (내부 메서드)
  ///
  /// **복구 작업:**
  /// 1. 상태를 'error'로 변경
  /// 2. 사용자에게 구체적인 오류 메시지 표시
  /// 3. 관련 리소스 정리
  ///
  /// **에러 메시지 매핑:**
  /// - 네트워크 오류: "네트워크 연결을 확인해주세요"
  /// - 설정 오류: "스트리밍 설정을 확인해주세요"
  /// - 기타 오류: 원본 에러 메시지 표시
  ///
  /// - Parameter error: 발생한 오류 정보
  private func handleScreenCaptureStreamingStartFailure(_ error: Error) async {
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
  ///
  /// **중지 단계:**
  /// 1. CameraPreviewView에 화면 캡처 중지 신호 전송
  /// 2. 스트리밍 서비스 연결 해제
  /// 3. 데이터 모니터링 중지
  ///
  /// **중지 순서 중요성:**
  /// 먼저 화면 캡처를 중지해야 HaishinKit으로 전송되는 프레임이 중단되고,
  /// 그 다음 서비스 연결을 해제하여 안전하게 종료됩니다.
  ///
  /// - Throws: LiveStreamError 또는 기타 스트리밍 관련 에러
  private func performScreenCaptureStreamingStop() async throws {
    guard let service = liveStreamService else {
      throw LiveStreamError.configurationError("스트리밍 서비스가 초기화되지 않았습니다")
    }

    logDebug("🔄 [화면캡처] 스트리밍 서비스 중지 중...", category: .streaming)

    // Step 1: CameraPreviewView에 화면 캡처 중지 신호 전송
    // 30fps 타이머 중지 및 프레임 캡처 종료
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: NSNotification.Name("stopScreenCapture"), object: nil)
    }

    // Step 2: HaishinKit 스트리밍 서비스 중지
    await service.stopStreaming()

    logInfo("✅ [화면캡처] 스트리밍 서비스 중지 완료", category: .streaming)
  }

  /// 화면 캡처 스트리밍 중지 성공 후처리 (내부 메서드)
  ///
  /// **정리 작업:**
  /// 1. 상태를 'idle'로 초기화
  /// 2. 성공 메시지 표시
  /// 3. 관련 상태 변수 초기화
  ///
  /// **상태 초기화:**
  /// 다음 화면 캡처 스트리밍을 위해 모든 상태를 초기값으로 복원합니다.
  private func handleScreenCaptureStreamingStopSuccess() async {
    logInfo("✅ [화면캡처] 스트리밍 중지 성공", category: .streaming)

    // 상태를 'idle'로 초기화
    await updateStatus(.idle, message: "화면 캡처 스트리밍 준비 완료")

    logInfo("🏁 [화면캡처] 모든 리소스 정리 완료", category: .streaming)
  }

  /// 화면 캡처 스트리밍 중지 실패 처리 (내부 메서드)
  ///
  /// **안전장치 역할:**
  /// 스트리밍 중지 중 오류가 발생해도 강제로 상태를 초기화하여
  /// 사용자가 다시 스트리밍을 시작할 수 있도록 합니다.
  ///
  /// **강제 정리:**
  /// - 화면 캡처 중지 신호 재전송
  /// - 상태 강제 초기화
  /// - 모든 모니터링 중지
  ///
  /// - Parameter error: 발생한 오류 정보
  private func handleScreenCaptureStreamingStopFailure(_ error: Error) async {
    logError("❌ [화면캡처] 스트리밍 중지 실패: \(error.localizedDescription)", category: .streaming)

    // 강제로 화면 캡처 중지 신호 재전송 (안전장치)
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: NSNotification.Name("stopScreenCapture"), object: nil)
    }

    // 강제로 상태 초기화 (사용자가 다시 시도할 수 있도록)
    await updateStatus(.idle, message: "스트리밍 중지됨 (오류 복구)")

    logWarning("⚠️ [화면캡처] 강제 상태 초기화 완료", category: .streaming)
  }
}
