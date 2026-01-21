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
  // MARK: - 개발자 전용 디버깅 메서드들

  #if DEBUG
    // 테스트 및 디버그 관련 메서드들이 제거되었습니다.
    // 프로덕션 환경에서 불필요한 테스트 데이터 및 더미 기능을 정리했습니다.
  #endif

  /// 스트리밍 설정에 맞춰 하드웨어 최적화 연동
  /// - 카메라 및 오디오 하드웨어를 스트리밍 설정에 맞춰 최적화
  /// - 품질 불일치 방지 및 성능 향상
  func optimizeHardwareForStreaming(_ settings: USBExternalCamera.LiveStreamSettings) async
  {
    logger.info("🎛️ 스트리밍 설정에 맞춰 전체 하드웨어 최적화 시작", category: .system)

    // 1. 카메라 하드웨어 최적화 (CameraSessionManager 연동)
    await optimizeCameraHardware(for: settings)

    // 2. 하드웨어 최적화 결과 로깅
    await logHardwareOptimizationResults(settings)

    logger.info("✅ 전체 하드웨어 최적화 완료", category: .system)
  }

  /// 카메라 하드웨어 최적화 (CameraSessionManager 연동)
  func optimizeCameraHardware(for settings: USBExternalCamera.LiveStreamSettings) async {
    // CameraSessionManager가 있는 경우에만 최적화 실행
    // (화면 캡처 모드에서는 실제 카메라를 사용하지 않지만, 향후 카메라 스트리밍 모드를 위해 준비)
    logger.info("📹 카메라 하드웨어 최적화 준비", category: .system)
    logger.info("  📺 스트리밍 해상도: \(settings.videoWidth)×\(settings.videoHeight)", category: .system)
    logger.info("  🎬 스트리밍 프레임레이트: \(settings.frameRate)fps", category: .system)
    logger.info("  📊 스트리밍 비트레이트: \(settings.videoBitrate)kbps", category: .system)

    // 화면 캡처 모드에서는 실제 카메라 최적화 생략
    // 향후 카메라 스트리밍 모드 추가 시 다음 코드 활성화:
    // if let cameraSessionManager = self.cameraSessionManager {
    //     cameraSessionManager.optimizeForStreamingSettings(settings)
    // }

    logger.info("✅ 카메라 하드웨어 최적화 완료 (화면 캡처 모드)", category: .system)
  }

  /// 하드웨어 최적화 결과 로깅
  func logHardwareOptimizationResults(_ settings: USBExternalCamera.LiveStreamSettings)
    async
  {
    logger.info("📊 하드웨어 최적화 결과 요약:", category: .system)

    // 오디오 최적화 결과
    let audioQualityLevel = determineAudioQualityLevel(bitrate: settings.audioBitrate)
    logger.info(
      "  🎵 오디오 품질 레벨: \(audioQualityLevel.rawValue) (\(settings.audioBitrate)kbps)",
      category: .system)

    // 비디오 최적화 결과
    let videoComplexity = determineVideoComplexity(settings: settings)
    logger.info("  📺 비디오 복잡도: \(videoComplexity)", category: .system)

    // 전체 최적화 상태
    let optimizationStatus = getOverallOptimizationStatus(settings: settings)
    logger.info("  🎯 전체 최적화 상태: \(optimizationStatus)", category: .system)
  }

  /// 비디오 복잡도 결정
  func determineVideoComplexity(settings: USBExternalCamera.LiveStreamSettings) -> String {
    let pixels = settings.videoWidth * settings.videoHeight
    let bitrate = settings.videoBitrate
    let fps = settings.frameRate

    switch (pixels, fps, bitrate) {
    case (0..<(1280 * 720), 0..<30, 0..<2000):
      return "저복잡도 (SD)"
    case (0..<(1920 * 1080), 0..<30, 0..<4000):
      return "중복잡도 (HD)"
    case (0..<(1920 * 1080), 30..<60, 4000..<6000):
      return "고복잡도 (HD 고프레임)"
    case ((1920 * 1080)..., _, 4000...):
      return "초고복잡도 (FHD+)"
    default:
      return "사용자정의"
    }
  }

  /// 전체 최적화 상태 평가
  func getOverallOptimizationStatus(settings: USBExternalCamera.LiveStreamSettings)
    -> String
  {
    let audioLevel = determineAudioQualityLevel(bitrate: settings.audioBitrate)
    let videoPixels = settings.videoWidth * settings.videoHeight

    // 오디오/비디오 품질 균형 평가
    let isBalanced =
      (audioLevel == .standard && videoPixels >= 1280 * 720 && videoPixels < 1920 * 1080)
      || (audioLevel == .high && videoPixels >= 1920 * 1080)

    if isBalanced {
      return "최적 균형 ⭐"
    } else if audioLevel == .low && videoPixels >= 1920 * 1080 {
      return "비디오 편중 ⚠️"
    } else if audioLevel == .high && videoPixels < 1280 * 720 {
      return "오디오 편중 ⚠️"
    } else {
      return "표준 설정 ✅"
    }
  }

  /// 수동으로 프레임을 스트리밍에 전송 (화면 캡처 모드) - 개선된 버전
  @MainActor
  public func sendManualFrame(_ pixelBuffer: CVPixelBuffer) async {
    guard isStreaming else {
      logger.warning("⚠️ 스트리밍이 활성화되지 않아 프레임 스킵")
      return
    }

    // 🔄 통계 업데이트 (프레임 시작)
    screenCaptureStats.updateFrameCount()

    let currentTime = CACurrentMediaTime()

    // 1. 프레임 유효성 사전 검증
    guard validatePixelBufferForEncoding(pixelBuffer) else {
      logger.error("❌ 프레임 유효성 검증 실패 - 프레임 스킵")
      screenCaptureStats.incrementFailureCount()
      return
    }

    let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
    let originalHeight = CVPixelBufferGetHeight(pixelBuffer)
    logger.debug("📥 수신 프레임: \(originalWidth)x\(originalHeight)")

    // 1.5. 텍스트 오버레이 처리 (픽셀 버퍼에 직접 병합)
    var frameToProcess = pixelBuffer
    if showTextOverlay && !textOverlaySettings.text.isEmpty {
      if let overlaidPixelBuffer = await addTextOverlayToPixelBuffer(pixelBuffer) {
        frameToProcess = overlaidPixelBuffer
        logger.debug("📝 텍스트 오버레이 병합 완료: '\(textOverlaySettings.text)'")
      } else {
        logger.warning("⚠️ 텍스트 오버레이 병합 실패 - 원본 프레임 사용")
      }
    }

    // 2. 프레임 전처리 (포맷 변환 + 해상도 정렬)
    guard let processedPixelBuffer = preprocessPixelBufferSafely(frameToProcess) else {
      logger.error("❌ 프레임 전처리 실패 - 프레임 스킵")
      screenCaptureStats.incrementFailureCount()
      return
    }

    // 3. 전처리 결과 확인
    _ = CVPixelBufferGetWidth(processedPixelBuffer)
    _ = CVPixelBufferGetHeight(processedPixelBuffer)
    // logger.debug("📊 최종 전송 프레임: \(finalWidth)x\(finalHeight)") // 반복적인 로그 비활성화

    // 4. CMSampleBuffer 생성 (향상된 에러 핸들링)
    guard let sampleBuffer = createSampleBufferSafely(from: processedPixelBuffer) else {
      logger.error("❌ CMSampleBuffer 생성 실패 - VideoCodec 호환성 문제")
      frameTransmissionFailure += 1
      screenCaptureStats.incrementFailureCount()

      // VideoCodec 문제 디버깅 정보
      logVideoCodecDiagnostics(pixelBuffer: processedPixelBuffer)
      return
    }

    // 5. 프레임 전송 시도 (VideoCodec 워크어라운드 적용)
    do {
      frameTransmissionCount += 1

      // logger.debug("📡 HaishinKit 프레임 전송 시도 #\(frameTransmissionCount): \(finalWidth)x\(finalHeight)") // 반복적인 로그 비활성화

      // VideoCodec 워크어라운드를 우선 사용하여 -12902 에러 해결
      await videoCodecWorkaround.sendFrameWithWorkaround(sampleBuffer)
      // logger.debug("✅ VideoCodec 워크어라운드 적용 프레임 전송") // 반복적인 로그 비활성화

      frameTransmissionSuccess += 1
      screenCaptureStats.incrementSuccessCount()
      // logger.debug("✅ 프레임 전송 성공 #\(frameTransmissionSuccess)") // 반복적인 로그 비활성화

      // 전송 성공 통계 업데이트 (매 50프레임마다 - 더 자주 확인)
      if frameTransmissionCount % 50 == 0 {
        let successRate = Double(frameTransmissionSuccess) / Double(frameTransmissionCount) * 100
        // 성공률이 낮을 때만 로그 출력 (95% 미만)
        if successRate < 95.0 {
          logger.warning(
            "📊 프레임 전송 성공률 낮음: \(String(format: "%.1f", successRate))% (\(frameTransmissionSuccess)/\(frameTransmissionCount))"
          )
        }

        // 성공률이 낮으면 경고
        if successRate < 80.0 {
          logger.warning("⚠️ 프레임 전송 성공률 저조: \(String(format: "%.1f", successRate))% - 스트리밍 품질 저하 가능")
        }
      }

    } catch {
      logger.error("❌ 프레임 전송 중 오류: \(error)")
      frameTransmissionFailure += 1
      screenCaptureStats.incrementFailureCount()

      // 오류 세부 정보 로깅
      logger.error("🔍 에러 세부 정보: \(String(describing: error))")

      // VideoCodec 에러 특별 처리 - 더 넓은 범위로 감지
      let errorString = String(describing: error)
      if errorString.contains("failedToPrepare") || errorString.contains("-12902") {
        logger.error("🚨 VideoCodec failedToPrepare 에러 감지 - 프레임 포맷 문제")

        // VideoCodec 에러 복구 시도 (더 적극적으로)
        await handleVideoCodecError(pixelBuffer: processedPixelBuffer)

        // 복구 후 재시도 (1회)
        if frameTransmissionFailure % 5 == 0 {  // 5번 실패마다 재시도
          logger.info("🔄 VideoCodec 복구 후 재시도 중...")
          do {
            if let recoveryBuffer = createSimpleDummyFrame() {
              try await videoCodecWorkaround.sendFrameWithWorkaround(recoveryBuffer)
              logger.info("✅ VideoCodec 복구 재시도 성공")
            }
          } catch {
            logger.warning("⚠️ VideoCodec 복구 재시도 실패: \(error)")
          }
        }
      }

      // NSError로 변환하여 에러 코드 확인
      if let nsError = error as NSError? {
        logger.error("🔍 NSError 도메인: \(nsError.domain), 코드: \(nsError.code)")

        if nsError.code == -12902 {
          logger.error("🚨 VideoCodec -12902 에러 확인됨")
        }
      }
    }

    // 6. 주기적 통계 리셋 (메모리 오버플로우 방지)
    if frameTransmissionCount >= 1500 {  // 약 60초마다 리셋 (3000 → 1500)
      let successRate = Double(frameTransmissionSuccess) / Double(frameTransmissionCount) * 100
      logger.info("📊 전송 세션 완료: 최종 성공률 \(String(format: "%.1f", successRate))%")

      frameTransmissionCount = 0
      frameTransmissionSuccess = 0
      frameTransmissionFailure = 0
      frameStatsStartTime = currentTime
    }
  }

  /// 프레임 유효성 검증 (인코딩 전 사전 체크)
  func validatePixelBufferForEncoding(_ pixelBuffer: CVPixelBuffer) -> Bool {
    // 기본 크기 검증
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    guard width > 0 && height > 0 else {
      logger.error("❌ 잘못된 프레임 크기: \(width)x\(height)")
      return false
    }

    // 최소/최대 해상도 검증
    guard width >= 160 && height >= 120 && width <= 3840 && height <= 2160 else {
      logger.error("❌ 지원되지 않는 해상도: \(width)x\(height)")
      return false
    }

    // 픽셀 포맷 사전 검증
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let supportedFormats: [OSType] = [
      kCVPixelFormatType_32BGRA,
      kCVPixelFormatType_32ARGB,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
    ]

    guard supportedFormats.contains(pixelFormat) else {
      logger.warning("⚠️ 비표준 픽셀 포맷: \(pixelFormat) - 변환 필요")
      return true  // 변환 필요하지만 유효한 상태로 처리
    }

    return true
  }

  /// 안전한 프레임 전처리 (에러 핸들링 강화)
  func preprocessPixelBufferSafely(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    do {
      logger.info("🔧 [preprocessPixelBufferSafely] 프레임 전처리 시작")

      // 포맷 변환 우선 실행
      guard let formatCompatibleBuffer = convertPixelBufferFormatSafely(pixelBuffer) else {
        logger.error("❌ [preprocessPixelBufferSafely] 포맷 변환 실패")
        return nil
      }

      logger.info("✅ [preprocessPixelBufferSafely] 포맷 변환 완료")

      // 해상도 확인 및 스케일링
      guard let settings = currentSettings else {
        logger.warning("⚠️ 스트리밍 설정 없음 - 원본 해상도 사용")
        return formatCompatibleBuffer
      }

      let currentWidth = CVPixelBufferGetWidth(formatCompatibleBuffer)
      let currentHeight = CVPixelBufferGetHeight(formatCompatibleBuffer)
      let targetWidth = settings.videoWidth
      let targetHeight = settings.videoHeight

      // 해상도가 이미 일치하면 바로 반환
      if currentWidth == targetWidth && currentHeight == targetHeight {
        return formatCompatibleBuffer
      }

      // 스케일링 실행
      logger.info(
        "🔄 해상도 스케일링 시작: \(currentWidth)x\(currentHeight) → \(targetWidth)x\(targetHeight)")

      guard
        let scaledBuffer = scalePixelBufferSafely(
          formatCompatibleBuffer, to: CGSize(width: targetWidth, height: targetHeight))
      else {
        logger.error("❌ 해상도 스케일링 실패 - 포맷 변환된 버퍼 사용")
        return formatCompatibleBuffer
      }

      logger.info(
        "🎉 해상도 스케일링 완료 및 검증 성공: \(CVPixelBufferGetWidth(scaledBuffer))x\(CVPixelBufferGetHeight(scaledBuffer))"
      )
      return scaledBuffer

    } catch {
      logger.error("❌ 프레임 전처리 예외: \(error)")
      return nil
    }
  }

  /// VideoCodec -12902 해결을 위한 안전한 포맷 변환 (BGRA → YUV420)
  func convertPixelBufferFormatSafely(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let currentFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let targetFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange  // YUV420 포맷

    logger.info("🔄 [포맷변환] 시작: \(currentFormat) → YUV420 (\(targetFormat))")

    // 이미 YUV420 포맷이면 원본 반환
    if currentFormat == targetFormat {
      logger.info("✅ [포맷변환] 이미 YUV420 포맷 - 변환 불필요")
      return pixelBuffer
    }

    logger.info("🔄 [포맷변환] BGRA→YUV420 변환 실행 중...")

    // 16의 배수 정렬과 YUV420 변환을 포함한 통합 변환
    let result = convertToSupportedFormat(pixelBuffer)

    if let convertedBuffer = result {
      let resultFormat = CVPixelBufferGetPixelFormatType(convertedBuffer)
      logger.info("✅ [포맷변환] 성공: \(currentFormat) → \(resultFormat)")
    } else {
      logger.error("❌ [포맷변환] 실패: \(currentFormat) → YUV420")
    }

    return result
  }

  /// 안전한 해상도 스케일링
  func scalePixelBufferSafely(_ pixelBuffer: CVPixelBuffer, to targetSize: CGSize)
    -> CVPixelBuffer?
  {
    return scalePixelBuffer(pixelBuffer, to: targetSize)
  }

  /// 안전한 CMSampleBuffer 생성 (VideoCodec 호환성 보장)
  func createSampleBufferSafely(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    // 추가 검증 로직
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    // VideoCodec 최적화 포맷 검증 (YUV420)
    let supportedFormats: [OSType] = [
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      kCVPixelFormatType_32BGRA,  // 폴백용
    ]

    guard supportedFormats.contains(pixelFormat) else {
      logger.error("❌ VideoCodec 비호환 포맷: \(pixelFormat)")
      return nil
    }

    if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
      logger.debug("✅ YUV420 포맷 확인 - VideoCodec 최적화")
    }

    // 해상도 16의 배수 확인 (H.264 인코더 요구사항)
    if width % 16 != 0 || height % 16 != 0 {
      logger.warning("⚠️ 해상도가 16의 배수가 아님: \(width)x\(height) - 인코딩 문제 가능")
      // 16의 배수가 아니어도 계속 진행 (스케일링에서 이미 처리됨)
    }

    // CMSampleBuffer 생성 전 pixelBuffer 락 상태 확인
    let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    guard lockResult == kCVReturnSuccess else {
      logger.error("❌ PixelBuffer 락 실패: \(lockResult)")
      return nil
    }

    // CMSampleBuffer 생성
    let sampleBuffer = createSampleBuffer(from: pixelBuffer)

    // PixelBuffer 언락
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

    if sampleBuffer == nil {
      logger.error("❌ CMSampleBuffer 생성 실패 - VideoCodec 호환성 문제")
      logVideoCodecDiagnostics(pixelBuffer: pixelBuffer)
    }

    return sampleBuffer
  }

  /// VideoCodec 에러 처리 및 복구
  func handleVideoCodecError(pixelBuffer: CVPixelBuffer) async {
    logger.warning("🔧 VideoCodec 에러 복구 시도 중...")

    // 1. 잠시 전송 중단 (더 길게)
    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms 대기

    // 2. 스트림 상태 재확인 및 플러시
    if let stream = currentRTMPStream {
      logger.info("🔄 RTMPStream 플러시 시도")

      // VideoCodec 재초기화를 위한 더미 프레임 전송
      if let dummyBuffer = createSimpleDummyFrame() {
        do {
          try await stream.append(dummyBuffer)
          logger.info("✅ VideoCodec 재활성화 더미 프레임 전송 성공")
        } catch {
          logger.warning("⚠️ 더미 프레임 전송 실패: \(error)")
        }
      }
    }

    logger.warning("✅ VideoCodec 에러 복구 시도 완료")
  }

  /// 간단한 더미 프레임 생성 (VideoCodec 재활성화용)
  func createSimpleDummyFrame() -> CMSampleBuffer? {
    guard let settings = currentSettings else { return nil }

    // 단색 픽셀버퍼 생성 (검은색, YUV420 포맷)
    let width = settings.videoWidth
    let height = settings.videoHeight

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      nil,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      return nil
    }

    // Y/UV 플레인 초기화 (검은색)
    CVPixelBufferLockBaseAddress(buffer, [])

    // Y 플레인 (밝기 - 검은색)
    if let yPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
      let ySize = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) * height
      memset(yPlane, 16, ySize)
    }

    // UV 플레인 (색상 - 중성)
    if let uvPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
      let uvSize = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * (height / 2)
      memset(uvPlane, 128, uvSize)
    }

    CVPixelBufferUnlockBaseAddress(buffer, [])

    // CMSampleBuffer 생성
    return createSampleBuffer(from: buffer)
  }

  /// VideoCodec 진단 정보 로깅
  func logVideoCodecDiagnostics(pixelBuffer: CVPixelBuffer) {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    logger.info("🔍 VideoCodec 진단:")
    logger.info("  - 해상도: \(width)x\(height)")
    logger.info("  - 픽셀 포맷: \(pixelFormat)")
    logger.info("  - 16의 배수 여부: \(width % 16 == 0 && height % 16 == 0)")
    logger.info(
      "  - YUV420 포맷 여부: \(pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)")
    logger.info("  - BGRA 포맷 여부: \(pixelFormat == kCVPixelFormatType_32BGRA)")

    // 디바이스 환경 진단 추가
    logDeviceEnvironmentDiagnostics()
  }

  /// 디바이스 환경 진단 (시뮬레이터 vs 실제 디바이스)
  func logDeviceEnvironmentDiagnostics() {
    #if targetEnvironment(simulator)
      logger.warning("⚠️ 시뮬레이터 환경에서 실행 중 - 실제 카메라 데이터 없음")
      logger.warning("  → 실제 디바이스에서 테스트 필요")
    #else
      logger.info("✅ 실제 디바이스에서 실행 중")
    #endif

    // 디바이스 정보
    let device = UIDevice.current
    logger.info("📱 디바이스 정보:")
    logger.info("  - 모델: \(device.model)")
    logger.info("  - 시스템: \(device.systemName) \(device.systemVersion)")
    logger.info("  - 이름: \(device.name)")

    // 카메라 디바이스 진단
    logCameraDeviceDiagnostics()
  }

  /// 카메라 디바이스 진단
  func logCameraDeviceDiagnostics() {
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInWideAngleCamera,
        .builtInUltraWideCamera,
        .external,
      ],
      mediaType: .video,
      position: .unspecified
    )

    let devices = discoverySession.devices
    logger.info("📹 카메라 디바이스 진단:")
    logger.info("  - 전체 디바이스 수: \(devices.count)")

    var builtInCount = 0
    var externalCount = 0

    for device in devices {
      if device.deviceType == .external {
        externalCount += 1
        logger.info("  - 외부 카메라: \(device.localizedName)")
      } else {
        builtInCount += 1
        logger.info("  - 내장 카메라: \(device.localizedName) (\(device.position.rawValue))")
      }
    }

    logger.info("  - 내장 카메라: \(builtInCount)개")
    logger.info("  - 외부 카메라: \(externalCount)개")

    if externalCount == 0 {
      logger.warning("⚠️ 외부 USB 카메라가 연결되지 않음")
      logger.warning("  → USB 카메라 연결 상태 확인 필요")
    }
  }

  /// 타임아웃 기능 구현
  func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T)
    async throws -> T
  {
    return try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }

      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw TimeoutError()
      }

      guard let result = try await group.next() else {
        throw TimeoutError()
      }

      group.cancelAll()
      return result
    }
  }

  /// 타임아웃 에러 타입
  struct TimeoutError: Error {
    let localizedDescription = "Operation timed out"
  }

}
