import AVFoundation
import Foundation
import HaishinKit

extension HaishinKitManager {
  @discardableResult
  public func setMicrophoneMuted(_ muted: Bool) async -> Bool {
    isMicrophoneMuted = muted

    let primaryApplied = await applyMicrophoneMuteState(to: mixer, muted: muted)

    let legacyApplied: Bool
    if let mediaMixer {
      legacyApplied = await applyMicrophoneMuteState(to: mediaMixer, muted: muted)
    } else {
      legacyApplied = true
    }

    logger.info(
      "🎤 송출 마이크 \(muted ? "음소거" : "음소거 해제") 적용",
      category: .audio
    )
    return primaryApplied && legacyApplied
  }

  func applyCurrentMicrophoneMuteState() async {
    _ = await setMicrophoneMuted(isMicrophoneMuted)
  }

  private func applyMicrophoneMuteState(to mixer: MediaMixer, muted: Bool) async -> Bool {
    var audioMixerSettings = await mixer.audioMixerSettings
    audioMixerSettings.isMuted = false
    audioMixerSettings.mainTrack = 0

    var trackSettings = audioMixerSettings.tracks[0] ?? AudioMixerTrackSettings()
    trackSettings.isMuted = muted
    audioMixerSettings.tracks[0] = trackSettings

    await mixer.setAudioMixerSettings(audioMixerSettings)
    return true
  }
}
