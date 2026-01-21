import AVFoundation
import Combine
import Foundation
import LiveStreamingCore
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Public Methods - Validation
  /// 스트림 키 유효성 검사
  /// - Parameter streamKey: 검사할 스트림 키
  /// - Returns: 유효성 검사 결과
  func validateStreamKey(_ key: String) -> Bool {
    return !key.isEmpty && key.count >= Constants.minimumStreamKeyLength
  }
  /// RTMP URL 유효성 검사
  /// - Parameter url: 검사할 URL
  func validateRTMPURL(_ url: String) -> Bool {
    return url.lowercased().hasPrefix("rtmp://") || url.lowercased().hasPrefix("rtmps://")
  }

  /// 예상 대역폭 계산
  /// - Returns: 예상 대역폭 (kbps)
  func calculateEstimatedBandwidth() -> Int {
    let totalBitrate = settings.videoBitrate + settings.audioBitrate
    let overhead = Int(Double(totalBitrate) * 0.1)
    return totalBitrate + overhead
  }
}
