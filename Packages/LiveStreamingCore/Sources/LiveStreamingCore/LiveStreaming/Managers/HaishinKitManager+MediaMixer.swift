import AVFoundation
import Combine
import CoreImage
import Foundation
import HaishinKit
import RTMPHaishinKit
import Network
import UIKit
import VideoToolbox
import os.log

extension HaishinKitManager {
  // MARK: - MediaMixer 기반 스트리밍 (HaishinKit Examples 패턴)

  /// HaishinKit 공식 Examples 패턴을 적용한 MediaMixer 기반 스트리밍
  func initializeMediaMixerBasedStreaming() {
    os_log("🏭 Examples 패턴: MediaMixer 기반 스트리밍 초기화 시작", log: .default, type: .info)

    // Examples와 동일한 MediaMixer 설정
    let mediaMixer = MediaMixer(
      captureSessionMode: .manual,  // 수동 캡처 모드 (화면 캡처용)
      multiTrackAudioMixingEnabled: true
    )

    Task {
      // 비디오 믹서 설정 (Examples 패턴)
      var videoMixerSettings = await mediaMixer.videoMixerSettings
      videoMixerSettings.mode = .offscreen  // 화면 캡처 모드
      await mediaMixer.setVideoMixerSettings(videoMixerSettings)

      // MediaMixer를 RTMPStream에 연결
      if let stream = await streamSwitcher.stream {
        await mediaMixer.addOutput(stream)
      }

      os_log("✅ Examples 패턴: MediaMixer ↔ RTMPStream 연결 완료", log: .default, type: .info)

      // 내부 저장
      self.mediaMixer = mediaMixer
    }
  }

  /// Examples 패턴: HKStreamSwitcher 스타일 연결
  func connectUsingExamplesPattern() {
    os_log("🔗 Examples 패턴: HKStreamSwitcher 스타일 연결 시작", log: .default, type: .info)

    Task {
      do {
        // 1. RTMP 연결 (Examples와 동일)
        guard let settings = currentSettings else {
          throw LiveStreamError.configurationError("스트리밍 설정이 없음")
        }

        _ = try await streamSwitcher.connection?.connect(settings.rtmpURL)
        os_log("✅ Examples 패턴: RTMP 연결 성공", log: .default, type: .info)

        // 2. 스트림 퍼블리시 (Examples와 동일)
        if let stream = await streamSwitcher.stream {
          _ = try await stream.publish(settings.streamKey)
          os_log("✅ Examples 패턴: 스트림 퍼블리시 성공", log: .default, type: .info)

          // 3. 상태 업데이트
          await MainActor.run {
            self.currentStatus = .streaming
            self.connectionStatus = "Examples 패턴 스트리밍 중..."
            self.isStreaming = true
          }

          // 4. MediaMixer 시작
          if let mixer = mediaMixer {
            await mixer.startRunning()
            os_log("✅ Examples 패턴: MediaMixer 시작됨", log: .default, type: .info)
          }

        } else {
          throw LiveStreamError.configurationError("스트림이 없음")
        }

      } catch {
        os_log("❌ Examples 패턴: 연결 실패 - %@", log: .default, type: .error, error.localizedDescription)
        await MainActor.run {
          self.currentStatus = .error(
            error as? LiveStreamError ?? LiveStreamError.streamingFailed(error.localizedDescription)
          )
        }
      }
    }
  }

  /// Examples 패턴: MediaMixer 기반 프레임 전송 (사용하지 않음 - 기존 방식 유지)
  func sendFrameUsingMediaMixer(_ pixelBuffer: CVPixelBuffer) {
    // 주석: MediaMixer의 append는 오디오 전용이므로 사용하지 않음
    // 대신 기존의 sendManualFrame에서 MediaMixer 연결된 스트림 사용
    os_log("ℹ️ MediaMixer 패턴은 sendManualFrame에서 처리됨", log: .default, type: .info)
  }

  /// MediaMixer 정리
  func cleanupMediaMixer() {
    guard let mixer = mediaMixer else { return }

    Task {
      await mixer.stopRunning()
      os_log("🛑 MediaMixer 정리 완료", log: .default, type: .info)
      self.mediaMixer = nil
    }
  }

}
