import AVFoundation
import Combine
import Foundation
import LiveStreamingCore
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Private Methods - Setup
  static func createDefaultSettings() -> LiveStreamSettings {
    var settings = LiveStreamSettings()
    settings.rtmpURL = Constants.youtubeRTMPURL
    settings.streamKey = ""
    settings.videoBitrate = Constants.defaultVideoBitrate
    settings.audioBitrate = Constants.defaultAudioBitrate
    settings.videoWidth = Constants.defaultVideoWidth
    settings.videoHeight = Constants.defaultVideoHeight
    settings.frameRate = Constants.defaultFrameRate
    return settings
  }
  static func createPresetSettings(_ preset: StreamingPreset)
    -> LiveStreamSettings
  {
    var settings = LiveStreamSettings()
    settings.rtmpURL = Constants.youtubeRTMPURL
    settings.streamKey = ""
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
      settings.frameRate = 30
    case .ultra:
      settings.videoWidth = 3840
      settings.videoHeight = 2160
      settings.videoBitrate = 35_000
      settings.frameRate = 30
    }
    settings.audioBitrate = preset == .ultra ? 256 : 128
    // keyframeInterval, videoEncoder, audioEncoder는 LiveStreamSettings에 없음
    return settings
  }
  func setupBindings() {
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
        .scan((previous: LiveStreamStatus.idle, current: LiveStreamStatus.idle)) { state, newStatus in
          (previous: state.current, current: newStatus)
        }
        .sink { [weak self] transition in
          guard let self else { return }
          let previousStatus = transition.previous
          let status = transition.current
          self.status = status

          if status == .streaming {
            if self.screenCaptureStreamingStartedAt == nil {
              self.screenCaptureStreamingStartedAt = .now
            }
            if previousStatus != .streaming {
              self.suspendIdleMicrophonePeakMonitoringForStreaming()
            }
          } else if status == .idle {
            self.screenCaptureStreamingStartedAt = nil
            self.resumeIdleMicrophonePeakMonitoringAfterStreaming()
          }
        }
        .store(in: &cancellables)

      // 네트워크 품질 바인딩 (transmissionStats에서 추출)
      haishinKitManager.$transmissionStats
        .map(\.connectionQuality)
        .map { connectionQuality -> NetworkQuality in
          switch connectionQuality {
          case .excellent: return .excellent
          case .good: return .good
          case .fair: return .fair
          case .poor: return .poor
          case .unknown: return .unknown
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
  func loadInitialSettings() {
    Task {
      let loadedSettings = liveStreamService.loadSettings()
      let defaults = UserDefaults.standard
      let hasSavedSettings =
        defaults.object(forKey: "LiveStream.savedAt") != nil
        || defaults.object(forKey: "LiveStream.videoBitrate") != nil
        || defaults.object(forKey: "LiveStream.videoWidth") != nil
        || defaults.object(forKey: "LiveStream.videoHeight") != nil
        || defaults.object(forKey: "LiveStream.streamOrientation") != nil
        || defaults.object(forKey: "LiveStream.frameRate") != nil

      await MainActor.run {
        if hasSavedSettings {
          self.settings = loadedSettings
          logDebug(
            "🎥 [LOAD] Saved settings loaded - RTMP: \(!loadedSettings.rtmpURL.isEmpty), Key: \(!loadedSettings.streamKey.isEmpty)",
            category: .streaming)
        } else {
          // 저장 이력이 없으면 앱 기본값(YouTube 1080p30/H.264 권장값) 적용
          self.settings = Self.createDefaultSettings()
          self.autoSaveSettings()
          logDebug("📝 [LOAD] Initial defaults applied (YouTube 1080p baseline)", category: .streaming)
        }
        self.updateStreamingAvailability()
        self.updateNetworkRecommendations()
      }
    }
  }
}
