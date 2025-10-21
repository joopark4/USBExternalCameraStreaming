import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Private Methods - Report Generation

  private func generateBasicInfoSection() -> String {
    var section = "📱 기본 정보:\n"
    section += "   • 앱 상태: \(status)\n"
    section += "   • 스트리밍 가능: \(canStartStreaming ? "예" : "아니오")\n"
    section += "   • RTMP URL: \(settings.rtmpURL)\n"
    section += "   • 스트림 키: \(settings.streamKey.isEmpty ? "❌ 미설정" : "✅ 설정됨")\n\n"
    return section
  }

  private func generatePermissionSection() -> String {
    let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)

    var section = "🔐 권한 상태:\n"
    section += "   • 카메라: \(cameraAuth == .authorized ? "✅ 허용" : "❌ 거부")\n"
    section += "   • 마이크: \(micAuth == .authorized ? "✅ 허용" : "❌ 거부")\n\n"
    return section
  }

  private func generateDeviceSection() -> String {
    var section = "📹 카메라 디바이스:\n"
    let cameras = checkAvailableCameras()
    for camera in cameras {
      section += "   • \(camera)\n"
    }
    section += "\n"
    return section
  }

  private func generateYouTubeSection() async -> String {
    var section = "🎬 YouTube Live 진단:\n"
    let youtubeIssues = await diagnoseYouTubeStreaming()
    for issue in youtubeIssues {
      section += "   \(issue)\n"
    }
    section += "\n"
    return section
  }

  private func generateRecommendationsSection() -> String {
    var section = "💡 권장 사항:\n"

    let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)

    if cameraAuth != .authorized {
      section += "   • 카메라 권한을 허용하세요\n"
    }
    if micAuth != .authorized {
      section += "   • 마이크 권한을 허용하세요\n"
    }
    if settings.streamKey.isEmpty || settings.streamKey == "YOUR_YOUTUBE_STREAM_KEY_HERE" {
      section += "   • YouTube Studio에서 실제 스트림 키를 설정하세요\n"
    }

    section += "   • YouTube Studio에서 '라이브 스트리밍 시작' 버튼을 눌러 대기 상태로 만드세요\n"
    section += "   • 스트림이 나타나기까지 10-30초 정도 기다려보세요\n\n"

    return section
  }

}
