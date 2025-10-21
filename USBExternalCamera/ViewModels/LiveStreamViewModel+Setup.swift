import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI
import LiveStreamingCore

extension LiveStreamViewModel {
  // MARK: - Private Methods - Setup

  private static func createDefaultSettings() -> USBExternalCamera.LiveStreamSettings {
    var settings = USBExternalCamera.LiveStreamSettings()
    settings.rtmpURL = Constants.youtubeRTMPURL
    settings.streamKey = ""
    settings.videoBitrate = Constants.defaultVideoBitrate
    settings.audioBitrate = Constants.defaultAudioBitrate
    settings.videoWidth = Constants.defaultVideoWidth
    settings.videoHeight = Constants.defaultVideoHeight
    settings.frameRate = Constants.defaultFrameRate
    return settings
  }

  private static func createPresetSettings(_ preset: StreamingPreset)
    -> USBExternalCamera.LiveStreamSettings
  {
    var settings = USBExternalCamera.LiveStreamSettings()

    switch preset {
    case .low:
      settings.videoWidth = 1280
      settings.videoHeight = 720
      settings.videoBitrate = 2500
      settings.frameRate = 30
    case .standard:
      settings.videoWidth = 1920
      settings.videoHeight = 1080
      settings.videoBitrate = 4500
      settings.frameRate = 30
    case .high:
      settings.videoWidth = 1920
      settings.videoHeight = 1080
      settings.videoBitrate = 6000
      settings.frameRate = 60
    case .ultra:
      settings.videoWidth = 3840
      settings.videoHeight = 2160
      settings.videoBitrate = 8000
      settings.frameRate = 60
    }

    settings.audioBitrate = preset == .ultra ? 256 : 128
    // keyframeInterval, videoEncoder, audioEncoder는 LiveStreamSettings에 없음

    return settings
  }

  private func setupBindings() {
    // 설정 변경 감지 및 자동 저장
    $settings
      .dropFirst()  // 초기값 제외
      .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)  // 500ms 디바운스
      .sink { [weak self] _ in
        self?.autoSaveSettings()
      }
      .store(in: &cancellables)

    // HaishinKitManager의 transmissionStats와 바인딩
    if let haishinKitManager = liveStreamService as? HaishinKitManager {
      haishinKitManager.$transmissionStats
        .receive(on: DispatchQueue.main)
        .sink { [weak self] stats in
          self?.transmissionStats = stats
        }
        .store(in: &cancellables)

      // 스트리밍 상태도 바인딩
      haishinKitManager.$currentStatus
        .receive(on: DispatchQueue.main)
        .sink { [weak self] status in
          self?.status = status
        }
        .store(in: &cancellables)

      // 네트워크 품질 바인딩 (transmissionStats에서 추출)
      haishinKitManager.$transmissionStats
        .map(\.connectionQuality)
        .map { connectionQuality in
          switch connectionQuality {
          case .excellent: return NetworkQuality.excellent
          case .good: return NetworkQuality.good
          case .fair: return NetworkQuality.fair
          case .poor: return NetworkQuality.poor
          case .unknown: return NetworkQuality.unknown
          }
        }
        .receive(on: DispatchQueue.main)
        .sink { [weak self] quality in
          self?.networkQuality = quality
        }
        .store(in: &cancellables)

      logDebug("✅ [BINDING] HaishinKitManager와 바인딩 완료", category: .streaming)
    }

    logDebug("✅ [AUTO-SAVE] 설정 자동 저장 바인딩 완료", category: .streaming)
  }

  private func loadInitialSettings() {
    guard let liveStreamService = liveStreamService else { return }

    Task {
      let loadedSettings = liveStreamService.loadSettings()

      await MainActor.run {
        // 로드된 설정이 있으면 적용 (빈 설정도 포함)
        self.settings = loadedSettings

        if !loadedSettings.rtmpURL.isEmpty || !loadedSettings.streamKey.isEmpty {
          logDebug(
            "🎥 [LOAD] Saved settings loaded - RTMP: \(!loadedSettings.rtmpURL.isEmpty), Key: \(!loadedSettings.streamKey.isEmpty)",
            category: .streaming)
        } else {
          logDebug("📝 [LOAD] Default settings loaded (no saved data)", category: .streaming)
        }

        self.updateStreamingAvailability()
        self.updateNetworkRecommendations()
      }
    }
  }

}
