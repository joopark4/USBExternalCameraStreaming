import AVFoundation
import Combine
import Foundation
import LiveStreamingCore
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Private Methods - Utilities
  func updateStatus(_ newStatus: LiveStreamStatus, message: String) async {
    await MainActor.run {
      self.status = newStatus
      self.statusMessage = message
      logDebug("🎯 [STATUS] Updated to \(newStatus): \(message)", category: .streaming)
    }
  }
  func syncServiceStatus(_ isStreaming: Bool) {
    if isStreaming && status != .streaming {
      status = .streaming
      logDebug("🎥 [SYNC] Service → ViewModel: streaming", category: .streaming)
    } else if !isStreaming && status == .streaming {
      status = .idle
      logDebug("🎥 [SYNC] Service → ViewModel: idle", category: .streaming)
    }
  }

  func updateStreamingAvailability() {
    let hasValidRTMP = !settings.rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasValidKey = !settings.streamKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let isRTMPFormat =
      settings.rtmpURL.hasPrefix("rtmp://") || settings.rtmpURL.hasPrefix("rtmps://")
    canStartStreaming = hasValidRTMP && hasValidKey && isRTMPFormat

    #if DEBUG
    // 개발용 강제 활성화 (릴리스 빌드에서는 제외됨)
    if !canStartStreaming {
      logWarning("Forcing canStartStreaming to true for development", category: .streaming)
      canStartStreaming = true
    }
    #endif
  }

  func updateNetworkRecommendations() {
    // getNetworkRecommendations 메서드가 아직 구현되지 않음
    // 기본값으로 설정
    networkRecommendations = StreamingRecommendations(
      recommendedVideoBitrate: 2500,
      recommendedAudioBitrate: 128,
      recommendedResolution: (width: 1920, height: 1080),
      networkQuality: .good,
      suggestions: ["네트워크 상태가 양호합니다"]
    )
  }

  private func showError(_ message: String) {
    currentErrorMessage = message
    showingErrorAlert = true
  }

  func logInitializationInfo() {
    logInfo("LiveStreamViewModel initialized", category: .streaming)
    logInfo("RTMP URL: \(settings.rtmpURL)", category: .streaming)
    logInfo("Stream Key: ***CONFIGURED***", category: .streaming)
    logInfo("📋 YouTube Live 설정 방법:", category: .streaming)
    logInfo("  1. studio.youtube.com 접속", category: .streaming)
    logInfo("  2. '라이브 스트리밍' > '스트림' 탭 선택", category: .streaming)
    logInfo("  3. '라이브 스트리밍 시작' 버튼 클릭", category: .streaming)
    logInfo("  4. 스트림 키 복사하여 앱에서 교체", category: .streaming)
  }

  private func logTransmissionStats(_ stats: Any) {
    // 타입을 확인하고 적절한 속성들을 출력
    logInfo("Transmission statistics received", category: .data)
    // Reflection을 사용하여 안전하게 통계 출력
    let mirror = Mirror(reflecting: stats)
    for child in mirror.children {
      if let label = child.label {
        logDebug("\(label): \(child.value)", category: .data)
      }
    }
  }
}
