//
//  CameraScreenCapture.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import Foundation
import HaishinKit
import CoreVideo
import UIKit
import LiveStreamingCore

private final class PixelBufferReference: @unchecked Sendable {
  let pixelBuffer: CVPixelBuffer

  init(_ pixelBuffer: CVPixelBuffer) {
    self.pixelBuffer = pixelBuffer
  }
}

final class ScreenCaptureFrameStore: @unchecked Sendable {
  let processingQueue = DispatchQueue(label: "CameraFrameProcessing", qos: .userInteractive)

  private let lock = NSLock()
  private var _isScreenCapturing = false
  private var _latestCameraFrame: CVPixelBuffer?
  private var _hasReceivedCameraFrame = false
  private var _latestCameraFrameTimestamp: CFTimeInterval = 0
  private var _lastLoggedCameraFrameSize: CGSize = .zero

  var isScreenCapturing: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _isScreenCapturing
  }

  func setIsScreenCapturing(_ value: Bool) {
    lock.lock()
    _isScreenCapturing = value
    lock.unlock()
  }

  var latestCameraFrame: CVPixelBuffer? {
    lock.lock()
    defer { lock.unlock() }
    return _latestCameraFrame
  }

  func setLatestCameraFrame(_ value: CVPixelBuffer?) {
    lock.lock()
    _latestCameraFrame = value
    lock.unlock()
  }

  var hasReceivedCameraFrame: Bool {
    lock.lock()
    defer { lock.unlock() }
    return _hasReceivedCameraFrame
  }

  func setHasReceivedCameraFrame(_ value: Bool) {
    lock.lock()
    _hasReceivedCameraFrame = value
    lock.unlock()
  }

  var latestCameraFrameTimestamp: CFTimeInterval {
    lock.lock()
    defer { lock.unlock() }
    return _latestCameraFrameTimestamp
  }

  func setLatestCameraFrameTimestamp(_ value: CFTimeInterval) {
    lock.lock()
    _latestCameraFrameTimestamp = value
    lock.unlock()
  }

  var lastLoggedCameraFrameSize: CGSize {
    lock.lock()
    defer { lock.unlock() }
    return _lastLoggedCameraFrameSize
  }

  func setLastLoggedCameraFrameSize(_ value: CGSize) {
    lock.lock()
    _lastLoggedCameraFrameSize = value
    lock.unlock()
  }

  func updateLatestFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CFTimeInterval) -> CGSize? {
    let size = CGSize(
      width: CVPixelBufferGetWidth(pixelBuffer),
      height: CVPixelBufferGetHeight(pixelBuffer)
    )

    lock.lock()
    defer { lock.unlock() }

    _latestCameraFrame = pixelBuffer
    _latestCameraFrameTimestamp = timestamp
    _hasReceivedCameraFrame = true

    guard size != _lastLoggedCameraFrameSize else {
      return nil
    }

    _lastLoggedCameraFrameSize = size
    return size
  }
}

final class ScreenCaptureFrameConsumer: NSObject, CameraFrameDelegate, @unchecked Sendable {
  private let frameStore: ScreenCaptureFrameStore

  init(frameStore: ScreenCaptureFrameStore) {
    self.frameStore = frameStore
  }

  nonisolated func didReceiveVideoFrame(
    _ sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard frameStore.isScreenCapturing,
      let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    else {
      return
    }

    let pixelBufferReference = PixelBufferReference(pixelBuffer)

    frameStore.processingQueue.async { [frameStore, pixelBufferReference] in
      guard frameStore.isScreenCapturing else { return }

      guard let copiedPixelBuffer = Self.clonePixelBufferForStreaming(pixelBufferReference.pixelBuffer)
      else {
        logWarning("카메라 프레임 복사 실패 - 전송용 프레임 생략", category: .camera)
        return
      }

      if let size = frameStore.updateLatestFrame(
        copiedPixelBuffer,
        timestamp: CACurrentMediaTime()
      ) {
        logDebug(
          "카메라 프레임 크기 수신: \(Int(size.width))×\(Int(size.height))",
          category: .camera
        )
      }
    }
  }

  private static func clonePixelBufferForStreaming(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]

    var clonedPixelBuffer: CVPixelBuffer?
    let createStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      pixelFormat,
      attrs as CFDictionary,
      &clonedPixelBuffer
    )

    guard createStatus == kCVReturnSuccess, let clonedPixelBuffer else {
      logWarning("카메라 프레임 복사용 버퍼 생성 실패: status=\(createStatus)")
      return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    CVPixelBufferLockBaseAddress(clonedPixelBuffer, [])

    defer {
      CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
      CVPixelBufferUnlockBaseAddress(clonedPixelBuffer, [])
    }

    let sourceIsPlanar = CVPixelBufferIsPlanar(pixelBuffer) == true

    if sourceIsPlanar {
      let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
      for plane in 0..<planeCount {
        guard
          let sourcePlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane),
          let destinationPlane = CVPixelBufferGetBaseAddressOfPlane(clonedPixelBuffer, plane)
        else {
          logWarning("카메라 프레임 플레인 \(plane) 주소를 얻지 못해 복사를 건너뜀")
          continue
        }

        let sourceBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
        let destinationBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(clonedPixelBuffer, plane)
        let rowHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)

        if sourceBytesPerRow == destinationBytesPerRow {
          memcpy(destinationPlane, sourcePlane, sourceBytesPerRow * rowHeight)
          continue
        }

        let copyBytesPerRow = min(sourceBytesPerRow, destinationBytesPerRow)
        for row in 0..<rowHeight {
          let sourcePointer = sourcePlane.advanced(by: row * sourceBytesPerRow)
          let destinationPointer = destinationPlane.advanced(by: row * destinationBytesPerRow)
          memcpy(destinationPointer, sourcePointer, copyBytesPerRow)
        }
      }
    } else if
      let sourceBuffer = CVPixelBufferGetBaseAddress(pixelBuffer),
      let destinationBuffer = CVPixelBufferGetBaseAddress(clonedPixelBuffer)
    {
      let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(clonedPixelBuffer)
      if sourceBytesPerRow == destinationBytesPerRow {
        memcpy(destinationBuffer, sourceBuffer, sourceBytesPerRow * height)
      } else {
        let copyBytesPerRow = min(sourceBytesPerRow, destinationBytesPerRow)
        for row in 0..<height {
          let sourcePointer = sourceBuffer.advanced(by: row * sourceBytesPerRow)
          let destinationPointer = destinationBuffer.advanced(by: row * destinationBytesPerRow)
          memcpy(destinationPointer, sourcePointer, copyBytesPerRow)
        }
      }
    } else {
      logWarning("카메라 프레임 버퍼 주소를 얻지 못해 복사 실패")
      return nil
    }

    return clonedPixelBuffer
  }
}

// MARK: - Screen Capture Extension for CameraPreviewUIView

extension CameraPreviewUIView {

  // MARK: - Screen Capture Properties

  /// 화면 캡처용 디스플레이 링크
  private var screenCaptureDisplayLink: CADisplayLink? {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.screenCaptureDisplayLink) as? CADisplayLink
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.screenCaptureDisplayLink, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// 화면 캡처 상태
  var isScreenCapturing: Bool {
    get {
      screenCaptureFrameStore.isScreenCapturing
    }
    set {
      screenCaptureFrameStore.setIsScreenCapturing(newValue)
    }
  }

  /// 최근 카메라 프레임 (화면 캡처용)
  var latestCameraFrame: CVPixelBuffer? {
    get {
      screenCaptureFrameStore.latestCameraFrame
    }
    set {
      screenCaptureFrameStore.setLatestCameraFrame(newValue)
    }
  }

  /// 카메라 프레임 수신 이력
  var hasReceivedCameraFrame: Bool {
    get {
      screenCaptureFrameStore.hasReceivedCameraFrame
    }
    set {
      screenCaptureFrameStore.setHasReceivedCameraFrame(newValue)
    }
  }

  /// 프레임 처리 큐
  var frameProcessingQueue: DispatchQueue {
    screenCaptureFrameStore.processingQueue
  }

  /// 최근 카메라 프레임 수신 시각(초 단위)
  var latestCameraFrameTimestamp: CFTimeInterval {
    get {
      screenCaptureFrameStore.latestCameraFrameTimestamp
    }
    set {
      screenCaptureFrameStore.setLatestCameraFrameTimestamp(newValue)
    }
  }

  /// 카메라 프레임 미수신 경고 마지막 타임스탬프
  var lastCameraFrameWarningTime: CFTimeInterval {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.lastCameraFrameWarningTime) as? CFTimeInterval ?? 0
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.lastCameraFrameWarningTime, newValue,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// 화면 캡처 시작 시각
  var screenCaptureStartTime: CFTimeInterval {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.screenCaptureStartTime) as? CFTimeInterval ?? 0
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.screenCaptureStartTime, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// 마지막 로그된 카메라 프레임 크기
  var lastLoggedCameraFrameSize: CGSize {
    get {
      screenCaptureFrameStore.lastLoggedCameraFrameSize
    }
    set {
      screenCaptureFrameStore.setLastLoggedCameraFrameSize(newValue)
    }
  }

  /// 프레임 카운터 (통계 출력용)
  var frameCounter: Int {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.frameCounter) as? Int ?? 0
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.frameCounter, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// 렌더링 중복 실행 방지 플래그 (백프레셔)
  var isFrameRenderInProgress: Bool {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.isFrameRenderInProgress) as? Bool ?? false
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.isFrameRenderInProgress, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// 전송 중복 실행 방지 플래그 (백프레셔)
  var isFrameSendInProgress: Bool {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.isFrameSendInProgress) as? Bool ?? false
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.isFrameSendInProgress, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// 프레임 드랍 로그 스팸 방지 타임스탬프
  var lastFrameDropLogTime: CFTimeInterval {
    get {
      return objc_getAssociatedObject(self, &AssociatedKeys.lastFrameDropLogTime) as? CFTimeInterval ?? 0
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.lastFrameDropLogTime, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// 마지막 display link tick 시각
  var lastDisplayLinkTickTimestamp: CFTimeInterval {
    get {
      objc_getAssociatedObject(self, &AssociatedKeys.lastDisplayLinkTickTimestamp) as? CFTimeInterval ?? 0
    }
    set {
      objc_setAssociatedObject(
        self,
        &AssociatedKeys.lastDisplayLinkTickTimestamp,
        newValue,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
      )
    }
  }

  /// 마지막 실제 캡처 시각
  var lastCaptureDispatchTimestamp: CFTimeInterval {
    get {
      objc_getAssociatedObject(self, &AssociatedKeys.lastCaptureDispatchTimestamp) as? CFTimeInterval ?? 0
    }
    set {
      objc_setAssociatedObject(
        self,
        &AssociatedKeys.lastCaptureDispatchTimestamp,
        newValue,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
      )
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
  func startScreenCapture(_ notification: Notification? = nil) {
    guard !isScreenCapturing else {
      logWarning("이미 화면 캡처가 진행 중입니다", category: .streaming)
      return
    }

    if let notification = notification {
      configureStreamingTargetFromNotification(notification)
    }

    if streamingTargetSize == nil, let manager = haishinKitManager, let settings = manager.getCurrentSettings() {
      setStreamingTargetSize(CGSize(width: settings.videoWidth, height: settings.videoHeight))
    }

    if streamingTargetSize == nil {
      logWarning("해상도 캐시가 비어있어 기본값 fallback이 동작하지 않았습니다", category: .streaming)
    } else if let target = streamingTargetSize {
      logInfo(
        "실행 전 최종 캡처 타겟: \(Int(target.width))×\(Int(target.height))",
        category: .streaming)
    }

    screenCaptureStartTime = CACurrentMediaTime()
    hasReceivedCameraFrame = false
    latestCameraFrame = nil
    latestCameraFrameTimestamp = 0
    lastCameraFrameWarningTime = 0
    lastLoggedCameraFrameSize = .zero

    // 화면 캡처 시작 전 카메라 파이프라인 정합성 확보
    if let session = captureSession {
      setupVideoFrameCapture(with: session)
    }

    // 내부 상태 초기화
    frameCounter = 0
    isFrameRenderInProgress = false
    isFrameSendInProgress = false
    lastFrameDropLogTime = 0
    lastDisplayLinkTickTimestamp = 0
    lastCaptureDispatchTimestamp = 0
    frameProcessingQueue.async { [weak self] in
      self?.latestCameraFrame = nil
      self?.latestCameraFrameTimestamp = 0
      self?.hasReceivedCameraFrame = false
    }

    isScreenCapturing = true
    logInfo("화면 캡처 송출 시작", category: .streaming)
    if let target = streamingTargetSize {
      logInfo(
        "현재 세션의 캡처 목표 해상도: \(Int(target.width))×\(Int(target.height))", category: .streaming)
    }

    let targetFrameRate = resolvedCaptureFrameRateForCurrentResolution()
    let displayLink = CADisplayLink(target: self, selector: #selector(handleScreenCaptureDisplayLink(_:)))
    if #available(iOS 15.0, *) {
      displayLink.preferredFrameRateRange = CAFrameRateRange(
        minimum: Float(targetFrameRate),
        maximum: Float(max(targetFrameRate, 60)),
        preferred: Float(targetFrameRate)
      )
    } else {
      displayLink.preferredFramesPerSecond = targetFrameRate
    }
    displayLink.add(to: .main, forMode: .common)
    screenCaptureDisplayLink = displayLink
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
    screenCaptureDisplayLink?.invalidate()
    screenCaptureDisplayLink = nil
    isFrameRenderInProgress = false
    isFrameSendInProgress = false
    lastFrameDropLogTime = 0
    lastDisplayLinkTickTimestamp = 0
    lastCaptureDispatchTimestamp = 0

    // 메모리 정리: 최근 캡처된 카메라 프레임 제거
    frameProcessingQueue.async { [weak self] in
      self?.latestCameraFrame = nil
      self?.latestCameraFrameTimestamp = 0
      self?.hasReceivedCameraFrame = false
      self?.screenCaptureStartTime = 0
      self?.lastCameraFrameWarningTime = 0
    }
    removeVideoFrameCapture()

    clearStreamingTargetSize()

    logInfo("화면 캡처 송출 중지 및 리소스 정리 완료", category: .streaming)
  }

  @objc private func handleScreenCaptureDisplayLink(_ displayLink: CADisplayLink) {
    guard isScreenCapturing else { return }

    let currentTimestamp = displayLink.timestamp
    let targetInterval = getCaptureIntervalForResolution()

    let mainThreadHitch: Bool
    if lastDisplayLinkTickTimestamp > 0 {
      let tickDelta = currentTimestamp - lastDisplayLinkTickTimestamp
      mainThreadHitch = tickDelta > max(targetInterval * 1.75, 0.05)
    } else {
      mainThreadHitch = false
    }
    lastDisplayLinkTickTimestamp = currentTimestamp

    if lastCaptureDispatchTimestamp > 0 {
      let elapsedSinceLastCapture = currentTimestamp - lastCaptureDispatchTimestamp
      if elapsedSinceLastCapture + 0.0005 < targetInterval {
        return
      }
    }

    let captureCadenceMs: Double?
    if lastCaptureDispatchTimestamp > 0 {
      captureCadenceMs = (currentTimestamp - lastCaptureDispatchTimestamp) * 1000
    } else {
      captureCadenceMs = nil
    }
    lastCaptureDispatchTimestamp = currentTimestamp

    captureCurrentFrame(
      captureCadenceMs: captureCadenceMs,
      mainThreadHitch: mainThreadHitch,
      presentationTimestamp: currentTimestamp
    )
  }

  /// 현재 프레임 캡처 및 HaishinKit 전송
  ///
  /// 이 메서드는 30fps 타이머에 의해 호출되며, 다음 단계를 수행합니다:
  /// 1. 메인 스레드에서 UI 렌더링 수행
  /// 2. 카메라 프레임과 UI를 합성하여 최종 이미지 생성
  /// 3. UIImage를 CVPixelBuffer로 변환
  /// 4. HaishinKit을 통해 스트리밍 서버에 전송
  private func captureCurrentFrame(
    captureCadenceMs: Double?,
    mainThreadHitch: Bool,
    presentationTimestamp: CFTimeInterval
  ) {
    // 화면 캡처 상태 재확인 (타이머 지연으로 인한 중복 실행 방지)
    guard isScreenCapturing else { return }

    // 렌더링이 이전 프레임 처리 중이면 이번 프레임은 드랍
    guard !isFrameRenderInProgress else {
      logFrameDropIfNeeded(reason: "렌더링 작업이 밀려 현재 프레임을 드랍합니다.")
      haishinKitManager?.recordScreenCaptureDrop(reason: .renderBackpressure)
      return
    }

    // 전송이 아직 완료되지 않았다면 큐 적체를 피하기 위해 현재 프레임 드랍
    guard !isFrameSendInProgress else {
      logFrameDropIfNeeded(reason: "프레임 전송이 밀려 현재 프레임을 드랍합니다.")
      haishinKitManager?.recordScreenCaptureDrop(reason: .sendBackpressure)
      return
    }

    let streamingSize = getOptimalCaptureSize()
    let overlaySnapshot = makeStreamingOverlaySnapshot(streamingSize: streamingSize)
    let cameraFrame = latestCameraFrame
    let cameraFrameAgeMs: Double? =
      hasReceivedCameraFrame && latestCameraFrameTimestamp > 0
      ? max(0, (CACurrentMediaTime() - latestCameraFrameTimestamp) * 1000)
      : nil

    isFrameRenderInProgress = true
    frameProcessingQueue.async { [weak self] in
      guard let self else { return }

      let compositionStart = CACurrentMediaTime()
      let pixelBuffer = self.composeStreamingPixelBuffer(
        cameraFrame: cameraFrame,
        overlaySnapshot: overlaySnapshot,
        streamingSize: streamingSize
      )
      let compositionTimeMs = (CACurrentMediaTime() - compositionStart) * 1000

      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isFrameRenderInProgress = false

        if pixelBuffer == nil {
          self.logFrameDropIfNeeded(reason: "합성 결과가 없어 현재 프레임을 드랍합니다.")
          self.haishinKitManager?.recordScreenCaptureDrop(reason: .renderBackpressure)
          return
        }

        self.haishinKitManager?.reportScreenCaptureLoopMetrics(
          captureCadenceMs: captureCadenceMs,
          cameraFrameAgeMs: cameraFrameAgeMs,
          compositionTimeMs: compositionTimeMs,
          mainThreadHitch: mainThreadHitch
        )
        self.sendFrameToHaishinKit(
          pixelBuffer!,
          frameRate: self.resolvedCaptureFrameRateForCurrentResolution(),
          compositionTimeMs: compositionTimeMs,
          cameraFrameAgeMs: cameraFrameAgeMs,
          presentationTimestamp: presentationTimestamp
        )
      }
    }
  }

  /// 프레임 드랍 상태 로깅 (스팸 방지)
  private func logFrameDropIfNeeded(reason: String) {
    let now = CACurrentMediaTime()
    guard now - lastFrameDropLogTime >= 1.0 else { return }
    lastFrameDropLogTime = now
    logWarning(reason, category: .performance)
  }

  /// 프레임 전송 타이밍에 대한 중복 실행 방지 로직
  private func performFrameSendWithBackpressure(
    manager: HaishinKitManager,
    pixelBuffer: CVPixelBuffer,
    frameRate: Int,
    compositionTimeMs: Double?,
    cameraFrameAgeMs: Double?,
    presentationTimestamp: CFTimeInterval
  ) {
    guard !isFrameSendInProgress else {
      logFrameDropIfNeeded(reason: "프레임 전송이 밀려 현재 프레임을 드랍합니다.")
      manager.recordScreenCaptureDrop(reason: .sendBackpressure)
      return
    }

    isFrameSendInProgress = true
    let presentationTime = CMTime(seconds: presentationTimestamp, preferredTimescale: 1_000_000_000)
    Task { @MainActor [weak self] in
      _ = await manager.enqueueManualFrame(
        pixelBuffer,
        presentationTime: presentationTime,
        frameRate: frameRate,
        compositionTimeMs: compositionTimeMs,
        cameraFrameAgeMs: cameraFrameAgeMs
      )
      self?.isFrameSendInProgress = false
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
  /// - 카메라 프레임이 없거나 지연된 경우 UI-only 프레임으로 대체해 블랙 화면 회피
  ///
  /// - Returns: 송출 해상도에 따라 최적화된 고품질 이미지
  private func renderToImageForStreaming() -> UIImage? {
    // HaishinKitManager에서 현재 스트리밍 설정 가져오기
    let streamingSize = getOptimalCaptureSize()

    // 카메라 프레임이 있으면 우선 카메라 합성 사용
    if let cameraFrame = latestCameraFrame {
      if hasFreshCameraFrame() {
        return renderCameraFrameWithUIForStreaming(
          cameraFrame: cameraFrame, streamingSize: streamingSize)
      }

      // 최신 프레임이 약간 지연되더라도 기존 프레임을 사용해 블랙 프레임을 회피
      logCameraFrameUnavailable(isStale: true)
      return renderCameraFrameWithUIForStreaming(
        cameraFrame: cameraFrame, streamingSize: streamingSize)
    } else {
      logCameraFrameUnavailable(isStale: false)
      return renderUIOnlyForStreaming(streamingSize: streamingSize)
    }
  }

  /// 카메라 프레임 최신성 확인
  ///
  /// 오래된 프레임도 송출은 하되, 상태 추적용으로 최신성만 판단합니다.
  ///
  /// - Returns: 최신 타임스탬프 기준으로 최근 프레임인지 여부
  private func hasFreshCameraFrame() -> Bool {
    guard hasReceivedCameraFrame else { return false }
    let now = CACurrentMediaTime()
    let maxAcceptedCameraFrameAge: TimeInterval = 1.0
    return (now - latestCameraFrameTimestamp) <= maxAcceptedCameraFrameAge
  }

  /// 카메라 프레임 수신 상태 로깅 (스팸 방지)
  private func logCameraFrameUnavailable(isStale: Bool) {
    let now = CACurrentMediaTime()
    guard now - lastCameraFrameWarningTime >= 1.0 else { return }
    lastCameraFrameWarningTime = now

    if isStale {
      let stale = now - latestCameraFrameTimestamp
      let staleDisplay = round(stale * 100) / 100
      logWarning("카메라 프레임 수신 지연: 최신 프레임 경과 \(staleDisplay)초")
    } else {
      logWarning("카메라 프레임을 아직 받지 못해 UI-only fallback으로 송출합니다.")
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
  private func sendFrameToHaishinKit(
    _ pixelBuffer: CVPixelBuffer,
    frameRate: Int,
    compositionTimeMs: Double?,
    cameraFrameAgeMs: Double?,
    presentationTimestamp: CFTimeInterval
  ) {
    // HaishinKitManager를 통한 실제 프레임 전송
    if let manager = haishinKitManager {
      performFrameSendWithBackpressure(
        manager: manager,
        pixelBuffer: pixelBuffer,
        frameRate: frameRate,
        compositionTimeMs: compositionTimeMs,
        cameraFrameAgeMs: cameraFrameAgeMs,
        presentationTimestamp: presentationTimestamp
      )

      // 성능 모니터링: 10초마다 전송 통계 출력 (로그 부하 완화)
      if frameCounter % 300 == 0 {
        let stats = manager.getScreenCaptureStats()
        let successRate =
          stats.frameCount > 0 ? (Double(stats.successCount) / Double(stats.frameCount)) * 100 : 0
        logInfo(
          """
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

  // 화면 캡처 성능 테스트 메서드가 제거되었습니다.
  // 프로덕션 환경에서 불필요한 테스트 기능을 정리했습니다.

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

    logDebug(
      "이중캡처 - 송출용: \(streamingImage?.size ?? CGSize.zero), 단말용: \(displayImage?.size ?? CGSize.zero)",
      category: .performance)

    return (streamingImage, displayImage)
  }

  /// 단말 화면 캡처 저장 (사진 앱에 저장)
  ///
  /// 사용자가 현재 화면을 사진으로 저장할 때 사용
  public func saveDisplayCapture(completion: @escaping (Bool, Error?) -> Void) {
    guard let displayImage = renderToImageForDisplay() else {
      completion(
        false,
        NSError(
          domain: "CameraPreview", code: 1,
          userInfo: [
            NSLocalizedDescriptionKey: NSLocalizedString(
              "camera_unavailable", comment: "카메라를 사용할 수 없습니다")
          ]))
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

  /// 해상도별 최적 캡처 간격 계산 (720p 끊김 개선)
  private func getCaptureIntervalForResolution() -> TimeInterval {
    let resolved = resolveStreamingSizeForDiagnostics()
    let resolutionClass = StreamResolutionDescriptor(
      width: resolved.width,
      height: resolved.height
    ).resolutionClass
    let clampedFrameRate = resolvedCaptureFrameRateForCurrentResolution()

    switch resolutionClass {
    case .p720:
      logInfo("720p 특화 캡처: \(clampedFrameRate)fps 적용", category: .streaming)
      return 1.0 / Double(clampedFrameRate)

    case .p1080:
      // 1080p에서도 설정 FPS를 우선 적용해 스톱모션 체감 완화
      let optimizedFrameRate = clampedFrameRate
      logInfo("1080p 특화 캡처: \(optimizedFrameRate)fps 적용", category: .streaming)
      return 1.0 / Double(optimizedFrameRate)

    case .p480, .p4k, .custom:
      // 480p: 설정값 기반 처리
      return 1.0 / Double(clampedFrameRate)
    }
  }

  private func maxSupportedCaptureFrameRate(width: Int, height: Int) -> Int {
    switch StreamResolutionDescriptor(width: width, height: height).resolutionClass {
    case .p720:
      return 60
    case .p480, .p1080, .p4k, .custom:
      return 30
    }
  }

  private func resolvedCaptureFrameRateForCurrentResolution() -> Int {
    let resolved = resolveStreamingSizeForDiagnostics()
    return min(
      max(resolveStreamingFrameRateForDiagnostics(), 15),
      maxSupportedCaptureFrameRate(width: resolved.width, height: resolved.height)
    )
  }

  /// 스트리밍 상태/설정 기반 캡처 FPS 조회
  private func resolveStreamingFrameRateForDiagnostics() -> Int {
    if let target = streamingTargetSize,
      let manager = haishinKitManager,
      let settings = manager.getCurrentSettings(),
      settings.videoWidth == Int(target.width),
      settings.videoHeight == Int(target.height),
      settings.frameRate > 0
    {
      return settings.frameRate
    }

    if let manager = haishinKitManager,
       let settings = manager.getCurrentSettings(),
       settings.frameRate > 0
    {
      return settings.frameRate
    }

    return 30
  }

  /// 스트리밍 해상도 진단용 해상도 해석
  private func resolveStreamingSizeForDiagnostics() -> (width: Int, height: Int) {
    if let target = streamingTargetSize {
      return (Int(target.width), Int(target.height))
    }

    if let manager = haishinKitManager, let settings = manager.getCurrentSettings() {
      return (settings.videoWidth, settings.videoHeight)
    }

    logWarning("해상도 해석 실패: fallback 1280×720")
    return (1280, 720)
  }

  /// 화면 캡처 시작 notification에서 전달한 해상도 반영
  private func configureStreamingTargetFromNotification(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
          let width = userInfo["videoWidth"] as? Int,
          let height = userInfo["videoHeight"] as? Int
    else {
      logWarning("화면 캡처 시작 알림에 해상도 정보가 없어 manager/캐시로 판단")
      return
    }
    guard width > 0, height > 0 else {
      logWarning(
        "화면 캡처 시작 알림의 해상도 값이 유효하지 않습니다: \(width)×\(height)",
        category: .streaming)
      return
    }

    setStreamingTargetSize(CGSize(width: width, height: height))
  }
  /// 화면 캡처 시작 직전 전달받은 목표 해상도 저장
  ///
  /// 해상도 저장 위치(캐시)로 인해 매니저 준비 시점과 무관하게
  /// 1080p 선택 상태를 유지할 수 있습니다.
  var streamingTargetSize: CGSize? {
    get {
      guard let value = objc_getAssociatedObject(self, &AssociatedKeys.streamingTargetSize) as? NSValue else {
        return nil
      }
      return value.cgSizeValue
    }
    set {
      if let size = newValue {
        objc_setAssociatedObject(
          self, &AssociatedKeys.streamingTargetSize, NSValue(cgSize: size),
          .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      } else {
        objc_setAssociatedObject(
          self, &AssociatedKeys.streamingTargetSize, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      }
    }
  }

  /// 화면 캡처 타겟 해상도 저장
  func setStreamingTargetSize(_ size: CGSize) {
    streamingTargetSize = size
    logInfo("화면 캡처 목표 해상도 캐시: \(Int(size.width))×\(Int(size.height))", category: .streaming)
  }

  /// 화면 캡처 타겟 해상도 캐시 삭제
  func clearStreamingTargetSize() {
    streamingTargetSize = nil
    logInfo("화면 캡처 목표 해상도 캐시 삭제", category: .streaming)
  }
}

// MARK: - Associated Keys for Runtime Properties

private struct AssociatedKeys {
  static var screenCaptureDisplayLink: UInt8 = 0
  static var frameCounter: UInt8 = 0
  static var isFrameRenderInProgress: UInt8 = 0
  static var isFrameSendInProgress: UInt8 = 0
  static var lastFrameDropLogTime: UInt8 = 0
  static var lastDisplayLinkTickTimestamp: UInt8 = 0
  static var lastCaptureDispatchTimestamp: UInt8 = 0
  static var streamingTargetSize: UInt8 = 0
  static var lastCameraFrameWarningTime: UInt8 = 0
  static var screenCaptureStartTime: UInt8 = 0
}
