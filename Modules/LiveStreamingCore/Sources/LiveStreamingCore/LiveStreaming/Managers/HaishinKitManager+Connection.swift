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
  // MARK: - 빠른 연결을 위한 병렬 처리 함수들

  /// RTMP 연결과 병렬로 실행할 로컬 설정들
  func setupLocalComponentsInParallel(_ settings: USBExternalCamera.LiveStreamSettings)
    async throws
  {
    logger.info("⚡ 로컬 컴포넌트 병렬 초기화 시작", category: .system)

    // 병렬 작업들 정의
    async let mediaMixerSetup: () = initializeMediaMixerQuickly()
    async let audioSetup: () = setupAudioQuickly()
    async let settingsPreparation: () = prepareStreamSettingsQuickly(settings)

    // 모든 병렬 작업 완료 대기
    try await mediaMixerSetup
    try await audioSetup
    try await settingsPreparation

    logger.info("✅ 로컬 컴포넌트 병렬 초기화 완료", category: .system)
  }

  /// 빠른 MediaMixer 초기화 (최소 설정만)
  func initializeMediaMixerQuickly() async throws {
    logger.info("🎛️ MediaMixer 빠른 초기화", category: .system)

    // Examples 패턴: MediaMixer 초기화 (기본 설정만)
    initializeMediaMixerBasedStreaming()

    // MediaMixer 시작 (설정은 나중에)
    await mixer.startRunning()

    logger.info("✅ MediaMixer 빠른 초기화 완료", category: .system)
  }

  /// 빠른 오디오 설정 (최소 설정만)
  func setupAudioQuickly() async throws {
    logger.info("🎵 오디오 빠른 설정", category: .system)

    // 기본 오디오 디바이스만 연결 (최적화는 나중에)
    if let audioDevice = AVCaptureDevice.default(for: .audio) {
      try await mixer.attachAudio(audioDevice, track: 0)
      logger.info("✅ 기본 오디오 연결 완료", category: .system)
    } else {
      logger.warning("⚠️ 오디오 디바이스 없음 - 비디오만 송출", category: .system)
    }
  }

  /// 스트림 설정 사전 준비
  func prepareStreamSettingsQuickly(_ settings: USBExternalCamera.LiveStreamSettings)
    async throws
  {
    logger.info("📋 스트림 설정 사전 준비", category: .system)

    // 설정 유효성 검증만 (적용은 나중에)
    let _ = validateAndAdjustSettings(settings)

    logger.info("✅ 스트림 설정 검증 완료", category: .system)
  }

  /// 최종 연결 완료 처리 (최소화)
  func finalizeScreenCaptureConnection() async throws {
    logger.info("🔧 최종 연결 처리 시작", category: .system)

    // RTMPStream 연결 확인 및 설정 적용
    if let stream = await streamSwitcher.stream {
      await mixer.addOutput(stream)
      currentRTMPStream = stream

      // 스트림 설정 적용 (병렬 처리로 이미 검증된 설정 사용)
      try await applyStreamSettings()

      // VideoCodec 워크어라운드 (백그라운드에서)
      Task.detached { [weak self] in
        guard let self = self else { return }
        await self.setupVideoCodecWorkaroundInBackground(stream: stream)
      }

      logger.info("✅ 최종 연결 처리 완료", category: .system)
    } else {
      throw LiveStreamError.configurationError("RTMPStream 초기화 실패")
    }
  }

  /// VideoCodec 워크어라운드 백그라운드 설정
  func setupVideoCodecWorkaroundInBackground(stream: RTMPStream) async {
    do {
      if let settings = currentSettings {
        try await videoCodecWorkaround.startWorkaroundStreaming(with: settings, rtmpStream: stream)
        logger.info("✅ VideoCodec 워크어라운드 백그라운드 완료", category: .system)
      }
    } catch {
      logger.warning("⚠️ VideoCodec 워크어라운드 백그라운드 실패: \(error)", category: .system)
    }
  }

}
