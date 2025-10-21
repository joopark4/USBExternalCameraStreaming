import Accelerate
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
  // MARK: - Manual Frame Injection Methods (최적화된 버전)

  /// 픽셀 버퍼 전처리 (사용자 설정 해상도 정확히 적용)
  func preprocessPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    guard let settings = currentSettings else {
      logger.debug("⚠️ 스트리밍 설정이 없어 스케일링 스킵")
      return pixelBuffer  // 설정이 없으면 원본 반환
    }

    let currentWidth = CVPixelBufferGetWidth(pixelBuffer)
    let currentHeight = CVPixelBufferGetHeight(pixelBuffer)

    // 🔧 사용자가 설정한 정확한 해상도로 변환
    let targetSize = CGSize(width: settings.videoWidth, height: settings.videoHeight)

    // 해상도가 정확히 일치하는지 확인
    if currentWidth == settings.videoWidth && currentHeight == settings.videoHeight {
      logger.debug("✅ 사용자 설정 해상도 일치: \(currentWidth)×\(currentHeight) - 변환 불필요")
      return pixelBuffer
    }

    logger.info(
      "🔄 사용자 설정 해상도로 정확히 변환: \(currentWidth)×\(currentHeight) → \(settings.videoWidth)×\(settings.videoHeight)"
    )

    // 성능 최적화 매니저를 통한 고성능 프레임 변환
    if let optimizedBuffer = performanceOptimizer.optimizedFrameConversion(
      pixelBuffer, targetSize: targetSize)
    {
      // 변환 결과 검증
      let resultWidth = CVPixelBufferGetWidth(optimizedBuffer)
      let resultHeight = CVPixelBufferGetHeight(optimizedBuffer)

      if resultWidth == settings.videoWidth && resultHeight == settings.videoHeight {
        logger.debug(
          "✅ 사용자 설정 해상도 변환 성공: \(resultWidth)×\(resultHeight) (\(String(format: "%.2f", performanceOptimizer.frameProcessingTime * 1000))ms)"
        )
        return optimizedBuffer
      } else {
        logger.error(
          "❌ 해상도 변환 검증 실패: 목표 \(settings.videoWidth)×\(settings.videoHeight) vs 결과 \(resultWidth)×\(resultHeight)"
        )
      }
    }

    // 폴백: 기존 방식
    logger.warning("⚠️ 성능 최적화 매니저 실패 - 기존 방식 폴백")

    // 1단계: VideoToolbox 최적화 포맷 변환 (YUV420 우선)
    guard let formatCompatibleBuffer = convertPixelBufferForVideoToolbox(pixelBuffer) else {
      logger.error("❌ VideoToolbox 포맷 변환 실패 - 원본 프레임 사용")
      return pixelBuffer
    }

    let originalWidth = CVPixelBufferGetWidth(formatCompatibleBuffer)
    let originalHeight = CVPixelBufferGetHeight(formatCompatibleBuffer)
    let targetWidth = settings.videoWidth
    let targetHeight = settings.videoHeight

    // 비율 계산 및 로깅 추가 (1:1 문제 추적)
    let originalAspectRatio = Double(originalWidth) / Double(originalHeight)
    let targetAspectRatio = Double(targetWidth) / Double(targetHeight)

    logger.info("📐 해상도 및 비율 검사:")
    logger.info(
      "   • 현재: \(originalWidth)x\(originalHeight) (비율: \(String(format: "%.2f", originalAspectRatio)))"
    )
    logger.info(
      "   • 목표: \(targetWidth)x\(targetHeight) (비율: \(String(format: "%.2f", targetAspectRatio)))")

    // 1:1 비율 감지 및 경고
    if abs(originalAspectRatio - 1.0) < 0.1 {
      logger.warning("⚠️ 1:1 정사각형 비율 감지! Aspect Fill로 16:9 변환 예정")
    }

    // 고품질 캡처된 프레임을 송출 해상도로 다운스케일링
    // (480p 송출을 위해 980p로 캡처된 프레임을 480p로 스케일링)
    if originalWidth != targetWidth || originalHeight != targetHeight {
      logger.info(
        "🔄 고품질 캡처 → 송출 해상도 스케일링: \(originalWidth)x\(originalHeight) → \(targetWidth)x\(targetHeight)"
      )
    } else {
      logger.debug("✅ 해상도 일치 - 스케일링 불필요")
      return formatCompatibleBuffer
    }

    let finalTargetSize = CGSize(width: targetWidth, height: targetHeight)
    guard let scaledPixelBuffer = scalePixelBuffer(formatCompatibleBuffer, to: finalTargetSize)
    else {
      logger.error("❌ 해상도 스케일링 실패 - 포맷 변환된 프레임으로 대체")
      return formatCompatibleBuffer  // 스케일링 실패 시 포맷만 변환된 버퍼 반환
    }

    // 3단계: 스케일링 성공 검증
    let finalWidth = CVPixelBufferGetWidth(scaledPixelBuffer)
    let finalHeight = CVPixelBufferGetHeight(scaledPixelBuffer)

    if finalWidth == targetWidth && finalHeight == targetHeight {
      logger.info("🎉 해상도 스케일링 완료 및 검증 성공: \(finalWidth)x\(finalHeight)")
      return scaledPixelBuffer
    } else {
      logger.error(
        "❌ 해상도 스케일링 검증 실패: 목표 \(targetWidth)x\(targetHeight) vs 결과 \(finalWidth)x\(finalHeight)")
      return formatCompatibleBuffer  // 검증 실패 시 포맷만 변환된 버퍼 반환
    }
  }

  /// CVPixelBuffer 해상도 스케일링 (고품질, HaishinKit 최적화, VideoCodec 호환성 보장)
  func scalePixelBuffer(_ pixelBuffer: CVPixelBuffer, to targetSize: CGSize)
    -> CVPixelBuffer?
  {
    // 16의 배수로 정렬된 해상도 계산 (H.264 인코더 요구사항) - 수정된 로직
    let requestedWidth = Int(targetSize.width)
    let requestedHeight = Int(targetSize.height)

    // 16의 배수 정렬 (화면 비율 유지를 위해 내림차순 적용)
    let alignedWidth = (requestedWidth / 16) * 16  // 내림 정렬 (화면 비율 유지)
    let alignedHeight = (requestedHeight / 16) * 16  // 내림 정렬 (화면 비율 유지)

    // 최소 해상도 보장 (160x120)
    let finalWidth = max(alignedWidth, 160)
    let finalHeight = max(alignedHeight, 120)

    // 해상도 변경 여부 로깅
    if finalWidth != requestedWidth || finalHeight != requestedHeight {
      logger.info(
        "📐 해상도 16의 배수 정렬: \(requestedWidth)x\(requestedHeight) → \(finalWidth)x\(finalHeight)")
    } else {
      logger.debug("✅ 해상도 이미 16의 배수: \(finalWidth)x\(finalHeight)")
    }

    // HaishinKit 최적화 속성으로 픽셀 버퍼 생성
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 64,  // 16 → 64로 증가 (더 안전한 정렬)
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: finalWidth,
      kCVPixelBufferHeightKey as String: finalHeight,
    ]

    var outputBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      finalWidth,
      finalHeight,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &outputBuffer
    )

    guard status == kCVReturnSuccess, let scaledBuffer = outputBuffer else {
      logger.error("❌ CVPixelBuffer 생성 실패: \(status)")
      return nil
    }

    // Core Image를 사용한 고품질 스케일링 (개선된 방법)
    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)

    // 정확한 스케일링을 위한 bounds 계산
    let targetRect = CGRect(x: 0, y: 0, width: finalWidth, height: finalHeight)
    let sourceRect = inputImage.extent

    // Aspect Fill 스케일링 (화면 꽉 채우기, 16:9 비율 유지) - 1:1 문제 해결
    let scaleX = CGFloat(finalWidth) / sourceRect.width
    let scaleY = CGFloat(finalHeight) / sourceRect.height
    let scale = max(scaleX, scaleY)  // Aspect Fill - 화면 꽉 채우기 (1:1 → 16:9 비율)

    let scaledWidth = sourceRect.width * scale
    let scaledHeight = sourceRect.height * scale

    // 중앙 정렬을 위한 오프셋 계산 (넘치는 부분은 잘림)
    let offsetX = (CGFloat(finalWidth) - scaledWidth) / 2.0
    let offsetY = (CGFloat(finalHeight) - scaledHeight) / 2.0

    let transform = CGAffineTransform(scaleX: scale, y: scale)
      .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))

    let scaledImage = inputImage.transformed(by: transform)

    // GPU 가속 CIContext 생성 (개선된 설정)
    let context = CIContext(options: [
      .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      .useSoftwareRenderer: false,  // GPU 사용
      .priorityRequestLow: false,  // 고우선순위
      .cacheIntermediates: false,  // 메모리 절약
    ])

    // CVPixelBuffer에 정확한 크기로 렌더링
    do {
      context.render(
        scaledImage, to: scaledBuffer, bounds: targetRect,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    } catch {
      logger.error("❌ CIContext 렌더링 실패: \(error)")
      return nil
    }

    // 스케일링 결과 검증
    let resultWidth = CVPixelBufferGetWidth(scaledBuffer)
    let resultHeight = CVPixelBufferGetHeight(scaledBuffer)

    if resultWidth == finalWidth && resultHeight == finalHeight {
      let originalInputRatio =
        Double(CVPixelBufferGetWidth(pixelBuffer)) / Double(CVPixelBufferGetHeight(pixelBuffer))
      let finalOutputRatio = Double(finalWidth) / Double(finalHeight)

      logger.info("✅ Aspect Fill 스케일링 성공:")
      logger.info(
        "   • 입력: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)) (비율: \(String(format: "%.2f", originalInputRatio)))"
      )
      logger.info(
        "   • 출력: \(finalWidth)x\(finalHeight) (비율: \(String(format: "%.2f", finalOutputRatio)))")
      logger.info("   • 1:1 → 16:9 변환: \(abs(originalInputRatio - 1.0) < 0.1 ? "✅완료" : "N/A")")
      return scaledBuffer
    } else {
      logger.error(
        "❌ 스케일링 결과 불일치: 예상 \(finalWidth)x\(finalHeight) vs 실제 \(resultWidth)x\(resultHeight)")
      return nil
    }
  }

  /// CVPixelBuffer를 CMSampleBuffer로 변환 (HaishinKit 완벽 호환성)
  func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
    // 1. CVPixelBuffer 입력 검증
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    logger.debug("🎬 CMSampleBuffer 생성 시작: \(width)x\(height) 포맷:\(pixelFormat)")

    // 2. HaishinKit 필수 포맷 강제 확인
    let supportedFormats: [OSType] = [
      kCVPixelFormatType_32BGRA,  // 주요 포맷 (HaishinKit 권장)
      kCVPixelFormatType_32ARGB,  // 대체 포맷
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,  // YUV 포맷
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
    ]

    if !supportedFormats.contains(pixelFormat) {
      logger.error("❌ 지원되지 않는 픽셀 포맷: \(pixelFormat) → 포맷 변환 시도")

      // 강제 포맷 변환
      if let convertedBuffer = convertToSupportedFormat(pixelBuffer) {
        logger.info("✅ 픽셀 포맷 변환 성공: \(pixelFormat) → \(kCVPixelFormatType_32BGRA)")
        return createSampleBuffer(from: convertedBuffer)
      } else {
        logger.error("❌ 픽셀 포맷 변환 실패 - CMSampleBuffer 생성 중단")
        return nil
      }
    }

    // 3. CVFormatDescription 생성 (중요: 정확한 비디오 메타데이터)
    var formatDescription: CMFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )

    guard formatStatus == noErr, let videoDesc = formatDescription else {
      logger.error("❌ CMVideoFormatDescription 생성 실패: \(formatStatus)")
      return nil
    }

    // 4. CMSampleTiming 설정 (정확한 타이밍 정보)
    let frameDuration = CMTime(value: 1, timescale: 30)  // 30fps 기준
    let currentTime = CMClockGetTime(CMClockGetHostTimeClock())

    var sampleTiming = CMSampleTimingInfo(
      duration: frameDuration,
      presentationTimeStamp: currentTime,
      decodeTimeStamp: CMTime.invalid  // 실시간 스트리밍에서는 invalid
    )

    // 5. CMSampleBuffer 생성 (HaishinKit 최적화)
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: videoDesc,
      sampleTiming: &sampleTiming,
      sampleBufferOut: &sampleBuffer
    )

    guard sampleStatus == noErr, let finalBuffer = sampleBuffer else {
      logger.error("❌ CMSampleBuffer 생성 실패: \(sampleStatus)")
      return nil
    }

    // 6. 최종 검증 및 HaishinKit 호환성 확인
    if CMSampleBufferIsValid(finalBuffer) {
      // 추가 검증: 데이터 무결성 확인
      guard CMSampleBufferGetNumSamples(finalBuffer) > 0 else {
        logger.error("❌ CMSampleBuffer에 유효한 샘플이 없음")
        return nil
      }

      // CVPixelBuffer 재확인
      guard CMSampleBufferGetImageBuffer(finalBuffer) != nil else {
        logger.error("❌ CMSampleBuffer에서 ImageBuffer 추출 실패")
        return nil
      }

      logger.debug("✅ HaishinKit 호환 CMSampleBuffer 생성 완료: \(width)x\(height)")
      return finalBuffer
    } else {
      logger.error("❌ 생성된 CMSampleBuffer 유효성 검증 실패")
      return nil
    }
  }

  /// VideoCodec -12902 에러 해결을 위한 BGRA → YUV420 포맷 변환
  func convertToSupportedFormat(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
    let originalHeight = CVPixelBufferGetHeight(pixelBuffer)
    let currentFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    // VideoCodec 안정성을 위한 해상도 16의 배수 정렬
    let width = ((originalWidth + 15) / 16) * 16  // 16의 배수로 올림
    let height = ((originalHeight + 15) / 16) * 16  // 16의 배수로 올림

    if width != originalWidth || height != originalHeight {
      logger.debug("🔧 해상도 16배수 정렬: \(originalWidth)x\(originalHeight) → \(width)x\(height)")
    }

    // VideoCodec이 선호하는 YUV420 포맷으로 변환 (VideoCodec -12902 에러 해결)
    let targetFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    logger.info(
      "🔄 [convertToSupportedFormat] BGRA→YUV420 변환: \(currentFormat) → \(targetFormat) (\(width)x\(height))"
    )

    // 이미 YUV420 포맷이면 그대로 반환
    if currentFormat == targetFormat {
      logger.info("✅ [convertToSupportedFormat] 이미 YUV420 포맷 - 변환 불필요")
      return pixelBuffer
    }

    // VideoCodec 최적화를 위한 YUV420 속성 설정
    let attributes: [String: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 16,  // YUV420에 최적화된 정렬
      kCVPixelBufferPixelFormatTypeKey as String: targetFormat,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferPlaneAlignmentKey as String: 16,  // YUV420 플레인 정렬
    ]

    var yuvBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      targetFormat,
      attributes as CFDictionary,
      &yuvBuffer
    )

    guard createStatus == kCVReturnSuccess, let outputBuffer = yuvBuffer else {
      logger.error("❌ YUV420 픽셀버퍼 생성 실패: \(createStatus)")

      // 폴백: BGRA 포맷으로 대체 (기존 방식)
      return convertToBGRAFormat(pixelBuffer)
    }

    // 해상도가 변경된 경우 먼저 스케일링 수행
    var processedPixelBuffer = pixelBuffer
    if width != originalWidth || height != originalHeight {
      if let scaledBuffer = scalePixelBuffer(pixelBuffer, toWidth: width, toHeight: height) {
        processedPixelBuffer = scaledBuffer
      } else {
        logger.warning("⚠️ 픽셀버퍼 스케일링 실패 - 원본 크기 사용")
      }
    }

    // vImage를 사용한 고성능 BGRA → YUV420 변환
    let conversionSuccess = convertBGRAToYUV420UsingvImage(
      sourceBuffer: processedPixelBuffer,
      destinationBuffer: outputBuffer
    )

    if conversionSuccess {
      logger.debug("✅ VideoCodec 최적화 변환 성공: \(width)x\(height) → YUV420")
      return outputBuffer
    } else {
      logger.warning("⚠️ vImage 변환 실패 - CIImage 폴백 시도")

      // 폴백: CIImage를 통한 변환
      if let fallbackBuffer = convertBGRAToYUV420UsingCIImage(pixelBuffer) {
        logger.debug("✅ CIImage 폴백 변환 성공")
        return fallbackBuffer
      } else {
        logger.error("❌ 모든 YUV420 변환 방법 실패 - BGRA 폴백")
        return convertToBGRAFormat(pixelBuffer)
      }
    }
  }

  /// vImage를 사용한 고성능 BGRA → YUV420 변환 (채널 순서 변환 포함)
  func convertBGRAToYUV420UsingvImage(
    sourceBuffer: CVPixelBuffer, destinationBuffer: CVPixelBuffer
  ) -> Bool {
    CVPixelBufferLockBaseAddress(sourceBuffer, .readOnly)
    CVPixelBufferLockBaseAddress(destinationBuffer, [])

    defer {
      CVPixelBufferUnlockBaseAddress(sourceBuffer, .readOnly)
      CVPixelBufferUnlockBaseAddress(destinationBuffer, [])
    }

    let width = CVPixelBufferGetWidth(sourceBuffer)
    let height = CVPixelBufferGetHeight(sourceBuffer)

    // 소스 BGRA 버퍼 정보
    guard let sourceBaseAddress = CVPixelBufferGetBaseAddress(sourceBuffer) else {
      logger.error("❌ 소스 픽셀버퍼 주소 획득 실패")
      return false
    }

    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(sourceBuffer)

    // 1단계: BGRA → ARGB 채널 순서 변환을 위한 임시 버퍼 생성
    guard let argbData = malloc(sourceBytesPerRow * height) else {
      logger.error("❌ ARGB 변환용 임시 버퍼 할당 실패")
      return false
    }
    defer { free(argbData) }

    // BGRA → ARGB 채널 순서 변환 수행
    if !swapBGRAToARGBChannels(
      sourceData: sourceBaseAddress,
      destinationData: argbData,
      width: width,
      height: height,
      sourceBytesPerRow: sourceBytesPerRow,
      destinationBytesPerRow: sourceBytesPerRow
    ) {
      logger.error("❌ BGRA → ARGB 채널 순서 변환 실패")
      return false
    }

    // YUV420 대상 버퍼 정보
    guard let yPlaneAddress = CVPixelBufferGetBaseAddressOfPlane(destinationBuffer, 0),
      let uvPlaneAddress = CVPixelBufferGetBaseAddressOfPlane(destinationBuffer, 1)
    else {
      logger.error("❌ YUV420 플레인 주소 획득 실패")
      return false
    }

    let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destinationBuffer, 0)
    let uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(destinationBuffer, 1)

    // 2단계: vImage 버퍼 구조체 설정 (ARGB 변환된 데이터 사용)
    var sourceImageBuffer = vImage_Buffer(
      data: argbData,  // 변환된 ARGB 데이터 사용
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: sourceBytesPerRow
    )

    var yPlaneBuffer = vImage_Buffer(
      data: yPlaneAddress,
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: yBytesPerRow
    )

    var uvPlaneBuffer = vImage_Buffer(
      data: uvPlaneAddress,
      height: vImagePixelCount(height / 2),
      width: vImagePixelCount(width / 2),
      rowBytes: uvBytesPerRow
    )

    // BGRA → YUV420 변환 정보 설정 (색상 순서 수정)
    var info = vImage_ARGBToYpCbCr()
    var pixelRange = vImage_YpCbCrPixelRange(
      Yp_bias: 16,
      CbCr_bias: 128,
      YpRangeMax: 235,
      CbCrRangeMax: 240,
      YpMax: 235,
      YpMin: 16,
      CbCrMax: 240,
      CbCrMin: 16)

    // ITU-R BT.709 변환 행렬 설정 (HD용) - ARGB 순서 사용 (vImage 표준)
    let error = vImageConvert_ARGBToYpCbCr_GenerateConversion(
      kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2,
      &pixelRange,
      &info,
      kvImageARGB8888,  // vImage 표준 ARGB 포맷 사용
      kvImage420Yp8_CbCr8,
      vImage_Flags(kvImageNoFlags)
    )

    guard error == kvImageNoError else {
      logger.error("❌ vImage 변환 설정 실패: \(error)")
      return false
    }

    // BGRA 데이터를 ARGB 순서로 변환한 후 YUV420 변환 수행
    // vImage는 ARGB 순서를 기본으로 하므로 데이터 순서 조정 후 변환
    let conversionError = vImageConvert_ARGB8888To420Yp8_CbCr8(
      &sourceImageBuffer,
      &yPlaneBuffer,
      &uvPlaneBuffer,
      &info,
      UnsafePointer<UInt8>?.none,  // nil 대신 명시적 타입 지정
      vImage_Flags(kvImageNoFlags)
    )

    if conversionError == kvImageNoError {
      logger.debug("✅ vImage BGRA→YUV420 변환 성공: \(width)x\(height)")
      return true
    } else {
      logger.error("❌ vImage BGRA→YUV420 변환 실패: \(conversionError)")
      return false
    }
  }

  /// CIImage를 사용한 BGRA → YUV420 변환 (폴백)
  func convertBGRAToYUV420UsingCIImage(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // YUV420 버퍼 생성
    var yuvBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      nil,
      &yuvBuffer
    )

    guard createStatus == kCVReturnSuccess, let outputBuffer = yuvBuffer else {
      return nil
    }

    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext(options: [
      .workingColorSpace: CGColorSpace(name: CGColorSpace.itur_709)!,  // YUV에 적합한 색공간
      .outputColorSpace: CGColorSpace(name: CGColorSpace.itur_709)!,
      .useSoftwareRenderer: false,
      .cacheIntermediates: false,
    ])

    let targetRect = CGRect(x: 0, y: 0, width: width, height: height)

    do {
      context.render(
        inputImage, to: outputBuffer, bounds: targetRect,
        colorSpace: CGColorSpace(name: CGColorSpace.itur_709)!)
      return outputBuffer
    } catch {
      logger.error("❌ CIImage YUV420 변환 실패: \(error)")
      return nil
    }
  }

  /// 폴백용 BGRA 포맷 변환 (기존 방식)
  func convertToBGRAFormat(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let currentFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let targetFormat = kCVPixelFormatType_32BGRA

    // 이미 BGRA면 그대로 반환
    if currentFormat == targetFormat {
      return pixelBuffer
    }

    logger.debug("🔄 폴백 BGRA 변환: \(currentFormat) → \(targetFormat)")

    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
    ]

    var convertedBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      targetFormat,
      attributes as CFDictionary,
      &convertedBuffer
    )

    guard status == kCVReturnSuccess, let outputBuffer = convertedBuffer else {
      return nil
    }

    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext(options: [.useSoftwareRenderer: false])
    let targetRect = CGRect(x: 0, y: 0, width: width, height: height)

    context.render(
      inputImage, to: outputBuffer, bounds: targetRect,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

    return outputBuffer
  }

  /// BGRA → ARGB 채널 순서 변환 (vImage 호환성을 위한 전처리)
  func swapBGRAToARGBChannels(
    sourceData: UnsafeRawPointer,
    destinationData: UnsafeMutableRawPointer,
    width: Int,
    height: Int,
    sourceBytesPerRow: Int,
    destinationBytesPerRow: Int
  ) -> Bool {

    // vImage를 사용한 고성능 채널 순서 변환
    var sourceBuffer = vImage_Buffer(
      data: UnsafeMutableRawPointer(mutating: sourceData),
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: sourceBytesPerRow
    )

    var destinationBuffer = vImage_Buffer(
      data: destinationData,
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: destinationBytesPerRow
    )

    // BGRA(0,1,2,3) → ARGB(3,0,1,2) 순서 변환
    // B=0, G=1, R=2, A=3 → A=3, R=2, G=1, B=0
    let channelOrder: [UInt8] = [3, 2, 1, 0]  // ARGB 순서

    let error = vImagePermuteChannels_ARGB8888(
      &sourceBuffer,
      &destinationBuffer,
      channelOrder,
      vImage_Flags(kvImageNoFlags)
    )

    if error == kvImageNoError {
      logger.debug("✅ BGRA → ARGB 채널 순서 변환 성공")
      return true
    } else {
      logger.error("❌ BGRA → ARGB 채널 순서 변환 실패: \(error)")

      // 폴백: 수동 채널 변환
      return swapChannelsManually(
        sourceData: sourceData,
        destinationData: destinationData,
        width: width,
        height: height,
        sourceBytesPerRow: sourceBytesPerRow,
        destinationBytesPerRow: destinationBytesPerRow
      )
    }
  }

  /// 수동 채널 순서 변환 (vImage 실패 시 폴백)
  func swapChannelsManually(
    sourceData: UnsafeRawPointer,
    destinationData: UnsafeMutableRawPointer,
    width: Int,
    height: Int,
    sourceBytesPerRow: Int,
    destinationBytesPerRow: Int
  ) -> Bool {

    let sourceBytes = sourceData.assumingMemoryBound(to: UInt8.self)
    let destinationBytes = destinationData.assumingMemoryBound(to: UInt8.self)

    for y in 0..<height {
      for x in 0..<width {
        let sourcePixelIndex = y * sourceBytesPerRow + x * 4
        let destPixelIndex = y * destinationBytesPerRow + x * 4

        // BGRA → ARGB 변환
        // 소스: [B, G, R, A]
        // 대상: [A, R, G, B]
        destinationBytes[destPixelIndex + 0] = sourceBytes[sourcePixelIndex + 3]  // A
        destinationBytes[destPixelIndex + 1] = sourceBytes[sourcePixelIndex + 2]  // R
        destinationBytes[destPixelIndex + 2] = sourceBytes[sourcePixelIndex + 1]  // G
        destinationBytes[destPixelIndex + 3] = sourceBytes[sourcePixelIndex + 0]  // B
      }
    }

    logger.debug("✅ 수동 BGRA → ARGB 채널 순서 변환 완료")
    return true
  }

  /// 픽셀 버퍼를 지정된 크기로 스케일링 (16의 배수 정렬용)
  func scalePixelBuffer(
    _ pixelBuffer: CVPixelBuffer, toWidth newWidth: Int, toHeight newHeight: Int
  ) -> CVPixelBuffer? {
    let originalWidth = CVPixelBufferGetWidth(pixelBuffer)
    let originalHeight = CVPixelBufferGetHeight(pixelBuffer)

    // 크기가 같으면 원본 반환
    if newWidth == originalWidth && newHeight == originalHeight {
      return pixelBuffer
    }

    logger.debug("🔧 픽셀버퍼 스케일링: \(originalWidth)x\(originalHeight) → \(newWidth)x\(newHeight)")

    // CIImage를 사용한 스케일링
    let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
    let scaleX = CGFloat(newWidth) / CGFloat(originalWidth)
    let scaleY = CGFloat(newHeight) / CGFloat(originalHeight)

    let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    // 스케일된 픽셀 버퍼 생성
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 16,
    ]

    var scaledBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      newWidth,
      newHeight,
      CVPixelBufferGetPixelFormatType(pixelBuffer),
      attributes as CFDictionary,
      &scaledBuffer
    )

    guard createStatus == kCVReturnSuccess, let outputBuffer = scaledBuffer else {
      logger.error("❌ 스케일된 픽셀버퍼 생성 실패: \(createStatus)")
      return nil
    }

    let context = CIContext(options: [.useSoftwareRenderer: false])
    let targetRect = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)

    context.render(
      scaledImage, to: outputBuffer, bounds: targetRect,
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

    return outputBuffer
  }

  /// VideoToolbox 하드웨어 최적화를 위한 픽셀 버퍼 포맷 변환
  func convertPixelBufferForVideoToolbox(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let currentFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    // VideoToolbox 하드웨어 인코더가 가장 효율적으로 처리하는 포맷 우선순위:
    // 1. YUV420 (하드웨어 가속 최적화)
    // 2. BGRA (폴백용)
    let preferredFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    if currentFormat == preferredFormat {
      logger.debug("✅ 이미 VideoToolbox 최적화 포맷(YUV420)")
      return pixelBuffer
    }

    // YUV420 변환 시도 (하드웨어 가속 최대화)
    if let yuvBuffer = convertToYUV420Format(pixelBuffer) {
      logger.debug("🚀 VideoToolbox YUV420 변환 성공 - 하드웨어 가속 최적화")
      return yuvBuffer
    }

    // 폴백: BGRA 포맷 변환
    logger.debug("⚠️ YUV420 변환 실패 - BGRA 폴백")
    return convertToSupportedFormat(pixelBuffer)
  }

  /// YUV420 포맷으로 변환 (VideoToolbox 하드웨어 가속 최적화)
  func convertToYUV420Format(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    // YUV420 픽셀 버퍼 생성
    let attributes: [String: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      kCVPixelBufferBytesPerRowAlignmentKey as String: 16,
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferPlaneAlignmentKey as String: 16,
    ]

    var yuvBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      attributes as CFDictionary,
      &yuvBuffer
    )

    guard createStatus == kCVReturnSuccess, let outputBuffer = yuvBuffer else {
      logger.warning("⚠️ YUV420 픽셀버퍼 생성 실패: \(createStatus)")
      return nil
    }

    // vImage를 사용한 고성능 BGRA → YUV420 변환
    let conversionSuccess = convertBGRAToYUV420UsingvImage(
      sourceBuffer: pixelBuffer,
      destinationBuffer: outputBuffer
    )

    if conversionSuccess {
      logger.debug("✅ VideoToolbox YUV420 변환 성공")
      return outputBuffer
    } else {
      logger.warning("⚠️ YUV420 변환 실패")
      return nil
    }
  }

  /// CVPixelBuffer를 HaishinKit 호환 포맷으로 변환 (convertToSupportedFormat 대체용)
  func convertPixelBufferFormat(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    // convertToSupportedFormat와 동일한 로직 사용
    return convertToSupportedFormat(pixelBuffer)
  }

  /// 화면 캡처 모드로 스트리밍 시작
  /// CameraPreviewUIView 화면을 송출하는 특별한 모드
  public func startScreenCaptureStreaming(with settings: USBExternalCamera.LiveStreamSettings)
    async throws
  {
    logger.info("🎬 화면 캡처 스트리밍 모드 시작")

    // 일반적인 스트리밍 시작과 동일하지만 카메라 연결은 생략
    guard !isStreaming else {
      logger.warning("⚠️ 이미 스트리밍 중입니다")
      throw LiveStreamError.streamingFailed("이미 스트리밍이 진행 중입니다")
    }

    // 사용자 원본 설정 보존 (덮어쓰기 방지)
    originalUserSettings = settings

    // 현재 설정 저장
    currentSettings = settings
    saveSettings(settings)

    // 상태 업데이트
    currentStatus = .connecting
    connectionStatus = "화면 캡처 모드 연결 중..."

    do {
      // 🚀 빠른 연결을 위한 최적화된 시퀀스
      logger.info("🚀 화면 캡처 스트리밍: 빠른 연결 모드 시작", category: .system)

      // 1단계: RTMP 연결 우선 (가장 중요한 부분)
      let preference = StreamPreference(
        rtmpURL: settings.rtmpURL,
        streamKey: settings.streamKey
      )
      await streamSwitcher.setPreference(preference)

      // 2단계: 실제 RTMP 연결 시작 (병렬 처리 준비)
      async let rtmpConnection: () = streamSwitcher.startStreaming()

      // 3단계: 동시에 로컬 설정들 초기화 (RTMP 연결과 병렬)
      async let localSetup: () = setupLocalComponentsInParallel(settings)

      // 4단계: 두 작업 완료 대기
      try await rtmpConnection
      try await localSetup

      logger.info("✅ 병렬 초기화 완료: RTMP 연결 + 로컬 설정", category: .system)

      // 5단계: 최종 후처리 (최소화)
      try await finalizeScreenCaptureConnection()

      // 상태 업데이트 및 모니터링 시작
      isStreaming = true
      isScreenCaptureMode = true  // 화면 캡처 모드 플래그 설정
      currentStatus = .streaming
      connectionStatus = "화면 캡처 스트리밍 중..."

      startDataMonitoring()

      // 연결 안정화 후 모니터링 시작 (최적화: 5초 → 2초로 단축)
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.startConnectionHealthMonitoring()
      }

      logger.info("🎉 화면 캡처 스트리밍 시작 성공 - 빠른 연결 모드")

    } catch {
      logger.error("❌ 화면 캡처 스트리밍 시작 실패: \(error)")

      // 실패 시 정리
      currentStatus = .error(
        error as? LiveStreamError ?? LiveStreamError.streamingFailed(error.localizedDescription))
      connectionStatus = "화면 캡처 연결 실패"
      isStreaming = false
      isScreenCaptureMode = false

      throw error
    }
  }

}
