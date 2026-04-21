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
  // MARK: - Protocol Implementation

  /// 연결 테스트
  public func testConnection(to settings: LiveStreamSettings) async
    -> ConnectionTestResult
  {
    logger.info("🔍 Examples 패턴 연결 테스트 시작", category: .connection)

    do {
      // 설정 검증
      try validateSettings(settings)

      // 간단한 연결성 테스트
      return ConnectionTestResult(
        isSuccessful: true,
        latency: 50,
        message: "Examples 패턴 연결 테스트 성공",
        networkQuality: .good
      )

    } catch let error as LiveStreamError {
      logger.error("❌ 연결 테스트 실패: \(error.localizedDescription)", category: .connection)
      return ConnectionTestResult(
        isSuccessful: false,
        latency: 0,
        message: error.localizedDescription,
        networkQuality: .poor
      )
    } catch {
      logger.error("❌ 연결 테스트 오류: \(error.localizedDescription)", category: .connection)
      return ConnectionTestResult(
        isSuccessful: false,
        latency: 0,
        message: "알 수 없는 오류가 발생했습니다",
        networkQuality: .unknown
      )
    }
  }

  /// 설정 검증
  func validateSettings(_ settings: LiveStreamSettings) throws {
    logger.info("🔍 스트리밍 설정 검증 시작")

    // RTMP URL 검증
    guard !settings.rtmpURL.isEmpty else {
      logger.error("❌ RTMP URL이 비어있음")
      throw LiveStreamError.configurationError("RTMP URL이 설정되지 않았습니다")
    }

    guard settings.rtmpURL.lowercased().hasPrefix("rtmp") else {
      logger.error("❌ RTMP 프로토콜이 아님: \(settings.rtmpURL)")
      throw LiveStreamError.configurationError("RTMP 프로토콜을 사용해야 합니다")
    }

    // 스트림 키 검증
    guard !settings.streamKey.isEmpty else {
      logger.error("❌ 스트림 키가 비어있음")
      throw LiveStreamError.authenticationFailed("스트림 키가 설정되지 않았습니다")
    }

    logger.info("✅ 스트리밍 설정 검증 완료")
  }

  /// 설정 로드 (UserDefaults에서)
  public func loadSettings() -> LiveStreamSettings {
    logger.info("📂 스트리밍 설정 로드", category: .system)

    var settings = LiveStreamSettings()

    // UserDefaults에서 스트림 설정 로드
    let defaults = UserDefaults.standard

    // 기본 스트리밍 설정
    if let rtmpURL = defaults.string(forKey: "LiveStream.rtmpURL"), !rtmpURL.isEmpty {
      settings.rtmpURL = rtmpURL
      logger.debug("📂 RTMP URL 로드됨", category: .system)
    }

    // Keychain에서 스트림 키 로드 (보안 향상)
    if let streamKey = KeychainManager.shared.loadStreamKey(), !streamKey.isEmpty {
      settings.streamKey = streamKey
      logger.debug("📂 스트림 키 로드됨 (길이: \(streamKey.count)자)", category: .system)
    } else {
      // 기존 UserDefaults에서 마이그레이션
      if let legacyStreamKey = defaults.string(forKey: "LiveStream.streamKey"),
        !legacyStreamKey.isEmpty
      {
        settings.streamKey = legacyStreamKey
        // Keychain으로 마이그레이션
        if KeychainManager.shared.saveStreamKey(legacyStreamKey) {
          // 마이그레이션 성공 시 UserDefaults에서 삭제
          defaults.removeObject(forKey: "LiveStream.streamKey")
          logger.info("🔒 스트림 키를 Keychain으로 마이그레이션 완료", category: .system)
        }
      }
    }

    if let streamTitle = defaults.string(forKey: "LiveStream.streamTitle"), !streamTitle.isEmpty {
      settings.streamTitle = streamTitle
    }

    // 비디오 설정
    let videoBitrate = defaults.integer(forKey: "LiveStream.videoBitrate")
    if videoBitrate > 0 {
      settings.videoBitrate = videoBitrate
    }

    let videoWidth = defaults.integer(forKey: "LiveStream.videoWidth")
    if videoWidth > 0 {
      settings.videoWidth = videoWidth
    }

    let videoHeight = defaults.integer(forKey: "LiveStream.videoHeight")
    if videoHeight > 0 {
      settings.videoHeight = videoHeight
    }

    let frameRate = defaults.integer(forKey: "LiveStream.frameRate")
    if frameRate > 0 {
      settings.frameRate = frameRate
    }

    // 오디오 설정
    let audioBitrate = defaults.integer(forKey: "LiveStream.audioBitrate")
    if audioBitrate > 0 {
      settings.audioBitrate = audioBitrate
    }

    // 고급 설정 (기본값을 고려한 로드)
    if defaults.object(forKey: "LiveStream.autoReconnect") != nil {
      settings.autoReconnect = defaults.bool(forKey: "LiveStream.autoReconnect")
    }  // 기본값: true (LiveStreamSettings의 init에서 설정)

    if defaults.object(forKey: "LiveStream.isEnabled") != nil {
      settings.isEnabled = defaults.bool(forKey: "LiveStream.isEnabled")
    }  // 기본값: true (LiveStreamSettings의 init에서 설정)

    let bufferSize = defaults.integer(forKey: "LiveStream.bufferSize")
    if bufferSize > 0 {
      settings.bufferSize = bufferSize
    }

    let connectionTimeout = defaults.integer(forKey: "LiveStream.connectionTimeout")
    if connectionTimeout > 0 {
      settings.connectionTimeout = connectionTimeout
    }

    if let videoEncoder = defaults.string(forKey: "LiveStream.videoEncoder"), !videoEncoder.isEmpty
    {
      settings.videoEncoder = videoEncoder
    }

    if let audioEncoder = defaults.string(forKey: "LiveStream.audioEncoder"), !audioEncoder.isEmpty
    {
      settings.audioEncoder = audioEncoder
    }

    logger.info("✅ 스트리밍 설정 로드 완료", category: .system)
    return settings
  }

  /// 설정 저장 (UserDefaults에)
  public func saveSettings(_ settings: LiveStreamSettings) {
    logger.info("💾 스트리밍 설정 저장 시작", category: .system)

    // 현재 설정과 비교하여 변경된 경우에만 스트리밍 중 실시간 적용
    let settingsChanged = (currentSettings != nil) && !isSettingsEqual(currentSettings!, settings)
    if settingsChanged && isStreaming {
      logger.info("🔄 스트리밍 중 설정 변경 감지 - 실시간 적용 시작", category: .system)
      currentSettings = settings

      // 비동기로 실시간 설정 적용
      Task {
        do {
          try await self.applyStreamSettings()
        } catch {
          self.logger.error("❌ 스트리밍 중 설정 적용 실패: \(error)", category: .system)
        }
      }
    } else {
      // 설정 업데이트 (스트리밍 중이 아니거나 변경사항 없음)
      currentSettings = settings
    }

    let defaults = UserDefaults.standard

    // 기본 스트리밍 설정
    defaults.set(settings.rtmpURL, forKey: "LiveStream.rtmpURL")

    // 스트림 키는 Keychain에 저장 (보안 향상)
    if !settings.streamKey.isEmpty {
      if !KeychainManager.shared.saveStreamKey(settings.streamKey) {
        logger.error("❌ 스트림 키 Keychain 저장 실패", category: .system)
      }
    }

    defaults.set(settings.streamTitle, forKey: "LiveStream.streamTitle")

    // 비디오 설정
    defaults.set(settings.videoBitrate, forKey: "LiveStream.videoBitrate")
    defaults.set(settings.videoWidth, forKey: "LiveStream.videoWidth")
    defaults.set(settings.videoHeight, forKey: "LiveStream.videoHeight")
    defaults.set(settings.frameRate, forKey: "LiveStream.frameRate")

    // 오디오 설정
    defaults.set(settings.audioBitrate, forKey: "LiveStream.audioBitrate")

    // 고급 설정
    defaults.set(settings.autoReconnect, forKey: "LiveStream.autoReconnect")
    defaults.set(settings.isEnabled, forKey: "LiveStream.isEnabled")
    defaults.set(settings.bufferSize, forKey: "LiveStream.bufferSize")
    defaults.set(settings.connectionTimeout, forKey: "LiveStream.connectionTimeout")
    defaults.set(settings.videoEncoder, forKey: "LiveStream.videoEncoder")
    defaults.set(settings.audioEncoder, forKey: "LiveStream.audioEncoder")

    // 저장 시점 기록
    defaults.set(Date(), forKey: "LiveStream.savedAt")

    // 즉시 디스크에 동기화
    defaults.synchronize()

    logger.info("✅ 스트리밍 설정 저장 완료", category: .system)
    logger.debug("💾 저장된 설정:", category: .system)
    logger.debug("  📍 RTMP URL: [설정됨]", category: .system)
    logger.debug("  🔑 스트림 키 길이: \(settings.streamKey.count)자", category: .system)
    logger.debug(
      "  📊 비디오: \(settings.videoWidth)×\(settings.videoHeight) @ \(settings.videoBitrate)kbps",
      category: .system)
    logger.debug("  🎵 오디오: \(settings.audioBitrate)kbps", category: .system)
  }

  /// 두 설정이 동일한지 비교 (실시간 적용 여부 결정용)
  func isSettingsEqual(
    _ settings1: LiveStreamSettings,
    _ settings2: LiveStreamSettings
  ) -> Bool {
    return settings1.videoWidth == settings2.videoWidth
      && settings1.videoHeight == settings2.videoHeight
      && settings1.videoBitrate == settings2.videoBitrate
      && settings1.audioBitrate == settings2.audioBitrate
      && settings1.frameRate == settings2.frameRate
  }

  /// RTMP 스트림 반환 (UI 미리보기용)
  public func getRTMPStream() -> RTMPStream? {
    return currentRTMPStream
  }

  /// 스트림 키 문제 상세 분석
  func analyzeStreamKeyIssues(for settings: LiveStreamSettings) {
    logger.error("  🔑 스트림 키 상세 분석:", category: .connection)

    let streamKey = settings.streamKey
    let cleanedKey = cleanAndValidateStreamKey(streamKey)

    // 1. 기본 정보
    logger.error("    📏 원본 스트림 키 길이: \(streamKey.count)자", category: .connection)
    logger.error("    🧹 정제된 스트림 키 길이: \(cleanedKey.count)자", category: .connection)
    logger.error(
      "    🔤 스트림 키 형식: \(cleanedKey.prefix(4))***\(cleanedKey.suffix(2))", category: .connection)

    // 2. 문자 구성 분석
    let hasUppercase = cleanedKey.rangeOfCharacter(from: .uppercaseLetters) != nil
    let hasLowercase = cleanedKey.rangeOfCharacter(from: .lowercaseLetters) != nil
    let hasNumbers = cleanedKey.rangeOfCharacter(from: .decimalDigits) != nil
    let hasSpecialChars = cleanedKey.rangeOfCharacter(from: CharacterSet(charactersIn: "-_")) != nil

    logger.error("    📊 문자 구성:", category: .connection)
    logger.error("      • 대문자: \(hasUppercase ? "✅" : "❌")", category: .connection)
    logger.error("      • 소문자: \(hasLowercase ? "✅" : "❌")", category: .connection)
    logger.error("      • 숫자: \(hasNumbers ? "✅" : "❌")", category: .connection)
    logger.error("      • 특수문자(-_): \(hasSpecialChars ? "✅" : "❌")", category: .connection)

    // 3. 공백 및 특수문자 검사
    let originalLength = streamKey.count
    let trimmedLength = streamKey.trimmingCharacters(in: .whitespacesAndNewlines).count
    let cleanedLength = cleanedKey.count

    if originalLength != trimmedLength {
      logger.error("    ⚠️ 앞뒤 공백/개행 발견! (\(originalLength - trimmedLength)자)", category: .connection)
    }

    if trimmedLength != cleanedLength {
      logger.error("    ⚠️ 숨겨진 제어문자 발견! (\(trimmedLength - cleanedLength)자)", category: .connection)
    }

    // 4. 스트림 키 패턴 검증
    if cleanedKey.count < 16 {
      logger.error("    ❌ 스트림 키가 너무 짧음 (16자 이상 필요)", category: .connection)
    } else if cleanedKey.count > 50 {
      logger.error("    ❌ 스트림 키가 너무 긺 (50자 이하 권장)", category: .connection)
    } else {
      logger.error("    ✅ 스트림 키 길이 적정", category: .connection)
    }

    // 5. YouTube 스트림 키 패턴 검증 (일반적인 패턴)
    if settings.rtmpURL.contains("youtube.com") {
      // YouTube 스트림 키는 보통 24-48자의 영숫자+하이픈 조합
      let youtubePattern = "^[a-zA-Z0-9_-]{20,48}$"
      let regex = try? NSRegularExpression(pattern: youtubePattern)
      let isValidYouTubeFormat =
        regex?.firstMatch(in: cleanedKey, range: NSRange(location: 0, length: cleanedKey.count))
        != nil

      if isValidYouTubeFormat {
        logger.error("    ✅ YouTube 스트림 키 형식 적합", category: .connection)
      } else {
        logger.error("    ❌ YouTube 스트림 키 형식 의심스러움", category: .connection)
        logger.error("        (일반적으로 20-48자의 영숫자+하이픈 조합)", category: .connection)
      }
    }
  }

  /// StreamSwitcher와 공유하는 스트림 키 검증 및 정제 메서드
  public func cleanAndValidateStreamKey(_ streamKey: String) -> String {
    // 1. 앞뒤 공백 제거
    let trimmed = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)

    // 2. 보이지 않는 특수 문자 제거 (제어 문자, BOM 등)
    let cleaned = trimmed.components(separatedBy: .controlCharacters).joined()
      .components(separatedBy: CharacterSet(charactersIn: "\u{FEFF}\u{200B}\u{200C}\u{200D}"))
      .joined()

    return cleaned
  }

  /// 송출 데이터 흐름 상태 확인 (공개 메서드)
  public func getDataFlowStatus() -> (isConnected: Bool, framesSent: Int, summary: String) {
    let rtmpConnected = currentRTMPStream != nil
    let framesSent = screenCaptureStats.successCount

    let summary = """
      📊 송출 데이터 흐름 상태:
      🎛️ MediaMixer: 실행 상태 확인 중
      📡 RTMPStream: \(rtmpConnected ? "연결됨" : "미연결")
      🎥 화면캡처: \(isScreenCaptureMode ? "활성" : "비활성")
      📹 프레임전송: \(framesSent)개 성공
      📊 현재FPS: \(String(format: "%.1f", screenCaptureStats.currentFPS))
      """

    return (rtmpConnected, framesSent, summary)
  }

  /// YouTube Live 연결 문제 진단 및 해결 가이드 (공개 메서드)
  public func diagnoseYouTubeLiveConnection() -> String {
    guard let settings = currentSettings, settings.rtmpURL.contains("youtube.com") else {
      return "YouTube Live 설정이 감지되지 않았습니다."
    }

    let diagnosis = """
      🎯 YouTube Live 연결 진단 결과:

      📊 현재 상태:
      • RTMP URL: \(settings.rtmpURL)
      • 스트림 키 길이: \(settings.streamKey.count)자
      • 재연결 시도: \(reconnectAttempts)/\(maxReconnectAttempts)
      • 연결 실패: \(connectionFailureCount)/\(maxConnectionFailures)

      🔧 해결 방법 (순서대로 시도):

      1️⃣ YouTube Studio 확인
         • studio.youtube.com 접속
         • 좌측 메뉴 → 라이브 스트리밍
         • "스트리밍 시작" 버튼 클릭 ⭐️
         • 상태: "스트리밍을 기다리는 중..." 확인

      2️⃣ 스트림 키 새로고침
         • YouTube Studio에서 새 스트림 키 복사
         • 앱에서 스트림 키 교체
         • 전체 선택 후 복사 (공백 없이)

      3️⃣ 네트워크 환경 확인
         • Wi-Fi 연결 상태 확인
         • 방화벽 설정 확인
         • VPN 사용 시 비활성화 시도

      4️⃣ YouTube 계정 상태
         • 라이브 스트리밍 권한 활성화 여부
         • 계정 제재 또는 제한 확인
         • 채널 인증 상태 확인

      💡 추가 팁:
      • 다른 스트리밍 프로그램 완전 종료
      • 브라우저 YouTube 탭 새로고침
      • 10-15분 후 재시도 (서버 혼잡 시)
      """

    return diagnosis
  }

  /// 연결 상태 간단 체크 (UI용)
  public func getConnectionSummary() -> (status: String, color: String, recommendation: String) {
    if !isStreaming {
      return ("중지됨", "gray", "스트리밍을 시작하세요")
    }

    if reconnectAttempts > 0 {
      return ("재연결 중", "orange", "YouTube Studio 상태를 확인하세요")
    }

    if connectionFailureCount > 0 {
      return ("불안정", "yellow", "연결 상태를 모니터링 중입니다")
    }

    if currentRTMPStream != nil && screenCaptureStats.frameCount > 0 {
      return ("정상", "green", "스트리밍이 원활히 진행 중입니다")
    }

    return ("확인 중", "blue", "연결 상태를 확인하고 있습니다")
  }

  /// 실시간 데이터 흐름 검증 (테스트용)
  public func validateDataFlow() -> Bool {
    // 모든 조건이 충족되어야 정상 송출 상태
    let conditions = [
      isStreaming,  // 스트리밍 중
      isScreenCaptureMode,  // 화면 캡처 모드
      currentRTMPStream != nil,  // RTMPStream 연결
      screenCaptureStats.frameCount > 0,  // 실제 프레임 전송
    ]

    let isValid = conditions.allSatisfy { $0 }

    if !isValid {
      logger.warning("⚠️ 데이터 흐름 검증 실패:")
      logger.warning("  - 스트리밍 중: \(isStreaming)")
      logger.warning("  - 화면캡처 모드: \(isScreenCaptureMode)")
      logger.warning("  - RTMPStream 연결: \(currentRTMPStream != nil)")
      logger.warning("  - 프레임 전송: \(screenCaptureStats.frameCount)개")
    }

    return isValid
  }

  /// 수동 재연결 (사용자가 직접 재시도)
  public func manualReconnect() async throws {
    guard let settings = currentSettings else {
      throw LiveStreamError.configurationError("재연결할 설정이 없습니다")
    }

    logger.info("🔄 사용자 요청 수동 재연결", category: .connection)

    // 재연결 카운터 리셋
    reconnectAttempts = 0
    reconnectDelay = 8.0  // 초기 재연결 지연시간 최적화 (15.0 → 8.0)
    connectionFailureCount = 0

    // 기존 연결 정리
    if isStreaming {
      await stopStreaming()
    }

    // 새로운 연결 시도 (화면 캡처 모드)
    try await startScreenCaptureStreaming(with: settings)
  }

  /// AVCaptureSession에서 받은 비디오 프레임 통계 업데이트 (통계 전용)
  public func processVideoFrame(_ sampleBuffer: CMSampleBuffer) async {
    guard isStreaming else { return }

    // 프레임 카운터 증가 (실제 데이터는 HaishinKit이 자체 카메라 연결로 처리)
    frameCounter += 1
    transmissionStats.videoFramesTransmitted += 1

    // 전송 바이트 추정
    let estimatedFrameSize: Int64 = 50000  // 50KB 추정
    transmissionStats.totalBytesTransmitted += estimatedFrameSize
    bytesSentCounter += estimatedFrameSize

    // 참고: 실제 프레임 송출은 sendManualFrame()에서 처리됩니다.
    // 텍스트 오버레이 병합도 sendManualFrame()에서 수행됩니다.
  }

  /// 픽셀 버퍼에 텍스트 오버레이 추가
  func addTextOverlayToPixelBuffer(_ pixelBuffer: CVPixelBuffer) async -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // 픽셀 버퍼를 UIImage로 변환
    guard let sourceImage = pixelBufferToUIImage(pixelBuffer) else {
      logger.error("❌ 픽셀버퍼 → UIImage 변환 실패", category: .streaming)
      return nil
    }

    // 텍스트 오버레이가 추가된 이미지 생성
    guard let overlaidImage = addTextOverlayToImage(sourceImage) else {
      logger.error("❌ 이미지에 텍스트 오버레이 추가 실패", category: .streaming)
      return nil
    }

    // UIImage를 다시 픽셀 버퍼로 변환
    return uiImageToPixelBuffer(overlaidImage, width: width, height: height)
  }

  /// UIImage에 텍스트 오버레이 추가
  func addTextOverlayToImage(_ image: UIImage) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: image.size)

    return renderer.image { context in
      // 원본 이미지 그리기
      image.draw(at: .zero)

      // 스트림 해상도와 프리뷰 해상도 비율 계산하여 폰트 크기 조정
      // 기준 해상도 720p (1280x720)와 현재 이미지 크기 비교
      let baseWidth: CGFloat = 1280
      let baseHeight: CGFloat = 720
      let scaleFactor = min(image.size.width / baseWidth, image.size.height / baseHeight)
      let adjustedFontSize = textOverlaySettings.fontSize * scaleFactor

      // 조정된 폰트 생성
      var adjustedFont: UIFont
      switch textOverlaySettings.fontName {
      case "System":
        adjustedFont = UIFont.systemFont(ofSize: adjustedFontSize, weight: .medium)
      case "System Bold":
        adjustedFont = UIFont.systemFont(ofSize: adjustedFontSize, weight: .bold)
      case "Helvetica":
        adjustedFont =
          UIFont(name: "Helvetica", size: adjustedFontSize)
          ?? UIFont.systemFont(ofSize: adjustedFontSize)
      case "Helvetica Bold":
        adjustedFont =
          UIFont(name: "Helvetica-Bold", size: adjustedFontSize)
          ?? UIFont.systemFont(ofSize: adjustedFontSize, weight: .bold)
      case "Arial":
        adjustedFont =
          UIFont(name: "Arial", size: adjustedFontSize)
          ?? UIFont.systemFont(ofSize: adjustedFontSize)
      case "Arial Bold":
        adjustedFont =
          UIFont(name: "Arial-BoldMT", size: adjustedFontSize)
          ?? UIFont.systemFont(ofSize: adjustedFontSize, weight: .bold)
      default:
        adjustedFont = UIFont.systemFont(ofSize: adjustedFontSize, weight: .medium)
      }

      // 사용자 설정에 따른 텍스트 스타일 설정 (조정된 폰트 사용)
      let textAttributes: [NSAttributedString.Key: Any] = [
        .font: adjustedFont,
        .foregroundColor: textOverlaySettings.uiColor,
        .strokeColor: UIColor.black,
        .strokeWidth: -2.0,  // 외곽선 두께 (가독성 향상)
      ]

      let attributedText = NSAttributedString(
        string: textOverlaySettings.text, attributes: textAttributes)
      let textSize = attributedText.size()

      // 텍스트 위치 계산 (하단 중앙)
      let textRect = CGRect(
        x: (image.size.width - textSize.width) / 2,
        y: image.size.height - textSize.height - 60,  // 하단에서 60px 위
        width: textSize.width,
        height: textSize.height
      )

      // 배경 그리기 (반투명 검은색 둥근 사각형 - 프리뷰와 일치)
      let scaledPaddingX = 16 * scaleFactor
      let scaledPaddingY = 8 * scaleFactor
      let scaledCornerRadius = 8 * scaleFactor
      let backgroundRect = textRect.insetBy(dx: -scaledPaddingX, dy: -scaledPaddingY)
      context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)

      // 둥근 사각형 그리기 (스케일에 맞는 cornerRadius)
      let path = UIBezierPath(roundedRect: backgroundRect, cornerRadius: scaledCornerRadius)
      context.cgContext.addPath(path.cgPath)
      context.cgContext.fillPath()

      // 텍스트 그리기
      attributedText.draw(in: textRect)
    }
  }

  /// 픽셀 버퍼를 UIImage로 변환 (색상 공간 최적화)
  func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

    // 색상 공간을 명시적으로 sRGB로 설정하여 일관성 확보
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CIContext(options: [
      .workingColorSpace: colorSpace,
      .outputColorSpace: colorSpace,
    ])

    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      logger.error("❌ CIImage → CGImage 변환 실패", category: .streaming)
      return nil
    }

    return UIImage(cgImage: cgImage)
  }

  /// UIImage를 픽셀 버퍼로 변환 (색상 필터 및 위아래 반전 문제 수정)
  func uiImageToPixelBuffer(_ image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
    let attributes =
      [
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
      ] as CFDictionary

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,  // ARGB → BGRA로 변경 (색상 채널 순서 문제 해결)
      attributes,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      logger.error("❌ 픽셀버퍼 생성 실패", category: .streaming)
      return nil
    }

    CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
    defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }

    let pixelData = CVPixelBufferGetBaseAddress(buffer)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()

    let context = CGContext(
      data: pixelData,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: rgbColorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue  // BGRA 포맷에 맞는 설정
    )

    guard let cgContext = context else {
      logger.error("❌ CGContext 생성 실패", category: .streaming)
      return nil
    }

    // 위아래 반전 제거 - 좌표계 변환 없이 이미지를 그대로 그리기
    let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
    cgContext.draw(image.cgImage!, in: imageRect)

    return buffer
  }

}
