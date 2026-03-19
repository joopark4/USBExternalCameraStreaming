import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI


// MARK: - Supporting Types

/// 스트리밍 품질 프리셋
enum StreamingPreset: String, CaseIterable {
  case low
  case standard
  case high
  case ultra

  var displayName: String {
    switch self {
    case .low: return NSLocalizedString("streaming_preset_low", comment: "저화질")
    case .standard: return NSLocalizedString("streaming_preset_standard", comment: "표준")
    case .high: return NSLocalizedString("streaming_preset_high", comment: "고화질")
    case .ultra: return NSLocalizedString("streaming_preset_ultra", comment: "최고화질")
    }
  }

  var description: String {
    switch self {
    case .low: return "720p • 2.5Mbps"
    case .standard: return "1080p • 4.5Mbps"
    case .high: return "1080p • 6.0Mbps"
    case .ultra: return "4K • 35.0Mbps"
    }
  }

  var icon: String {
    switch self {
    case .low: return "1.circle"
    case .standard: return "2.circle"
    case .high: return "3.circle"
    case .ultra: return "4.circle"
    }
  }
}

/// YouTube Live H.264 권장 비트레이트 계산 유틸리티
enum YouTubeBitrateAdvisor {
  static func recommendedH264Bitrate(width: Int, height: Int, frameRate: Int) -> Int {
    let is60fps = frameRate >= 50
    if width >= 3840 && height >= 2160 {
      return is60fps ? 51_000 : 35_000
    } else if width >= 2560 && height >= 1440 {
      return is60fps ? 24_000 : 16_000
    } else if width >= 1920 && height >= 1080 {
      return is60fps ? 9_000 : 4_500
    } else {
      return is60fps ? 6_000 : 2_500
    }
  }
}

/// 네트워크 상태
enum NetworkStatus: String, CaseIterable {
  case poor
  case fair
  case good
  case excellent

  var displayName: String {
    switch self {
    case .poor: return NSLocalizedString("network_status_poor", comment: "불량")
    case .fair: return NSLocalizedString("network_status_fair", comment: "보통")
    case .good: return NSLocalizedString("network_status_good", comment: "양호")
    case .excellent: return NSLocalizedString("network_status_excellent", comment: "우수")
    }
  }

  var description: String {
    switch self {
    case .poor: return NSLocalizedString("network_status_poor_desc", comment: "느린 연결 (< 2Mbps)")
    case .fair: return NSLocalizedString("network_status_fair_desc", comment: "보통 연결 (2-5Mbps)")
    case .good: return NSLocalizedString("network_status_good_desc", comment: "빠른 연결 (5-10Mbps)")
    case .excellent:
      return NSLocalizedString("network_status_excellent_desc", comment: "매우 빠른 연결 (> 10Mbps)")
    }
  }

  var color: Color {
    switch self {
    case .poor: return .red
    case .fair: return .orange
    case .good: return .green
    case .excellent: return .blue
    }
  }
}

/// 사용 가능한 마이크 입력 옵션
struct MicrophoneInputOption: Identifiable, Hashable {
  static let automaticID = "automatic"

  let id: String
  let name: String
  let portType: AVAudioSession.Port?
  let uid: String?

  var isAutomatic: Bool {
    id == Self.automaticID
  }

  var isExternal: Bool {
    guard let portType else { return false }
    switch portType {
    case .builtInMic:
      return false
    default:
      return true
    }
  }
}
