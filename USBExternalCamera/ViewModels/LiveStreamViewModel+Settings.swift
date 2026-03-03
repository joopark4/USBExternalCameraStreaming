import AVFoundation
import Combine
import Foundation
import LiveStreamingCore
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  private func recommendedYouTubeH264Bitrate(width: Int, height: Int, frameRate: Int) -> Int {
    let is60fps = frameRate >= 50
    if width >= 3840 && height >= 2160 {
      return is60fps ? 51_000 : 35_000
    } else if width >= 2560 && height >= 1440 {
      return is60fps ? 24_000 : 16_000
    } else if width >= 1920 && height >= 1080 {
      return is60fps ? 12_000 : 10_000
    } else {
      return is60fps ? 6_000 : 4_000
    }
  }

  // MARK: - Public Methods - Settings
  /// 스트리밍 설정 저장
  func saveSettings() {
    logDebug("💾 [SETTINGS] Saving stream settings...", category: .streaming)
    liveStreamService.saveSettings(settings)
    updateStreamingAvailability()
    logDebug("✅ [SETTINGS] Settings saved successfully", category: .streaming)
  }
  /// 설정 자동 저장 (설정이 변경될 때마다 호출)
  func autoSaveSettings() {
    liveStreamService.saveSettings(settings)
    logDebug("💾 [AUTO-SAVE] Settings auto-saved", category: .streaming)
  }

  /// 연결 테스트
  func testConnection() async {
    logDebug("🔍 [TEST] Testing connection...", category: .streaming)
    await MainActor.run {
      self.connectionTestResult = NSLocalizedString(
        "connection_test_starting", comment: "연결 테스트를 시작합니다...")
    }
    // 간단한 연결 테스트 시뮬레이션
    try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1초 대기
    let isValid = validateRTMPURL(settings.rtmpURL) && validateStreamKey(settings.streamKey)
    await MainActor.run {
      if isValid {
        self.connectionTestResult = NSLocalizedString(
          "connection_test_success", comment: "설정이 유효합니다. 스트리밍을 시작할 수 있습니다.")
      } else {
        self.connectionTestResult = NSLocalizedString(
          "connection_test_failed", comment: "설정에 문제가 있습니다. RTMP URL과 스트림 키를 확인해주세요.")
      }
    }
  }

  /// 빠른 연결 상태 확인
  func quickConnectionCheck() -> String {
    logDebug("⚡ [QUICK CHECK] 빠른 연결 상태 확인", category: .streaming)
    var result = "⚡ **빠른 연결 상태 확인**\n"
    result += String(repeating: "-", count: 30) + "\n\n"
    // RTMP URL 확인
    if settings.rtmpURL.isEmpty {
      result += "❌ RTMP URL이 설정되지 않았습니다\n"
    } else if validateRTMPURL(settings.rtmpURL) {
      result += "✅ RTMP URL이 올바르게 설정되었습니다\n"
    } else {
      result += "⚠️ RTMP URL 형식이 올바르지 않습니다\n"
    }
    // 스트림 키 확인
    if settings.streamKey.isEmpty {
      result += "❌ 스트림 키가 설정되지 않았습니다\n"
    } else if validateStreamKey(settings.streamKey) {
      result += "✅ 스트림 키가 올바르게 설정되었습니다\n"
    } else {
      result += "⚠️ 스트림 키가 너무 짧습니다\n"
    }
    // 권한 확인
    let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
    result += cameraAuth == .authorized ? "✅ 카메라 권한 허용됨\n" : "❌ 카메라 권한 필요\n"
    result += micAuth == .authorized ? "✅ 마이크 권한 허용됨\n" : "❌ 마이크 권한 필요\n"
    result += "\n📊 현재 상태: \(status.description)\n"
    return result
  }

  /// 스트리밍 품질 프리셋 적용
  /// - Parameter preset: 적용할 프리셋
  func applyPreset(_ preset: StreamingPreset) {
    let presetSettings = Self.createPresetSettings(preset)
    settings.videoWidth = presetSettings.videoWidth
    settings.videoHeight = presetSettings.videoHeight
    settings.videoBitrate = presetSettings.videoBitrate
    settings.audioBitrate = presetSettings.audioBitrate
    settings.frameRate = presetSettings.frameRate
    // keyframeInterval, videoEncoder, audioEncoder는 LiveStreamSettings에 없음

    // 스트리밍 가능 여부 업데이트
    updateStreamingAvailability()
  }

  /// 설정 초기화 (저장된 설정도 삭제)
  func resetToDefaults() {
    logDebug("🔄 [SETTINGS] Resetting to default settings...", category: .streaming)
    settings = Self.createDefaultSettings()
    // 저장된 설정도 삭제
    clearSavedSettings()
    // 즉시 기본 설정을 저장
    autoSaveSettings()
    // 스트리밍 가능 여부 업데이트
    updateStreamingAvailability()
    logDebug("✅ [SETTINGS] Reset to YouTube 1080p baseline successfully", category: .streaming)
  }

  /// 유튜브 라이브 스트리밍 표준 프리셋 적용
  func applyYouTubePreset(_ preset: YouTubeLivePreset) {
    logDebug("🎯 [PRESET] Applying YouTube preset: \(preset.displayName)", category: .streaming)
    settings.applyYouTubeLivePreset(preset)
    settings.videoBitrate = recommendedYouTubeH264Bitrate(
      width: settings.videoWidth,
      height: settings.videoHeight,
      frameRate: settings.frameRate
    )
    settings.audioBitrate = Constants.defaultAudioBitrate
    // 설정 즉시 저장
    autoSaveSettings()
    // 스트리밍 가능 여부 업데이트
    updateStreamingAvailability()
    logDebug("✅ [PRESET] YouTube preset applied successfully", category: .streaming)
    logDebug(
      "📊 [PRESET] Resolution: \(settings.videoWidth)×\(settings.videoHeight)", category: .streaming)
    logDebug("📊 [PRESET] Bitrate: \(settings.videoBitrate) kbps", category: .streaming)
  }

  /// 현재 설정에서 유튜브 프리셋 감지
  func detectCurrentYouTubePreset() -> YouTubeLivePreset {
    return settings.detectYouTubePreset() ?? .custom
  }

  /// 저장된 설정 삭제 (앱 삭제와 같은 효과)
  private func clearSavedSettings() {
    let defaults = UserDefaults.standard
    let keys = [
      "LiveStream.rtmpURL",
      "LiveStream.streamTitle",
      "LiveStream.videoBitrate",
      "LiveStream.videoWidth",
      "LiveStream.videoHeight",
      "LiveStream.frameRate",
      "LiveStream.audioBitrate",
      "LiveStream.autoReconnect",
      "LiveStream.isEnabled",
      "LiveStream.bufferSize",
      "LiveStream.connectionTimeout",
      "LiveStream.videoEncoder",
      "LiveStream.audioEncoder",
      "LiveStream.savedAt",
    ]
    for key in keys {
      defaults.removeObject(forKey: key)
    }
    // Keychain에서 스트림 키 삭제 (보안 향상)
    KeychainManager.shared.deleteStreamKey()
    defaults.synchronize()
    logDebug("🗑️ [CLEAR] Saved settings cleared", category: .streaming)
  }
}
