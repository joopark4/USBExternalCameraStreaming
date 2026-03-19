import AVFoundation
import Combine
import CoreImage
import Foundation
import HaishinKit
import Network
import UIKit
import VideoToolbox
import os.log

extension HaishinKitManager {
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

  public func getScreenCaptureDiagnosticsSnapshot() -> ScreenCaptureStats {
    return screenCaptureStats
  }

  /// 현재 스트리밍 설정 가져오기 (CameraPreview에서 사용)
  public func getCurrentSettings() -> LiveStreamSettings? {
    return currentSettings
  }

  /// 화면 캡처 통계 초기화
  public func resetScreenCaptureStats() {
    screenCaptureStats = ScreenCaptureStats()
    logger.info("🔄 화면 캡처 통계 초기화")
  }

}
