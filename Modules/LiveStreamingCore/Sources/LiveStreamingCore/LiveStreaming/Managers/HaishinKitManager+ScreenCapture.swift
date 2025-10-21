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
  // MARK: - Screen Capture MediaMixer Setup

  /// 화면 캡처 전용 MediaMixer 설정
  func setupScreenCaptureMediaMixer() async throws {
    logger.info("🎛️ 화면 캡처용 MediaMixer 초기화 시작", category: .system)

    // MediaMixer 시작
    await mixer.startRunning()

    // 스크린 크기 설정 (매우 중요 - aspect ratio 문제 해결)
    if let settings = currentSettings {
      logger.info(
        "📹 화면 캡처용 목표 해상도: \(settings.videoWidth)x\(settings.videoHeight) @ \(settings.videoBitrate)kbps",
        category: .system)
      logger.info("📹 화면 캡처용 목표 프레임률: \(settings.frameRate)fps", category: .system)
      logger.info("🎵 화면 캡처용 목표 오디오: \(settings.audioBitrate)kbps", category: .system)

      // 🔧 중요: mixer.screen.size를 스트리밍 해상도와 정확히 일치시킴 (ScreenActor 사용)
      let screenSize = CGSize(width: settings.videoWidth, height: settings.videoHeight)

      Task { @ScreenActor in
        await mixer.screen.size = screenSize
        await mixer.screen.backgroundColor = UIColor.black.cgColor
      }

      logger.info("🖥️ MediaMixer 스크린 크기 설정: \(screenSize) (aspect ratio 문제 해결)", category: .system)
      logger.info("🎨 MediaMixer 배경색 설정: 검은색", category: .system)
    }

    logger.info("✅ 화면 캡처용 MediaMixer 초기화 완료 - RTMPStream 연결 대기", category: .system)
  }

  /// RTMPStream 설정 적용 (스트림이 준비된 후 호출)
  func applyStreamSettings() async throws {
    guard let stream = await streamSwitcher.stream, let settings = currentSettings else {
      logger.error("❌ RTMPStream 또는 설정이 준비되지 않음", category: .system)
      return
    }

    logger.info("🎛️ RTMPStream 설정 적용 시작", category: .system)
    logger.info("📋 현재 설정값:", category: .system)
    logger.info(
      "  📺 비디오: \(settings.videoWidth)×\(settings.videoHeight) @ \(settings.videoBitrate) kbps",
      category: .system)
    logger.info("  🎵 오디오: \(settings.audioBitrate) kbps", category: .system)
    logger.info("  🎬 프레임률: \(settings.frameRate) fps", category: .system)

    // 🔧 개선: VideoToolbox 진단 수행
    let diagnostics = await performVideoToolboxDiagnosis()

    // 사용자 설정 검증 및 권장사항 제공 (강제 변경 없음)
    let validationResult = validateAndProvideRecommendations(settings)
    var userSettings = validationResult.settings  // 사용자 설정 그대로 사용

    // 🔧 개선: VideoToolbox 프리셋 기반 설정 적용
    if diagnostics.hardwareAccelerationSupported {
      logger.info(
        "🎯 VideoToolbox 하드웨어 가속 지원 - 프리셋 설정: \(videoToolboxPreset.description)", category: .system)

      // iOS 17.4 이상에서만 새로운 VideoToolbox API 사용
      if #available(iOS 17.4, *) {
        do {
          // 새로운 강화된 VideoToolbox 설정 사용
          try await performanceOptimizer.setupHardwareCompressionWithPreset(
            settings: userSettings,
            preset: videoToolboxPreset
          )
          logger.info("✅ VideoToolbox 프리셋 설정 완료", category: .system)
        } catch {
          logger.error("❌ VideoToolbox 프리셋 설정 실패 - 기본 설정으로 폴백: \(error)", category: .system)

          // 폴백: 기존 방식으로 시도
          do {
            try performanceOptimizer.setupHardwareCompression(settings: userSettings)
            logger.info("✅ VideoToolbox 기본 설정 완료 (폴백)", category: .system)
          } catch {
            logger.warning("⚠️ VideoToolbox 하드웨어 설정 실패 - 소프트웨어 인코딩 사용: \(error)", category: .system)
          }
        }
      } else {
        // iOS 17.4 미만에서는 기본 설정만 사용
        logger.info("📱 iOS 17.4 미만 - VideoToolbox 고급 기능 미사용", category: .system)
      }
    } else {
      logger.warning("⚠️ VideoToolbox 하드웨어 가속 미지원 - 소프트웨어 인코딩 사용", category: .system)
    }

    // 🎯 720p 특화 최적화 적용 (사용자 설정 유지, 내부 최적화만)
    if settings.videoWidth == 1280 && settings.videoHeight == 720 {
      // 사용자 설정은 변경하지 않고, 내부 최적화만 적용
      _ = performanceOptimizer.optimize720pStreaming(settings: userSettings)
      logger.info("🎯 720p 특화 내부 최적화 적용됨 (사용자 설정 유지)", category: .system)
    }

    // 비디오 설정 적용 (사용자 설정 그대로)
    var videoSettings = await stream.videoSettings
    videoSettings.videoSize = CGSize(
      width: userSettings.videoWidth, height: userSettings.videoHeight)

    // VideoToolbox 하드웨어 인코딩 최적화 설정
    videoSettings.bitRate = userSettings.videoBitrate * 1000  // kbps를 bps로 변환

    // 💡 VideoToolbox 하드웨어 인코딩 최적화 (HaishinKit 2.0.8 API 호환)
    videoSettings.profileLevel = kVTProfileLevel_H264_High_AutoLevel as String  // 고품질 프로파일
    videoSettings.allowFrameReordering = true  // B-프레임 활용 (압축 효율 향상)
    videoSettings.maxKeyFrameIntervalDuration = 2  // 2초 간격 키프레임

    // 하드웨어 가속 활성화 (iOS는 기본적으로 하드웨어 사용)
    videoSettings.isHardwareEncoderEnabled = true

    await stream.setVideoSettings(videoSettings)
    logger.info(
      "✅ 사용자 설정 적용 완료: \(userSettings.videoWidth)×\(userSettings.videoHeight) @ \(userSettings.videoBitrate)kbps",
      category: .system)

    // 오디오 설정 적용 (사용자 설정 그대로)
    var audioSettings = await stream.audioSettings
    audioSettings.bitRate = userSettings.audioBitrate * 1000  // kbps를 bps로 변환

    await stream.setAudioSettings(audioSettings)
    logger.info("✅ 사용자 오디오 설정 적용: \(userSettings.audioBitrate)kbps", category: .system)

    // 🔍 중요: 설정 적용 검증 (실제 적용된 값 확인)
    let appliedVideoSettings = await stream.videoSettings
    let appliedAudioSettings = await stream.audioSettings

    let actualWidth = Int(appliedVideoSettings.videoSize.width)
    let actualHeight = Int(appliedVideoSettings.videoSize.height)
    let actualVideoBitrate = appliedVideoSettings.bitRate / 1000
    let actualAudioBitrate = appliedAudioSettings.bitRate / 1000

    logger.info("🔍 설정 적용 검증:", category: .system)
    logger.info(
      "  📺 해상도: \(actualWidth)×\(actualHeight) (요청: \(userSettings.videoWidth)×\(userSettings.videoHeight))",
      category: .system)
    logger.info(
      "  📊 비디오 비트레이트: \(actualVideoBitrate)kbps (요청: \(userSettings.videoBitrate)kbps)",
      category: .system)
    logger.info(
      "  🎵 오디오 비트레이트: \(actualAudioBitrate)kbps (요청: \(userSettings.audioBitrate)kbps)",
      category: .system)

    // 설정값과 실제값 불일치 검사
    if actualWidth != userSettings.videoWidth || actualHeight != userSettings.videoHeight {
      logger.warning(
        "⚠️ 해상도 불일치 감지: 요청 \(userSettings.videoWidth)×\(userSettings.videoHeight) vs 실제 \(actualWidth)×\(actualHeight)",
        category: .system)
    }

    if abs(Int(actualVideoBitrate) - userSettings.videoBitrate) > 100 {
      logger.warning(
        "⚠️ 비디오 비트레이트 불일치: 요청 \(userSettings.videoBitrate)kbps vs 실제 \(actualVideoBitrate)kbps",
        category: .system)
    }

    if abs(Int(actualAudioBitrate) - userSettings.audioBitrate) > 10 {
      logger.warning(
        "⚠️ 오디오 비트레이트 불일치: 요청 \(userSettings.audioBitrate)kbps vs 실제 \(actualAudioBitrate)kbps",
        category: .system)
    }

    // 🎯 720p 전용 버퍼링 최적화 적용
    await optimize720pBuffering()

    // 🔧 개선: VideoToolbox 성능 모니터링 시작
    await startVideoToolboxPerformanceMonitoring()

    logger.info("🎉 강화된 RTMPStream 설정 적용 완료", category: .system)
  }

  /// 스트리밍 설정 검증 및 권장사항 제공 (강제 변경 제거)
  func validateAndProvideRecommendations(_ settings: USBExternalCamera.LiveStreamSettings)
    -> (settings: USBExternalCamera.LiveStreamSettings, recommendations: [String])
  {
    var recommendations: [String] = []

    // 성능 권장사항만 제공, 강제 변경하지 않음
    if settings.videoWidth >= 1920 && settings.videoHeight >= 1080 {
      recommendations.append("⚠️ 1080p는 높은 성능을 요구합니다. 프레임 드롭이 발생할 수 있습니다.")
      recommendations.append("💡 권장: 720p (1280x720)로 설정하면 더 안정적입니다.")
    }

    if settings.frameRate > 30 {
      recommendations.append("⚠️ 60fps는 높은 CPU 사용량을 요구합니다.")
      recommendations.append("💡 권장: 30fps로 설정하면 더 안정적입니다.")
    }

    if settings.videoBitrate > 6000 {
      recommendations.append("⚠️ 높은 비트레이트는 네트워크 부하를 증가시킬 수 있습니다.")
      recommendations.append("💡 권장: 4500kbps 이하로 설정하는 것을 권장합니다.")
    }

    // 권장사항 로그 출력
    if !recommendations.isEmpty {
      logger.info("📋 성능 권장사항 (사용자 설정은 유지됨):", category: .system)
      for recommendation in recommendations {
        logger.info("  \(recommendation)", category: .system)
      }
    }

    // 🔧 중요: 사용자 설정을 그대로 반환 (강제 변경 없음)
    return (settings: settings, recommendations: recommendations)
  }

  /// 기존 validateAndAdjustSettings 함수를 새로운 함수로 대체
  func validateAndAdjustSettings(_ settings: USBExternalCamera.LiveStreamSettings)
    -> USBExternalCamera.LiveStreamSettings
  {
    let validationResult = validateAndProvideRecommendations(settings)

    // 권장사항이 있어도 사용자 설정을 그대로 사용
    logger.info(
      "✅ 사용자 설정 보존: \(settings.videoWidth)×\(settings.videoHeight) @ \(settings.frameRate)fps, \(settings.videoBitrate)kbps",
      category: .system)

    return validationResult.settings
  }

  /// 화면 캡처 스트리밍용 오디오 설정
  func setupAudioForScreenCapture() async throws {
    logger.info("🎵 화면 캡처용 오디오 설정 시작", category: .system)

    do {
      // 디바이스 마이크를 MediaMixer에 연결 (개선된 설정)
      guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
        logger.warning("⚠️ 오디오 디바이스를 찾을 수 없음", category: .system)
        return
      }

      // 스트리밍 설정에 맞춰 오디오 디바이스 최적화
      if let settings = currentSettings {
        try optimizeAudioDevice(audioDevice, for: settings)
      }

      // 오디오 디바이스 연결
      try await mixer.attachAudio(audioDevice, track: 0)

      // 오디오 설정은 기본값 사용 (HaishinKit에서 지원하는 설정만)

      logger.info("✅ 화면 캡처용 오디오 설정 완료 - 마이크 연결됨", category: .system)
      logger.info("  🎤 디바이스: \(audioDevice.localizedName)", category: .system)

    } catch {
      logger.warning("⚠️ 화면 캡처용 오디오 설정 실패 (비디오만 송출): \(error)", category: .system)
      // 오디오 실패는 치명적이지 않으므로 비디오만 송출 계속
    }
  }

  /// 스트리밍 설정에 맞춰 오디오 디바이스 최적화
  func optimizeAudioDevice(
    _ audioDevice: AVCaptureDevice, for settings: USBExternalCamera.LiveStreamSettings
  ) throws {
    logger.info("🎛️ 스트리밍 설정에 맞춰 오디오 디바이스 최적화", category: .system)

    try audioDevice.lockForConfiguration()
    defer { audioDevice.unlockForConfiguration() }

    // 오디오 비트레이트에 따른 품질 최적화
    let audioQualityLevel = determineAudioQualityLevel(bitrate: settings.audioBitrate)

    switch audioQualityLevel {
    case .low:
      // 64kbps 이하: 기본 설정으로 충분
      logger.info("🎵 저품질 오디오 모드 (≤64kbps): 기본 설정 사용", category: .system)

    case .standard:
      // 128kbps: 표준 품질 최적화
      logger.info("🎵 표준 오디오 모드 (128kbps): 균형 설정 적용", category: .system)

    case .high:
      // 192kbps 이상: 고품질 최적화
      logger.info("🎵 고품질 오디오 모드 (≥192kbps): 최고 품질 설정 적용", category: .system)
    }

    // 오디오 세션 최적화 (전역 설정)
    try optimizeAudioSession(for: audioQualityLevel)

    logger.info("✅ 오디오 디바이스 최적화 완료", category: .system)
  }

  /// 오디오 품질 레벨 결정
  func determineAudioQualityLevel(bitrate: Int) -> AudioQualityLevel {
    switch bitrate {
    case 0..<96:
      return .low
    case 96..<160:
      return .standard
    default:
      return .high
    }
  }

  /// 오디오 세션 최적화
  func optimizeAudioSession(for qualityLevel: AudioQualityLevel) throws {
    let audioSession = AVAudioSession.sharedInstance()

    do {
      // 카테고리 설정 (녹음과 재생 모두 가능)
      try audioSession.setCategory(
        .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])

      // 품질 레벨에 따른 세부 설정
      switch qualityLevel {
      case .low:
        // 저품질: 성능 우선
        try audioSession.setPreferredSampleRate(44100)  // 표준 샘플레이트
        try audioSession.setPreferredIOBufferDuration(0.02)  // 20ms 버퍼 (성능)

      case .standard:
        // 표준 품질: 균형
        try audioSession.setPreferredSampleRate(44100)  // 표준 샘플레이트
        try audioSession.setPreferredIOBufferDuration(0.01)  // 10ms 버퍼 (균형)

      case .high:
        // 고품질: 품질 우선
        try audioSession.setPreferredSampleRate(48000)  // 고품질 샘플레이트
        try audioSession.setPreferredIOBufferDuration(0.005)  // 5ms 버퍼 (품질)
      }

      try audioSession.setActive(true)

      logger.info("🎛️ 오디오 세션 최적화 완료 (\(qualityLevel))", category: .system)

    } catch {
      logger.warning("⚠️ 오디오 세션 최적화 실패: \(error)", category: .system)
      // 실패해도 기본 설정으로 계속 진행
    }
  }

}
