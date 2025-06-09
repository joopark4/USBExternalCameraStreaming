//
//  CameraRenderingHelpers.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import HaishinKit
import SwiftUI
import UIKit
import Foundation

// MARK: - Rendering Helpers Extension for CameraPreviewUIView

extension CameraPreviewUIView {
  
  /// 송출용 고해상도 카메라 프레임과 UI 합성
  /// 
  /// 1920x1080 크기로 고품질 렌더링하여 업스케일링으로 인한 화질 저하 방지
  /// 
  /// - Parameter cameraFrame: 실시간 카메라 프레임 (CVPixelBuffer)
  /// - Parameter streamingSize: 송출 목표 해상도 (1920x1080)
  /// - Returns: 고해상도 합성 이미지 또는 nil
  func renderCameraFrameWithUIForStreaming(cameraFrame: CVPixelBuffer, streamingSize: CGSize) -> UIImage? {
    
    // Step 1: 카메라 프레임을 UIImage로 변환
    guard let cameraImage = cameraFrame.toUIImage() else {
      logError("카메라 프레임 → UIImage 변환 실패", category: .performance)
      return nil
    }
    logDebug("카메라 이미지 변환 성공: \(cameraImage.size)", category: .performance)
    
    // Step 2: UI 오버레이를 고해상도로 생성 (1:1 → 16:9 비율 강제 변환)
    // 단말 크기에서 송출 크기로 스케일링 비율 계산
    let currentSize = bounds.size
    let originalAspectRatio = currentSize.width / currentSize.height
    let targetAspectRatio = streamingSize.width / streamingSize.height
    
    let scaleX = streamingSize.width / currentSize.width
    let scaleY = streamingSize.height / currentSize.height
    let scale = max(scaleX, scaleY) // **Aspect Fill**: 화면 꽉 채우기 (1:1 문제 해결)
    
    logDebug("비율 분석:", category: .performance)
    logDebug("  • 원본 UI: \(currentSize) (비율: \(String(format: "%.2f", originalAspectRatio)))", category: .performance)
    logDebug("  • 목표 송출: \(streamingSize) (비율: \(String(format: "%.2f", targetAspectRatio)))", category: .performance)
    logDebug("  • Aspect Fill 스케일: \(String(format: "%.2f", scale))x", category: .performance)
    
    // 1:1 비율 문제 감지
    if abs(originalAspectRatio - 1.0) < 0.2 {
      logWarning("1:1 문제 감지 - 카메라+UI 합성에서 정사각형 UI 감지 → Aspect Fill 적용", category: .performance)
    }
    
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
    logDebug("UI 오버레이 생성 완료: \(streamingSize)", category: .performance)
    
    // Step 3: 카메라 이미지와 UI 오버레이를 고해상도로 합성
    let finalRenderer = UIGraphicsImageRenderer(size: streamingSize)
    let compositeImage = finalRenderer.image { context in
      let rect = CGRect(origin: .zero, size: streamingSize)
      
      // 3-1: 카메라 이미지를 UI와 동일한 비율로 업스케일링
      // 단말에서의 카메라 프리뷰 영역을 계산
      let cameraPreviewRect = calculateCameraPreviewRect(in: currentSize)
      
      // 카메라 프리뷰 영역을 동일한 스케일 비율로 업스케일링
      let scaledCameraRect = CGRect(
        x: cameraPreviewRect.origin.x * scale,
        y: cameraPreviewRect.origin.y * scale,
        width: cameraPreviewRect.size.width * scale,
        height: cameraPreviewRect.size.height * scale
      )
      
      logDebug("카메라 영역 스케일링: \(cameraPreviewRect) → \(scaledCameraRect)", category: .performance)
      
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
        drawRect = CGRect(x: offsetX, y: scaledCameraRect.origin.y, width: drawWidth, height: drawHeight)
      } else {
        // 카메라가 더 높음: 너비를 맞추고 세로는 넘침
        let drawWidth = scaledCameraRect.width
        let drawHeight = drawWidth / cameraAspectRatio
        let offsetY = scaledCameraRect.origin.y + (scaledCameraRect.height - drawHeight) / 2
        drawRect = CGRect(x: scaledCameraRect.origin.x, y: offsetY, width: drawWidth, height: drawHeight)
      }
      
      logDebug("카메라 이미지 Aspect Fill 그리기: \(scaledCameraRect) → \(drawRect)", category: .performance)
      cameraImage.draw(in: drawRect)
      
      // 3-2: UI 오버레이를 전체 화면에 합성
      uiOverlay.draw(in: rect, blendMode: .normal, alpha: 1.0)
    }
    
    logDebug("최종 이미지 합성 완료: \(streamingSize)", category: .performance)
    return compositeImage
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
         deviceInput.device.hasMediaType(.video) {
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
    
    logDebug("비디오 크기: \(actualVideoSize), 레이어 크기: \(layerBounds.size), 중력: \(videoGravity)", category: .camera)
    
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
    logDebug("  • 원본 UI: \(currentSize) (비율: \(String(format: "%.2f", originalAspectRatio)))", category: .performance)
    logDebug("  • 목표 송출: \(streamingSize) (비율: \(String(format: "%.2f", targetAspectRatio)))", category: .performance)
    
    // **Aspect Fill 방식**: 화면을 꽉 채우기 위해 max 사용 (1:1 문제 해결)
    let scaleX = streamingSize.width / currentSize.width
    let scaleY = streamingSize.height / currentSize.height
    let scale = max(scaleX, scaleY) // Aspect Fill - 화면 꽉 채우기
    
    logDebug("  • 스케일링: scaleX=\(String(format: "%.2f", scaleX)), scaleY=\(String(format: "%.2f", scaleY))", category: .performance)
    logDebug("  • Aspect Fill 최종 스케일: \(String(format: "%.2f", scale))x", category: .performance)
    
    // 1:1 비율 문제 감지 경고 (개선된 감지)
    if abs(originalAspectRatio - 1.0) < 0.2 { // 0.8~1.2 사이는 정사각형으로 간주
      logWarning("1:1 문제 감지 - 원본 UI가 정사각형에 가까움 (비율: \(String(format: "%.2f", originalAspectRatio))) → Aspect Fill로 16:9 변환", category: .performance)
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
      
      logDebug("Aspect Fill 렌더링 완료: \(originalAspectRatio) → \(targetAspectRatio)", category: .performance)
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
    // HaishinKitManager에서 현재 스트리밍 설정 가져오기
    guard let manager = haishinKitManager,
          let settings = manager.getCurrentSettings() else {
      // 기본값: 720p (16:9 비율)
      return CGSize(width: 1280, height: 720)
    }
    
    let streamWidth = settings.videoWidth
    let streamHeight = settings.videoHeight
    
    // 16:9 비율 강제 적용 (유튜브 라이브 표준)
    let aspectRatio: CGFloat = 16.0 / 9.0
    
    // 송출 해상도를 16:9 비율로 수정
    let correctedStreamSize: CGSize
    let currentAspectRatio = CGFloat(streamWidth) / CGFloat(streamHeight)
    
    if abs(currentAspectRatio - aspectRatio) > 0.1 {
      // 비율이 16:9가 아니면 강제로 수정
      let correctedHeight = CGFloat(streamWidth) / aspectRatio
      correctedStreamSize = CGSize(width: streamWidth, height: Int(correctedHeight))
      logInfo("비율수정: \(streamWidth)x\(streamHeight) (비율: \(String(format: "%.2f", currentAspectRatio))) → \(correctedStreamSize) (16:9)", category: .streaming)
    } else {
      correctedStreamSize = CGSize(width: streamWidth, height: streamHeight)
      logDebug("이미 16:9 비율: \(correctedStreamSize)", category: .streaming)
    }
    
    // 16:9 비율 기반 최적 캡처 해상도 계산
    let captureSize: CGSize
    let width = Int(correctedStreamSize.width)
    let height = Int(correctedStreamSize.height)
    
    switch (width, height) {
    case (640...854, 360...480):
      // 480p 계열 → 2배 업스케일
      captureSize = CGSize(width: 1280, height: 720) // 720p로 캡처
      logDebug("16:9 캡처 - 480p계열 송출 → 720p 캡처: \(captureSize)", category: .streaming)
      
    case (1280, 720):
      // 720p → 2배 업스케일
      captureSize = CGSize(width: 2560, height: 1440)
      logDebug("16:9 캡처 - 720p 송출 → 1440p 캡처: \(captureSize)", category: .streaming)
      
    case (1920, 1080):
      // 1080p → 동일 해상도 (안정성 우선)
      captureSize = CGSize(width: 1920, height: 1080)
      logDebug("16:9 캡처 - 1080p 송출 → 1080p 캡처: \(captureSize)", category: .streaming)
      
    default:
      // 사용자 정의 → 16:9 비율로 강제 변환 후 캡처
      let targetWidth = max(width, 1280) // 최소 720p 너비
      let targetHeight = Int(CGFloat(targetWidth) / aspectRatio)
      captureSize = CGSize(width: targetWidth, height: targetHeight)
      logDebug("16:9 캡처 - 사용자정의 → 16:9 강제변환 캡처: \(captureSize)", category: .streaming)
    }
    
    // 16의 배수로 정렬 (VideoCodec 호환성)
    let alignedWidth = ((Int(captureSize.width) + 15) / 16) * 16
    let alignedHeight = ((Int(captureSize.height) + 15) / 16) * 16
    let finalSize = CGSize(width: alignedWidth, height: alignedHeight)
    
    // 최종 16:9 비율 검증
    let finalAspectRatio = CGFloat(alignedWidth) / CGFloat(alignedHeight)
    logDebug("최종검증 - 16배수 정렬: \(captureSize) → \(finalSize)", category: .streaming)
    logDebug("최종검증 - 비율 확인: \(String(format: "%.2f", finalAspectRatio)) (16:9 ≈ 1.78)", category: .streaming)
    
    return finalSize
  }
} 