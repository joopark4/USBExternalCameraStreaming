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
  // MARK: - Text Overlay Properties

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
  func optimize720pBuffering() async {
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
    videoSettings.maxKeyFrameIntervalDuration = 2

    // 720p 전용 인코딩 설정
    videoSettings.profileLevel = kVTProfileLevel_H264_Main_AutoLevel as String

    await stream.setVideoSettings(videoSettings)

    logger.info("✅ 720p 버퍼링 최적화 완료", category: .system)
  }

}
