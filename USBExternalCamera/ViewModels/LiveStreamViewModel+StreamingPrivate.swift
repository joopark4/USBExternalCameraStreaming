import AVFoundation
import Combine
import Foundation
import LiveStreamingCore
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Private Methods - Streaming
  private func performStreamingStart(with captureSession: AVCaptureSession) async throws {
    // 화면 캡처 스트리밍 시작 (카메라 스트리밍은 제거됨)
    if let haishinKitManager = liveStreamService as? HaishinKitManager {
      try await haishinKitManager.startScreenCaptureStreaming(with: settings)
    } else {
      // 다른 서비스의 경우 화면 캡처 스트리밍을 구현해야 함
      throw LiveStreamError.streamingFailed(
        NSLocalizedString("screen_capture_only_supported", comment: "화면 캡처 스트리밍만 지원됩니다"))
    }
  }

  private func performStreamingStop() async throws {
    // 화면 캡처 중지 알림 전송 (화면 캡처 모드인 경우)
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .stopScreenCapture, object: nil)
    }
    await liveStreamService.stopStreaming()
  }

  private func handleStreamingStartSuccess() async {
    await updateStatus(
      .connected, message: NSLocalizedString("server_connected", comment: "서버에 연결됨"))
    try? await Task.sleep(nanoseconds: Constants.statusTransitionDelay)
    await updateStatus(.streaming, message: "YouTube Live 스트리밍 중")
    logDebug("✅ [STREAM] Streaming started successfully", category: .streaming)
  }

  private func handleStreamingStartFailure(_ error: Error) async {
    await updateStatus(
      .error(.streamingFailed(error.localizedDescription)),
      message: NSLocalizedString("streaming_start_failed", comment: "스트리밍 시작 실패: ")
        + error.localizedDescription)
    logDebug("❌ [STREAM] Failed to start: \(error.localizedDescription)", category: .streaming)
  }

  private func handleStreamingStopSuccess() async {
    await updateStatus(
      .idle, message: NSLocalizedString("streaming_ended", comment: "스트리밍이 종료되었습니다"))
    logDebug("✅ [STREAM] Streaming stopped successfully", category: .streaming)
  }

  private func handleStreamingStopFailure(_ error: Error) async {
    await updateStatus(
      .idle,
      message: NSLocalizedString("streaming_cleanup_complete", comment: "스트리밍 종료 완료 (일부 정리 오류 무시됨)")
    )
    logDebug(
      "⚠️ [STREAM] Stopped with minor issues: \(error.localizedDescription)", category: .streaming)
  }
}
