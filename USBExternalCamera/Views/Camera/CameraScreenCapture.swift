//
//  CameraScreenCapture.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import HaishinKit
import SwiftUI
import UIKit
import Foundation

// MARK: - Screen Capture Extension for CameraPreviewUIView

extension CameraPreviewUIView {
  
  // MARK: - Screen Capture Properties
  
  /// 화면 캡처용 타이머
  private var screenCaptureTimer: Timer? {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.screenCaptureTimer) as? Timer
    }
    set {
      objc_setAssociatedObject(self, &AssociatedKeys.screenCaptureTimer, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// 화면 캡처 상태
  var isScreenCapturing: Bool {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.isScreenCapturing) as? Bool ?? false
    }
    set {
      objc_setAssociatedObject(self, &AssociatedKeys.isScreenCapturing, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
  
  /// 최근 카메라 프레임 (화면 캡처용)
  var latestCameraFrame: CVPixelBuffer? {
    get {
      let object = objc_getAssociatedObject(self, &AssociatedKeys.latestCameraFrame)
      return object.map { $0 as! CVPixelBuffer }
    }
    set {
      objc_setAssociatedObject(self, &AssociatedKeys.latestCameraFrame, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }
  
  /// 프레임 처리 큐
  var frameProcessingQueue: DispatchQueue {
    if let queue = objc_getAssociatedObject(self, &AssociatedKeys.frameProcessingQueue) as? DispatchQueue {
      return queue
    }
    let queue = DispatchQueue(label: "CameraFrameProcessing", qos: .userInteractive)
    objc_setAssociatedObject(self, &AssociatedKeys.frameProcessingQueue, queue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return queue
  }
  
  /// 프레임 카운터 (통계 출력용)
  var frameCounter: Int {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.frameCounter) as? Int ?? 0
    }
    set {
      objc_setAssociatedObject(self, &AssociatedKeys.frameCounter, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  // MARK: - Screen Capture for Streaming

  /// CameraPreviewUIView의 화면 캡처 송출 기능
  /// 
  /// 이 기능은 다음과 같은 과정으로 동작합니다:
  /// 1. 실시간 카메라 프레임을 CVPixelBuffer로 캡처
  /// 2. UI 오버레이(버튼, 라벨, 워터마크 등)를 별도로 렌더링
  /// 3. 카메라 프레임과 UI를 합성하여 최종 이미지 생성
  /// 4. 30fps로 HaishinKit을 통해 스트리밍 서버에 전송
  ///
  /// **주의사항:**
  /// - 카메라 프레임이 없을 경우 UI만 캡처됩니다
  /// - AVCaptureVideoPreviewLayer는 하드웨어 가속 레이어이므로 직접 캡처가 불가능합니다
  /// - 따라서 AVCaptureVideoDataOutput에서 받은 실제 카메라 프레임을 사용합니다

  /// 화면 캡처 송출 시작
  /// 
  /// 30fps 타이머를 시작하여 지속적으로 화면을 캡처하고 스트리밍합니다.
  /// 카메라 프레임과 UI를 합성한 완전한 화면이 송출됩니다.
  func startScreenCapture() {
    guard !isScreenCapturing else { 
      logWarning("이미 화면 캡처가 진행 중입니다", category: .streaming)
      return 
    }

    isScreenCapturing = true
    logInfo("화면 캡처 송출 시작", category: .streaming)

    // **성능 최적화**: 30fps → 25fps로 낮춰서 CPU 부하 감소
    // 25fps는 여전히 부드러운 스트리밍을 제공하면서 시스템 부하를 줄임
    screenCaptureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 25.0, repeats: true) {
      [weak self] _ in
      self?.captureCurrentFrame()
    }
  }
  
  /// 화면 캡처 송출 중지
  /// 
  /// 타이머를 중지하고 캡처된 프레임 데이터를 정리합니다.
  func stopScreenCapture() {
    guard isScreenCapturing else { 
      logWarning("화면 캡처가 실행 중이지 않습니다", category: .streaming)
      return 
    }

    isScreenCapturing = false
    screenCaptureTimer?.invalidate()
    screenCaptureTimer = nil
    
    // 메모리 정리: 최근 캡처된 카메라 프레임 제거
    frameProcessingQueue.async { [weak self] in
      self?.latestCameraFrame = nil
    }
    
    logInfo("화면 캡처 송출 중지 및 리소스 정리 완료", category: .streaming)
  }

  /// 현재 프레임 캡처 및 HaishinKit 전송
  /// 
  /// 이 메서드는 30fps 타이머에 의해 호출되며, 다음 단계를 수행합니다:
  /// 1. 메인 스레드에서 UI 렌더링 수행
  /// 2. 카메라 프레임과 UI를 합성하여 최종 이미지 생성
  /// 3. UIImage를 CVPixelBuffer로 변환
  /// 4. HaishinKit을 통해 스트리밍 서버에 전송
  private func captureCurrentFrame() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }

      // 화면 캡처 상태 재확인 (타이머 지연으로 인한 중복 실행 방지)
      guard self.isScreenCapturing else { return }

      // Step 1: 현재 화면을 이미지로 렌더링 (카메라 프레임 + UI 합성)
      guard let capturedImage = self.renderToImage() else {
        return
      }

      // Step 2: UIImage를 CVPixelBuffer로 변환 (HaishinKit 호환 포맷)
      guard let pixelBuffer = capturedImage.toCVPixelBuffer() else {
        return
      }

      // Step 3: HaishinKit을 통해 스트리밍 서버에 전송
      self.sendFrameToHaishinKit(pixelBuffer)
    }
  }

  /// UIView를 UIImage로 렌더링 (카메라 프레임 + UI 합성)
  /// 
  /// 이 메서드는 화면 캡처의 핵심 로직입니다:
  /// - 카메라 프레임이 있으면: 카메라 영상 + UI 오버레이 합성
  /// - 카메라 프레임이 없으면: UI만 캡처 (기본 레이어 렌더링)
  ///
  /// **기술적 배경:**
  /// AVCaptureVideoPreviewLayer는 하드웨어 가속을 사용하므로 
  /// 일반적인 layer.render() 방식으로는 캡처되지 않습니다.
  /// 따라서 AVCaptureVideoDataOutput에서 받은 실제 프레임을 사용합니다.
  ///
  /// - Returns: 캡처된 최종 이미지 (카메라 + UI 합성) 또는 nil
  private func renderToImage() -> UIImage? {
    // 송출용 고해상도 렌더링 사용 (해상도 문제 해결)
    return renderToImageForStreaming()
  }
  
  /// 송출용 고해상도 UI 렌더링 (해상도 문제 해결)
  /// 
  /// **개선된 전략:**
  /// - 480p 송출 → 약 1000p(1712x960) 캡처
  /// - 720p 송출 → 약 1400p(2560x1440) 캡처  
  /// - 1080p 송출 → 동일 해상도(1920x1080) 캡처 (안정성 우선)
  /// - 송출 해상도보다 2배 정도 높은 해상도로 캡처하여 고품질 유지
  /// 
  /// - Returns: 송출 해상도에 따라 최적화된 고품질 이미지
  private func renderToImageForStreaming() -> UIImage? {
    // HaishinKitManager에서 현재 스트리밍 설정 가져오기
    let streamingSize = getOptimalCaptureSize()
    
    logDebug("송출용 UI 렌더링 시작: \(streamingSize)", category: .performance)
    
    // 최근 카메라 프레임이 있는지 확인
    if let cameraFrame = latestCameraFrame {
      return renderCameraFrameWithUIForStreaming(cameraFrame: cameraFrame, streamingSize: streamingSize)
    } else {
      logDebug("UI만 캡처 모드 (고해상도)", category: .performance)
      return renderUIOnlyForStreaming(streamingSize: streamingSize)
    }
  }
  
  /// 단말 표시용 일반 해상도 렌더링 (기존 방식 유지)
  /// 
  /// 사용자가 iPad에서 보는 화면용으로 기존 크기 유지
  /// - Returns: 단말 화면 크기의 이미지
  private func renderToImageForDisplay() -> UIImage? {
    let size = bounds.size
    guard size.width > 0 && size.height > 0 else { 
      logError("유효하지 않은 뷰 크기: \(size)", category: .performance)
      return nil 
    }
    
    logDebug("표시용 UI 렌더링: \(size)", category: .performance)
    
    // 최근 카메라 프레임이 있는지 확인
    if let cameraFrame = latestCameraFrame {
      return renderCameraFrameWithUI(cameraFrame: cameraFrame, viewSize: size)
    } else {
      logDebug("UI만 캡처 모드", category: .performance)
      let renderer = UIGraphicsImageRenderer(bounds: bounds)
      return renderer.image { context in
        layer.render(in: context.cgContext)
      }
    }
  }
  
  /// CVPixelBuffer를 HaishinKit에 전달하여 스트리밍
  /// 
  /// 캡처된 프레임을 HaishinKit의 수동 프레임 전송 기능을 통해
  /// 스트리밍 서버로 전송합니다.
  ///
  /// **성능 모니터링:**
  /// - 5초마다 전송 통계를 출력합니다
  /// - 성공/실패 카운트와 현재 FPS를 확인할 수 있습니다
  ///
  /// - Parameter pixelBuffer: 전송할 프레임 데이터
  private func sendFrameToHaishinKit(_ pixelBuffer: CVPixelBuffer) {
    // HaishinKitManager를 통한 실제 프레임 전송
    if let manager = haishinKitManager {
      Task {
        await manager.sendManualFrame(pixelBuffer)
      }

      // 성능 모니터링: 5초마다 전송 통계 출력 (25fps 기준)
      if frameCounter % 125 == 0 { // 25fps 기준 5초마다 = 125프레임마다
        let stats = manager.getScreenCaptureStats()
        let successRate = stats.frameCount > 0 ? (Double(stats.successCount) / Double(stats.frameCount)) * 100 : 0
        logInfo("""
        화면캡처 통계 
        - 현재 FPS: \(String(format: "%.1f", stats.currentFPS))
        - 성공 전송: \(stats.successCount)프레임
        - 실패 전송: \(stats.failureCount)프레임
        - 성공률: \(String(format: "%.1f", successRate))%
        - 총 처리: \(stats.frameCount)프레임
        """, category: .performance)
      }
      frameCounter += 1
    } else {
      logWarning("HaishinKitManager 없음 - 프레임 전달 불가", category: .streaming)
    }
  }

  /// 화면 캡처 상태와 통계 확인 (공개 메서드)
  public func getScreenCaptureStatus() -> (isCapturing: Bool, stats: String?) {
    let stats = haishinKitManager?.getScreenCaptureStats()
    return (isScreenCapturing, stats?.summary)
  }

  /// 화면 캡처 성능 테스트
  public func testScreenCapturePerformance() {
    guard let manager = haishinKitManager else {
      logError("HaishinKitManager가 없음", category: .streaming)
      return
    }

    logInfo("화면 캡처 성능 테스트 시작...", category: .performance)
    manager.resetScreenCaptureStats()

    // 10프레임 연속 전송 테스트
    for i in 1...10 {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) { [weak self] in
        if let image = self?.renderToImage(),
          let pixelBuffer = image.toCVPixelBuffer()
        {
          Task {
            await manager.sendManualFrame(pixelBuffer)
          }

          if i == 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
              let stats = manager.getScreenCaptureStats()
              logInfo("테스트 완료:", category: .performance)
              logInfo(stats.summary, category: .performance)
            }
          }
        }
      }
    }
  }
  
  /// 단말 표시용 화면 캡처 (사용자 화면에 표시용)
  /// 
  /// 송출과 별도로 사용자가 iPad에서 볼 수 있는 화면 캡처 기능
  /// - Returns: 단말 화면 크기의 이미지
  public func captureForDisplay() -> UIImage? {
    return renderToImageForDisplay()
  }
  
  /// 송출용과 단말용 이미지 동시 생성
  /// 
  /// - Returns: (송출용: 1920x1080, 단말용: 986x865) 튜플
  public func captureForBothPurposes() -> (streaming: UIImage?, display: UIImage?) {
    let streamingImage = renderToImageForStreaming()
    let displayImage = renderToImageForDisplay()
    
    logDebug("이중캡처 - 송출용: \(streamingImage?.size ?? CGSize.zero), 단말용: \(displayImage?.size ?? CGSize.zero)", category: .performance)
    
    return (streamingImage, displayImage)
  }
  
  /// 단말 화면 캡처 저장 (사진 앱에 저장)
  /// 
  /// 사용자가 현재 화면을 사진으로 저장할 때 사용
  public func saveDisplayCapture(completion: @escaping (Bool, Error?) -> Void) {
    guard let displayImage = renderToImageForDisplay() else {
      completion(false, NSError(domain: "CameraPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("camera_unavailable", comment: "카메라를 사용할 수 없습니다")]))
      return
    }
    
    UIImageWriteToSavedPhotosAlbum(displayImage, nil, nil, nil)
    logInfo("화면 캡처 사진 앱에 저장 완료: \(displayImage.size)", category: .general)
    completion(true, nil)
  }

  /// 화면 캡처 상태 확인
  var isCapturingScreen: Bool {
    return isScreenCapturing
  }
}

// MARK: - Screen Capture Video Frame Processing Extension

extension CameraPreviewUIView {
  
  /// 화면 캡처 모드를 위한 비디오 프레임 처리
  func processVideoFrameForScreenCapture(_ sampleBuffer: CMSampleBuffer) {
    // 🎬 화면 캡처 모드: 실시간 카메라 프레임 저장
    // UI와 합성하기 위해 최신 프레임을 백그라운드에서 저장
    if isScreenCapturing {
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
        logWarning("CMSampleBuffer에서 pixelBuffer 추출 실패", category: .camera)
        return 
      }
      
      // 백그라운드 큐에서 프레임 저장 (메인 스레드 블록킹 방지)
      frameProcessingQueue.async { [weak self] in
        self?.latestCameraFrame = pixelBuffer
      }
    }
  }
}

// MARK: - Associated Keys for Runtime Properties

private struct AssociatedKeys {
  static var screenCaptureTimer = "screenCaptureTimer"
  static var isScreenCapturing = "isScreenCapturing"
  static var latestCameraFrame = "latestCameraFrame"
  static var frameProcessingQueue = "frameProcessingQueue"
  static var frameCounter = "frameCounter"
} 