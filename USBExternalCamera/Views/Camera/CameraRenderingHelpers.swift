//
//  CameraRenderingHelpers.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import CoreImage
import HaishinKit
import SwiftUI
import UIKit
import LiveStreamingCore

private enum CameraStreamingCompositionContext {
  static let ciContext = CIContext(options: [
    .useSoftwareRenderer: false,
    .cacheIntermediates: false,
  ])
}

// MARK: - Rendering Helpers Extension for CameraPreviewUIView

extension CameraPreviewUIView {
  func makeStreamingOverlaySnapshot(streamingSize: CGSize) -> CGImage? {
    let width = Int(streamingSize.width)
    let height = Int(streamingSize.height)
    guard width > 0, height > 0 else { return nil }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
      | CGBitmapInfo.byteOrder32Little.rawValue

    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
      )
    else {
      return nil
    }

    let currentSize = bounds.size
    guard currentSize.width > 0, currentSize.height > 0 else { return nil }

    let scaleX = streamingSize.width / currentSize.width
    let scaleY = streamingSize.height / currentSize.height
    let scale = max(scaleX, scaleY)
    let scaledSize = CGSize(width: currentSize.width * scale, height: currentSize.height * scale)
    let offsetX = (streamingSize.width - scaledSize.width) / 2.0
    let offsetY = (streamingSize.height - scaledSize.height) / 2.0

    context.clear(CGRect(origin: .zero, size: streamingSize))
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: offsetX / scale, y: offsetY / scale)

    for subview in subviews {
      subview.layer.render(in: context)
    }

    return context.makeImage()
  }

  func composeStreamingPixelBuffer(
    cameraFrame: CVPixelBuffer?,
    overlaySnapshot: CGImage?,
    streamingSize: CGSize
  ) -> CVPixelBuffer? {
    let width = Int(streamingSize.width)
    let height = Int(streamingSize.height)
    guard width > 0, height > 0 else { return nil }

    guard let outputBuffer = makeStreamingPixelBuffer(width: width, height: height) else {
      return nil
    }

    let backgroundImage: CIImage
    if let cameraFrame {
      backgroundImage = aspectFillImage(CIImage(cvPixelBuffer: cameraFrame), targetSize: streamingSize)
    } else {
      backgroundImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
        .cropped(to: CGRect(origin: .zero, size: streamingSize))
    }

    let composedImage: CIImage
    if let overlaySnapshot {
      let overlayImage = CIImage(cgImage: overlaySnapshot)
      composedImage = overlayImage.composited(over: backgroundImage)
    } else {
      composedImage = backgroundImage
    }

    CameraStreamingCompositionContext.ciContext.render(
      composedImage,
      to: outputBuffer,
      bounds: CGRect(origin: .zero, size: streamingSize),
      colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    )

    return outputBuffer
  }

  private func makeStreamingPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    let attrs = [
      kCVPixelBufferCGImageCompatibilityKey as String: kCFBooleanTrue as Any,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: kCFBooleanTrue as Any,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ] as CFDictionary

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess else { return nil }
    return pixelBuffer
  }

  private func aspectFillImage(_ image: CIImage, targetSize: CGSize) -> CIImage {
    let sourceRect = image.extent
    guard sourceRect.width > 0, sourceRect.height > 0 else {
      return image.cropped(to: CGRect(origin: .zero, size: targetSize))
    }

    let scaleX = targetSize.width / sourceRect.width
    let scaleY = targetSize.height / sourceRect.height
    let scale = max(scaleX, scaleY)
    let scaledWidth = sourceRect.width * scale
    let scaledHeight = sourceRect.height * scale
    let offsetX = (targetSize.width - scaledWidth) / 2.0
    let offsetY = (targetSize.height - scaledHeight) / 2.0

    return image
      .transformed(
        by: CGAffineTransform(scaleX: scale, y: scale)
          .translatedBy(x: offsetX / scale, y: offsetY / scale)
      )
      .cropped(to: CGRect(origin: .zero, size: targetSize))
  }

  /// 송출용 고해상도 카메라 프레임과 UI 합성
  ///
  /// 1920x1080 크기로 고품질 렌더링하여 업스케일링으로 인한 화질 저하 방지
  ///
  /// - Parameter cameraFrame: 실시간 카메라 프레임 (CVPixelBuffer)
  /// - Parameter streamingSize: 송출 목표 해상도 (1920x1080)
  /// - Returns: 고해상도 합성 이미지 또는 nil
  func renderCameraFrameWithUIForStreaming(cameraFrame: CVPixelBuffer, streamingSize: CGSize)
    -> UIImage?
  {

    // Step 1: 카메라 프레임을 UIImage로 변환
    guard let cameraImage = cameraFrame.toUIImage() else {
      logError("카메라 프레임 → UIImage 변환 실패", category: .performance)
      return nil
    }
    // Step 2: UI 오버레이를 고해상도로 생성 (1:1 → 16:9 비율 강제 변환)
    // 단말 크기에서 송출 크기로 스케일링 비율 계산
    let currentSize = bounds.size

    let scaleX = streamingSize.width / currentSize.width
    let scaleY = streamingSize.height / currentSize.height
    let scale = max(scaleX, scaleY)  // **Aspect Fill**: 화면 꽉 채우기 (1:1 문제 해결)

    let uiRenderer = UIGraphicsImageRenderer(size: streamingSize)
    let uiOverlay = uiRenderer.image { context in
      // Aspect Fill 스케일링으로 UI 렌더링 (화면 꽉 채우기)
      context.cgContext.scaleBy(x: scale, y: scale)

      // UI가 잘릴 수 있으므로 중앙 정렬
      let scaledSize = CGSize(width: currentSize.width * scale, height: currentSize.height * scale)
      let offsetX = (streamingSize.width - scaledSize.width) / 2.0
      let offsetY = (streamingSize.height - scaledSize.height) / 2.0
      context.cgContext.translateBy(x: offsetX / scale, y: offsetY / scale)

      // 프리뷰 레이어를 제외한 모든 서브뷰 렌더링
      for subview in subviews {
        // AVCaptureVideoPreviewLayer는 제외 (카메라 프레임으로 대체됨)
        if !(subview.layer is AVCaptureVideoPreviewLayer) {
          subview.layer.render(in: context.cgContext)
        }
      }
    }

    // Step 3: 카메라 이미지와 UI 오버레이를 고해상도로 합성
    let finalRenderer = UIGraphicsImageRenderer(size: streamingSize)
    let compositeImage = finalRenderer.image { context in
      let rect = CGRect(origin: .zero, size: streamingSize)

    // 3-1: 단말 프리뷰에서 카메라 영역을 추출
    // 캡처 타임의 렌더링 상태를 기준으로 계산하면 16:9 프리뷰 중심 정렬 오차를 줄일 수 있음
    let cameraPreviewRect = calculateCameraPreviewRect(in: currentSize)

    // UI와 카메라를 동일한 Aspect Fill 변환으로 맞춤
    let scaledCameraRect = mapRectToStreamingSpace(cameraPreviewRect, from: currentSize, to: streamingSize)

      // 카메라 이미지를 스케일된 영역에 맞춰 그리기 (Aspect Fill 방식)
      // Aspect Fill로 그려서 카메라 이미지가 잘리지 않도록 함
      let cameraAspectRatio = cameraImage.size.width / cameraImage.size.height
      let rectAspectRatio = scaledCameraRect.width / scaledCameraRect.height

      let drawRect: CGRect
      if cameraAspectRatio > rectAspectRatio {
        // 카메라가 더 넓음: 높이를 맞추고 가로는 넘침
        let drawHeight = scaledCameraRect.height
        let drawWidth = drawHeight * cameraAspectRatio
        let offsetX = scaledCameraRect.origin.x + (scaledCameraRect.width - drawWidth) / 2
        drawRect = CGRect(
          x: offsetX, y: scaledCameraRect.origin.y, width: drawWidth, height: drawHeight)
      } else {
        // 카메라가 더 높음: 너비를 맞추고 세로는 넘침
        let drawWidth = scaledCameraRect.width
        let drawHeight = drawWidth / cameraAspectRatio
        let offsetY = scaledCameraRect.origin.y + (scaledCameraRect.height - drawHeight) / 2
        drawRect = CGRect(
          x: scaledCameraRect.origin.x, y: offsetY, width: drawWidth, height: drawHeight)
      }

      cameraImage.draw(in: drawRect)

      // 3-2: UI 오버레이를 전체 화면에 합성
      uiOverlay.draw(in: rect, blendMode: .normal, alpha: 1.0)
    }

    return compositeImage
  }

  /// Source 좌표계의 rect를 streamingSize 기준 좌표계로 Aspect Fill 매핑
  /// (UI 오버레이 렌더링과 동일한 스케일/오프셋을 사용)
  private func mapRectToStreamingSpace(
    _ rect: CGRect,
    from sourceSize: CGSize,
    to streamingSize: CGSize
  ) -> CGRect {
    let scaleX = streamingSize.width / sourceSize.width
    let scaleY = streamingSize.height / sourceSize.height
    let scale = max(scaleX, scaleY)

    let scaledSourceSize = CGSize(
      width: sourceSize.width * scale,
      height: sourceSize.height * scale)
    let offsetX = (streamingSize.width - scaledSourceSize.width) / 2.0
    let offsetY = (streamingSize.height - scaledSourceSize.height) / 2.0

    let mappedRect = CGRect(
      x: (rect.origin.x * scale) + offsetX,
      y: (rect.origin.y * scale) + offsetY,
      width: rect.width * scale,
      height: rect.height * scale
    )

    return mappedRect
  }

  /// 단말 화면에서 카메라 프리뷰가 차지하는 16:9 영역 계산
  ///
  /// 실제 송출되는 16:9 비율 영역을 계산합니다.
  /// 이를 통해 프리뷰와 송출 화면이 정확히 일치하도록 합니다.
  ///
  /// - Parameter containerSize: 컨테이너 뷰의 크기 (단말 화면 크기)
  /// - Returns: 16:9 비율로 계산된 카메라 프리뷰 영역
  func calculateCameraPreviewRect(in containerSize: CGSize) -> CGRect {
    // 16:9 비율로 고정된 송출 영역 계산
    let aspectRatio: CGFloat = 16.0 / 9.0

    let previewFrame: CGRect
    if containerSize.width / containerSize.height > aspectRatio {
      // 세로가 기준: 높이에 맞춰서 너비 계산
      let width = containerSize.height * aspectRatio
      let offsetX = (containerSize.width - width) / 2
      previewFrame = CGRect(x: offsetX, y: 0, width: width, height: containerSize.height)
    } else {
      // 가로가 기준: 너비에 맞춰서 높이 계산
      let height = containerSize.width / aspectRatio
      let offsetY = (containerSize.height - height) / 2
      previewFrame = CGRect(x: 0, y: offsetY, width: containerSize.width, height: height)
    }

    logDebug("16:9 비율 송출 영역: \(previewFrame)", category: .camera)
    return previewFrame
  }

  /// AVCaptureVideoPreviewLayer의 실제 비디오 표시 영역 계산
  ///
  /// videoGravity 설정에 따라 실제로 비디오가 표시되는 영역을 정확히 계산합니다.
  /// - resizeAspect: 비디오 비율 유지, 레이어 내부에 맞춤 (검은 여백 가능)
  /// - resizeAspectFill: 비디오 비율 유지, 레이어 전체를 채움 (일부 잘림 가능)
  /// - resize: 비디오를 레이어 크기에 맞춰 늘림 (비율 왜곡 가능)
  ///
  /// - Parameter previewLayer: 카메라 프리뷰 레이어
  /// - Returns: 실제 비디오가 표시되는 영역
  func calculateActualVideoRect(previewLayer: AVCaptureVideoPreviewLayer) -> CGRect {
    let layerBounds = previewLayer.bounds
    let videoGravity = previewLayer.videoGravity

    // 카메라 세션에서 비디오 입력의 실제 해상도 가져오기
    guard let session = previewLayer.session else {
      logWarning("세션 없음, 레이어 전체 영역 반환: \(layerBounds)", category: .camera)
      return layerBounds
    }

    // 현재 활성 비디오 입력의 해상도 찾기
    var videoSize: CGSize?
    for input in session.inputs {
      if let deviceInput = input as? AVCaptureDeviceInput,
        deviceInput.device.hasMediaType(.video)
      {
        let format = deviceInput.device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        videoSize = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        break
      }
    }

    guard let actualVideoSize = videoSize else {
      logWarning("비디오 크기 확인 불가, 레이어 전체 영역 반환: \(layerBounds)", category: .camera)
      return layerBounds
    }

    logDebug(
      "비디오 크기: \(actualVideoSize), 레이어 크기: \(layerBounds.size), 중력: \(videoGravity)",
      category: .camera)

    let videoRect: CGRect

    switch videoGravity {
    case .resizeAspectFill:
      // Aspect Fill: 비디오 비율 유지하면서 레이어 전체를 채움 (일부 잘림 가능)
      let videoAspectRatio = actualVideoSize.width / actualVideoSize.height
      let layerAspectRatio = layerBounds.width / layerBounds.height

      if videoAspectRatio > layerAspectRatio {
        // 비디오가 더 넓음: 세로를 레이어에 맞추고 가로는 넘침
        let scaledHeight = layerBounds.height
        let scaledWidth = scaledHeight * videoAspectRatio
        let offsetX = (layerBounds.width - scaledWidth) / 2
        videoRect = CGRect(x: offsetX, y: 0, width: scaledWidth, height: scaledHeight)
      } else {
        // 비디오가 더 높음: 가로를 레이어에 맞추고 세로는 넘침
        let scaledWidth = layerBounds.width
        let scaledHeight = scaledWidth / videoAspectRatio
        let offsetY = (layerBounds.height - scaledHeight) / 2
        videoRect = CGRect(x: 0, y: offsetY, width: scaledWidth, height: scaledHeight)
      }

    case .resizeAspect:
      // Aspect Fit: 비디오 비율 유지하면서 레이어 내부에 맞춤 (검은 여백 가능)
      videoRect = AVMakeRect(aspectRatio: actualVideoSize, insideRect: layerBounds)

    case .resize:
      // 비율 무시하고 레이어 전체를 채움
      videoRect = layerBounds

    default:
      videoRect = layerBounds
    }

    logDebug("계산된 실제 비디오 영역: \(videoRect)", category: .camera)
    return videoRect
  }

  /// 송출용 고해상도 UI만 렌더링 (카메라 프레임 없을 때)
  ///
  /// **1:1 → 16:9 비율 강제 변환 적용**
  /// - Parameter streamingSize: 송출 목표 해상도 (1920x1080)
  /// - Returns: 고해상도 UI 이미지 또는 nil
  func renderUIOnlyForStreaming(streamingSize: CGSize) -> UIImage? {
    let currentSize = bounds.size
    guard currentSize.width > 0 && currentSize.height > 0 else {
      logError("유효하지 않은 뷰 크기: \(currentSize)", category: .performance)
      return nil
    }

    // 원본 UI 비율 계산
    let originalAspectRatio = currentSize.width / currentSize.height
    let targetAspectRatio = streamingSize.width / streamingSize.height

    logDebug("비율 분석:", category: .performance)
    logDebug(
      "  • 원본 UI: \(currentSize) (비율: \(String(format: "%.2f", originalAspectRatio)))",
      category: .performance)
    logDebug(
      "  • 목표 송출: \(streamingSize) (비율: \(String(format: "%.2f", targetAspectRatio)))",
      category: .performance)

    // **Aspect Fill 방식**: 화면을 꽉 채우기 위해 max 사용 (1:1 문제 해결)
    let scaleX = streamingSize.width / currentSize.width
    let scaleY = streamingSize.height / currentSize.height
    let scale = max(scaleX, scaleY)  // Aspect Fill - 화면 꽉 채우기

    logDebug(
      "  • 스케일링: scaleX=\(String(format: "%.2f", scaleX)), scaleY=\(String(format: "%.2f", scaleY))",
      category: .performance)
    logDebug("  • Aspect Fill 최종 스케일: \(String(format: "%.2f", scale))x", category: .performance)

    // 1:1 비율 문제 감지 경고 (개선된 감지)
    if abs(originalAspectRatio - 1.0) < 0.2 {  // 0.8~1.2 사이는 정사각형으로 간주
      logWarning(
        "1:1 문제 감지 - 원본 UI가 정사각형에 가까움 (비율: \(String(format: "%.2f", originalAspectRatio))) → Aspect Fill로 16:9 변환",
        category: .performance)
    }

    let renderer = UIGraphicsImageRenderer(size: streamingSize)
    return renderer.image { context in
      // 배경을 검은색으로 채우기 (카메라 프레임이 없을 때)
      context.cgContext.setFillColor(UIColor.black.cgColor)
      context.cgContext.fill(CGRect(origin: .zero, size: streamingSize))

      // Aspect Fill 스케일링으로 UI 렌더링 (화면 꽉 채우기)
      context.cgContext.scaleBy(x: scale, y: scale)

      // UI가 잘릴 수 있으므로 중앙 정렬
      let scaledSize = CGSize(width: currentSize.width * scale, height: currentSize.height * scale)
      let offsetX = (streamingSize.width - scaledSize.width) / 2.0
      let offsetY = (streamingSize.height - scaledSize.height) / 2.0
      context.cgContext.translateBy(x: offsetX / scale, y: offsetY / scale)

      layer.render(in: context.cgContext)

      logDebug(
        "Aspect Fill 렌더링 완료: \(originalAspectRatio) → \(targetAspectRatio)", category: .performance)
    }
  }

  /// 단말 표시용 카메라 프레임과 UI 합성 (기존 방식 유지)
  ///
  /// 이 메서드는 다음 3단계로 이미지를 합성합니다:
  /// 1. CVPixelBuffer(카메라 프레임)를 UIImage로 변환
  /// 2. UI 서브뷰들을 별도 이미지로 렌더링 (오버레이)
  /// 3. 카메라 이미지 위에 UI 오버레이를 합성
  ///
  /// **합성 방식:**
  /// - 카메라 이미지: aspect fill로 배치 (비율 유지하면서 화면 전체 채움)
  /// - UI 오버레이: 전체 화면에 normal 블렌드 모드로 합성
  ///
  /// - Parameter cameraFrame: 실시간 카메라 프레임 (CVPixelBuffer)
  /// - Parameter viewSize: 최종 출력 이미지 크기 (단말 화면 크기)
  /// - Returns: 합성된 최종 이미지 또는 nil
  func renderCameraFrameWithUI(cameraFrame: CVPixelBuffer, viewSize: CGSize) -> UIImage? {

    // Step 1: 카메라 프레임을 UIImage로 변환
    guard let cameraImage = cameraFrame.toUIImage() else {
      logError("카메라 프레임 → UIImage 변환 실패", category: .performance)
      return nil
    }
    logDebug("카메라 이미지 변환 성공: \(cameraImage.size)", category: .performance)

    // Step 2: UI 오버레이 생성 (카메라 프리뷰 레이어 제외)
    // 모든 서브뷰(버튼, 라벨, 워터마크 등)를 별도 이미지로 렌더링
    let uiRenderer = UIGraphicsImageRenderer(size: viewSize)
    let uiOverlay = uiRenderer.image { context in
      // 프리뷰 레이어를 제외한 모든 서브뷰 렌더링
      // (카메라 프리뷰는 이미 cameraImage에 포함되어 있음)
      for subview in subviews {
        subview.layer.render(in: context.cgContext)
      }
    }
    logDebug("UI 오버레이 생성 완료", category: .performance)

    // Step 3: 카메라 이미지와 UI 오버레이 합성
    let finalRenderer = UIGraphicsImageRenderer(size: viewSize)
    let compositeImage = finalRenderer.image { context in
      let rect = CGRect(origin: .zero, size: viewSize)

      // 3-1: 카메라 이미지를 뷰 크기에 맞게 그리기 (aspect fill 적용)
      // Aspect Fill: 원본 비율을 유지하면서 전체 영역을 채움 (일부 잘림 가능하지만 화면 꽉 채움)
      let cameraAspectRatio = cameraImage.size.width / cameraImage.size.height
      let rectAspectRatio = rect.width / rect.height

      let drawRect: CGRect
      if cameraAspectRatio > rectAspectRatio {
        // 카메라가 더 넓음: 높이를 맞추고 가로는 넘침
        let drawHeight = rect.height
        let drawWidth = drawHeight * cameraAspectRatio
        let offsetX = (rect.width - drawWidth) / 2
        drawRect = CGRect(x: offsetX, y: 0, width: drawWidth, height: drawHeight)
      } else {
        // 카메라가 더 높음: 너비를 맞추고 세로는 넘침
        let drawWidth = rect.width
        let drawHeight = drawWidth / cameraAspectRatio
        let offsetY = (rect.height - drawHeight) / 2
        drawRect = CGRect(x: 0, y: offsetY, width: drawWidth, height: drawHeight)
      }

      cameraImage.draw(in: drawRect)

      // 3-2: UI 오버레이를 전체 화면에 합성
      // normal 블렌드 모드: 투명 영역은 그대로 두고 불투명 영역만 덮어씀
      uiOverlay.draw(in: rect, blendMode: .normal, alpha: 1.0)
    }

    logDebug("최종 이미지 합성 완료: \(viewSize)", category: .performance)
    return compositeImage
  }

  /// 송출 해상도에 따른 최적 캡처 사이즈 계산 (16:9 비율 고정)
  ///
  /// **16:9 비율 강제 적용:**
  /// - 480p(854x480) → 16:9 비율로 수정 후 2배 업스케일
  /// - 720p(1280x720) → 2배 업스케일
  /// - 1080p(1920x1080) → 동일 해상도 캡처
  /// - 모든 해상도를 16:9 비율로 강제 변환
  ///
  /// - Returns: 16:9 비율이 보장된 최적 캡처 해상도
  func getOptimalCaptureSize() -> CGSize {
    var streamWidth: Int = 0
    var streamHeight: Int = 0

    if let target = streamingTargetSize {
      let width = Int(target.width)
      let height = Int(target.height)
      if width > 0 && height > 0 {
        streamWidth = width
        streamHeight = height
      }
    }

    if streamWidth == 0 || streamHeight == 0 {
      // HaishinKitManager에서 현재 스트리밍 설정 가져오기
      guard let manager = haishinKitManager,
        let settings = manager.getCurrentSettings()
      else {
        // 기본값: 720p (16:9 비율)
        return CGSize(width: 1280, height: 720)
      }

      streamWidth = settings.videoWidth
      streamHeight = settings.videoHeight
    }

    // 16:9 비율 강제 적용 (유튜브 라이브 표준)
    let aspectRatio: CGFloat = 16.0 / 9.0

    // 송출 해상도를 16:9 비율로 수정
    let correctedStreamSize: CGSize
    let currentAspectRatio = CGFloat(streamWidth) / CGFloat(streamHeight)

    if abs(currentAspectRatio - aspectRatio) > 0.1 {
      // 비율이 16:9가 아니면 강제로 수정
      let correctedHeight = CGFloat(streamWidth) / aspectRatio
      correctedStreamSize = CGSize(width: streamWidth, height: Int(correctedHeight))
    } else {
      correctedStreamSize = CGSize(width: streamWidth, height: streamHeight)
    }

    // 16:9 비율 기반 최적 캡처 해상도 계산
    let captureSize: CGSize
    let width = Int(correctedStreamSize.width)
    let height = Int(correctedStreamSize.height)

    switch (width, height) {
    case (640...854, 360...480):
      // 480p 계열: 업스케일 없이 목표 해상도 사용 (프레임 안정성 우선)
      captureSize = CGSize(width: width, height: height)

    case (1280, 720):
      // 720p: 업스케일 제거로 렌더링 부하 완화
      captureSize = CGSize(width: 1280, height: 720)

    case (1920, 1080):
      // 1080p는 송출 해상도와 동일 크기 유지 (안정성 우선)
      captureSize = CGSize(width: 1920, height: 1080)

    default:
      // 사용자 정의: 보정된 목표 해상도 그대로 사용
      captureSize = CGSize(width: width, height: height)
    }

    // 1080p 표준 해상도는 그대로 유지해 불필요한 리사이즈 오버헤드를 줄임
    if Int(captureSize.width) == 1920 && Int(captureSize.height) == 1080 {
      return captureSize
    }

    // 16의 배수로 정렬 (VideoCodec 호환성)
    let alignedWidth = ((Int(captureSize.width) + 15) / 16) * 16
    let alignedHeight = ((Int(captureSize.height) + 15) / 16) * 16
    let finalSize = CGSize(width: alignedWidth, height: alignedHeight)
    return finalSize
  }
}
