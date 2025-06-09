//
//  CameraPreviewUIView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import HaishinKit
import SwiftUI
import UIKit
import Foundation

/// 실제 카메라 미리보기를 담당하는 UIView
final class CameraPreviewUIView: UIView {

  // MARK: - Properties

  /// AVFoundation 카메라 미리보기 레이어
  private var previewLayer: AVCaptureVideoPreviewLayer?

  /// HaishinKit 미리보기 레이어 (스트리밍 중일 때 사용)
  private var hkPreviewLayer: UIView?

  /// 비디오 출력 (통계 목적)
  private var videoOutput: AVCaptureVideoDataOutput?
  private let videoOutputQueue = DispatchQueue(
    label: "CameraPreviewView.VideoOutput", qos: .userInteractive)

  /// 현재 캡처 세션
  var captureSession: AVCaptureSession? {
    didSet {
      // 처음 설정될 때만 프리뷰 레이어 생성
      if oldValue == nil && captureSession != nil {
        logInfo("초기 캡처 세션 설정 - 프리뷰 레이어 생성", category: .camera)
        updatePreviewLayer()
      } else if oldValue !== captureSession {
        logInfo("캡처 세션 변경 감지 - 프리뷰 레이어 업데이트", category: .camera)
        updatePreviewLayer()
      }
    }
  }

  /// HaishinKit 매니저 (스트리밍 상태 확인용)
  var haishinKitManager: HaishinKitManager? {
    didSet {
      updateStreamingStatus()
      setupStatusMonitoring()
    }
  }

  /// 스트리밍 상태
  private var isStreaming: Bool = false {
    didSet {
      updateStreamingStatusView()
    }
  }

  /// 스트리밍 상태 모니터링 타이머
  private var statusMonitorTimer: Timer?

  /// 카메라 컨트롤 오버레이
  private lazy var controlOverlay: CameraControlOverlay = {
    let overlay = CameraControlOverlay()
    overlay.delegate = self
    overlay.translatesAutoresizingMaskIntoConstraints = false
    overlay.backgroundColor = UIColor.clear
    return overlay
  }()

  /// 스트리밍 상태 표시
  private lazy var streamingStatusView: StreamingStatusView = {
    let statusView = StreamingStatusView()
    statusView.translatesAutoresizingMaskIntoConstraints = false
    statusView.isHidden = true
    return statusView
  }()

  // MARK: - Initialization

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  // MARK: - View Setup

  private func setupView() {
    backgroundColor = .black

    // 컨트롤 오버레이만 추가 (StreamingStatusView는 중복되므로 제거)
    addSubview(controlOverlay)

    setupConstraints()
    setupGestureRecognizers()
    setupNotifications()
  }

  private func setupNotifications() {
    // 화면 캡처 제어 notification 구독
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleStartScreenCapture),
      name: NSNotification.Name("startScreenCapture"),
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleStopScreenCapture),
      name: NSNotification.Name("stopScreenCapture"),
      object: nil
    )
  }

  @objc private func handleStartScreenCapture() {
    logDebug("화면 캡처 시작 notification 수신", category: .streaming)
    startScreenCapture()
  }

  @objc private func handleStopScreenCapture() {
    logDebug("화면 캡처 중지 notification 수신", category: .streaming)
    stopScreenCapture()
  }

  private func setupConstraints() {
    NSLayoutConstraint.activate([
      // 컨트롤 오버레이
      controlOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
      controlOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
      controlOverlay.topAnchor.constraint(equalTo: topAnchor),
      controlOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  private func setupGestureRecognizers() {
    // 포커스 탭 제스처
    let focusTapGesture = UITapGestureRecognizer(
      target: self, action: #selector(handleFocusTap(_:)))
    addGestureRecognizer(focusTapGesture)

    // 노출 조절 더블탭 제스처
    let exposureDoubleTapGesture = UITapGestureRecognizer(
      target: self, action: #selector(handleExposureDoubleTap(_:)))
    exposureDoubleTapGesture.numberOfTapsRequired = 2
    addGestureRecognizer(exposureDoubleTapGesture)

    focusTapGesture.require(toFail: exposureDoubleTapGesture)

    // 줌 핀치 제스처
    let zoomPinchGesture = UIPinchGestureRecognizer(
      target: self, action: #selector(handleZoomPinch(_:)))
    addGestureRecognizer(zoomPinchGesture)
  }

  // MARK: - Preview Layer Management

  private func updatePreviewLayer() {
    // 기존 레이어 제거
    previewLayer?.removeFromSuperlayer()
    hkPreviewLayer?.removeFromSuperview()

    guard let session = captureSession else { return }

    // 항상 AVFoundation 프리뷰 사용 (안정성 향상)
    setupAVFoundationPreview(with: session)

    // 스트리밍 중이면 추가 표시
    if isStreaming {
      addStreamingIndicator()
    }
  }

  /// 스트리밍 표시만 추가 (프리뷰 레이어는 건드리지 않음)
  private func addStreamingIndicatorOnly() {
    // 기존 스트리밍 표시 제거
    removeStreamingIndicator()

    logDebug("스트리밍 표시 추가", category: .streaming)

    let streamingOverlay = UIView(frame: bounds)
    streamingOverlay.backgroundColor = UIColor.clear
    streamingOverlay.tag = 9999  // 식별용 태그

    let streamingIndicator = UIView()
    streamingIndicator.backgroundColor = UIColor.red.withAlphaComponent(0.9)
    streamingIndicator.layer.cornerRadius = 12
    streamingIndicator.translatesAutoresizingMaskIntoConstraints = false

    let liveLabel = UILabel()
    liveLabel.text = "🔴 LIVE"
    liveLabel.textColor = .white
    liveLabel.font = UIFont.boldSystemFont(ofSize: 14)
    liveLabel.translatesAutoresizingMaskIntoConstraints = false

    streamingIndicator.addSubview(liveLabel)
    streamingOverlay.addSubview(streamingIndicator)

    NSLayoutConstraint.activate([
      streamingIndicator.topAnchor.constraint(
        equalTo: streamingOverlay.safeAreaLayoutGuide.topAnchor, constant: 20),
      streamingIndicator.leadingAnchor.constraint(
        equalTo: streamingOverlay.leadingAnchor, constant: 20),
      streamingIndicator.widthAnchor.constraint(equalToConstant: 80),
      streamingIndicator.heightAnchor.constraint(equalToConstant: 32),

      liveLabel.centerXAnchor.constraint(equalTo: streamingIndicator.centerXAnchor),
      liveLabel.centerYAnchor.constraint(equalTo: streamingIndicator.centerYAnchor),
    ])

    addSubview(streamingOverlay)
    hkPreviewLayer = streamingOverlay
  }

  /// 스트리밍 표시 제거
  private func removeStreamingIndicator() {
    // 태그로 스트리밍 표시 찾아서 제거
    if let streamingOverlay = subviews.first(where: { $0.tag == 9999 }) {
      streamingOverlay.removeFromSuperview()
      logDebug("스트리밍 표시 제거", category: .streaming)
    }
    hkPreviewLayer = nil
  }

  /// 스트리밍 표시 추가 (레이아웃용)
  private func addStreamingIndicator() {
    addStreamingIndicatorOnly()
  }

  /// 프리뷰 레이어가 활성 상태인지 확인하고 필요시 복구
  private func ensurePreviewLayerActive() {
    guard let session = captureSession else {
      logError("캡처 세션이 없어 프리뷰 보호 불가", category: .camera)
      return
    }

    // 프리뷰 레이어가 없거나 세션이 다르면 복구
    if previewLayer == nil || previewLayer?.session !== session {
      logInfo("프리뷰 레이어 복구 필요 - 재생성", category: .camera)
      setupAVFoundationPreview(with: session)
    } else if let layer = previewLayer {
      // 프리뷰 레이어가 슈퍼레이어에서 제거되었으면 다시 추가
      if layer.superlayer == nil {
        logInfo("프리뷰 레이어 다시 추가", category: .camera)
        self.layer.insertSublayer(layer, at: 0)
      }

      // 프레임 업데이트
      layer.frame = bounds
    }

    logDebug("프리뷰 레이어 보호 완료", category: .camera)
  }

  /// 비디오 프레임 모니터링 설정 (통계 목적)
  private func setupVideoMonitoring(with session: AVCaptureSession) {
    // 기존 비디오 출력 제거
    if let existingOutput = videoOutput {
      session.removeOutput(existingOutput)
    }

    // 새로운 비디오 출력 생성 (통계 목적)
    let newVideoOutput = AVCaptureVideoDataOutput()
    newVideoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

    // 비디오 설정 (가벼운 처리용)
    newVideoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    // 프레임 드롭 허용 (성능 최적화)
    newVideoOutput.alwaysDiscardsLateVideoFrames = true

    // 세션에 추가
    if session.canAddOutput(newVideoOutput) {
      session.addOutput(newVideoOutput)
      videoOutput = newVideoOutput
    } else {
      logError("비디오 프레임 모니터링 설정 실패", category: .camera)
    }
  }

  /// 비디오 프레임 모니터링 해제
  private func removeVideoMonitoring() {
    guard let session = captureSession, let output = videoOutput else { return }

    session.removeOutput(output)
    videoOutput = nil
  }

  /// 스트리밍 상태 업데이트 (개선된 버전)
  private func updateStreamingStatus() {
    guard let manager = haishinKitManager else {
      isStreaming = false
      return
    }

    // 스트리밍 상태와 연결 상태 모두 확인
    let newStreamingState = manager.isStreaming
    let connectionStatus = manager.connectionStatus
    let currentStatus = manager.currentStatus

    if isStreaming != newStreamingState {
      isStreaming = newStreamingState

      // 상태 변화를 로깅
      if isStreaming {
        logInfo("스트리밍 시작됨 - 스트리밍 표시 추가 및 프리뷰 보호", category: .streaming)

        // 스트리밍 표시 추가 및 비디오 모니터링 설정
        DispatchQueue.main.async { [weak self] in
          self?.addStreamingIndicatorOnly()
          // 프리뷰 레이어가 활성 상태인지 확인하고 필요시 복구
          self?.ensurePreviewLayerActive()
          // 비디오 프레임 모니터링 설정 (통계 목적)
          if let session = self?.captureSession {
            self?.setupVideoMonitoring(with: session)
          }
        }
      } else {
        logInfo("스트리밍 종료됨 - 스트리밍 표시 제거", category: .streaming)

        // 스트리밍 표시 제거 및 비디오 모니터링 해제
        DispatchQueue.main.async { [weak self] in
          self?.removeStreamingIndicator()
          // 비디오 프레임 모니터링 해제
          self?.removeVideoMonitoring()
          // 프리뷰 레이어 복구
          self?.ensurePreviewLayerActive()
        }
      }
    }

    // 연결 상태에 따른 상세 UI 업데이트
    DispatchQueue.main.async { [weak self] in
      self?.updateDetailedStreamingStatus(
        isStreaming: newStreamingState,
        connectionStatus: connectionStatus,
        status: currentStatus
      )
    }
  }

  /// 상세 스트리밍 상태 UI 업데이트 (비활성화 - 중복 방지)
  private func updateDetailedStreamingStatus(
    isStreaming: Bool,
    connectionStatus: String,
    status: LiveStreamStatus
  ) {
    // StreamingStatusView 사용하지 않음 (중복 방지)
  }

  /// 스트리밍 상태 표시 뷰 업데이트 (비활성화 - 중복 방지)
  private func updateStreamingStatusView() {
    // StreamingStatusView 사용하지 않음 (중복 방지)
    logDebug("스트리밍 상태 뷰 업데이트 건너뜀 (중복 방지)", category: .streaming)
  }

  /// 스트리밍 상태 모니터링 설정
  private func setupStatusMonitoring() {
    // 기존 타이머 정리
    statusMonitorTimer?.invalidate()

    // 새 타이머 설정 (1초마다 상태 확인)
    statusMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
      [weak self] _ in
      self?.updateStreamingStatus()
    }
  }

  /// 정리 작업
  deinit {
    statusMonitorTimer?.invalidate()
  }

  /// 프리뷰 레이어 강제 새로고침 (스트리밍 상태 변화 시)
  func refreshPreviewLayer() {
    logInfo("프리뷰 레이어 새로고침 시작 (스트리밍: \(isStreaming))", category: .camera)

    guard let session = captureSession else {
      logError("캡처 세션이 없어 새로고침 실패", category: .camera)
      return
    }

    // 기존 프리뷰 레이어 완전 제거
    previewLayer?.removeFromSuperlayer()
    previewLayer = nil
    hkPreviewLayer?.removeFromSuperview()
    hkPreviewLayer = nil

    // 잠시 대기 후 상태에 맞는 프리뷰 레이어 생성
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      guard let self = self else { return }

      logInfo("AVFoundation 프리뷰 설정", category: .camera)
      self.setupAVFoundationPreview(with: session)

      if self.isStreaming {
        logInfo("스트리밍 표시 추가", category: .streaming)
        self.addStreamingIndicator()
      }

      logInfo("프리뷰 레이어 새로고침 완료", category: .camera)
    }
  }

  private func setupAVFoundationPreview(with session: AVCaptureSession) {
    logInfo("AVFoundation 프리뷰 레이어 설정 중...", category: .camera)

    let newPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
    
    // 16:9 비율 계산 및 적용
    let aspectRatio: CGFloat = 16.0 / 9.0
    let viewBounds = bounds
    
    // 16:9 비율에 맞는 프레임 계산
    let previewFrame: CGRect
    if viewBounds.width / viewBounds.height > aspectRatio {
      // 세로가 기준: 높이에 맞춰서 너비 계산
      let width = viewBounds.height * aspectRatio
      let offsetX = (viewBounds.width - width) / 2
      previewFrame = CGRect(x: offsetX, y: 0, width: width, height: viewBounds.height)
    } else {
      // 가로가 기준: 너비에 맞춰서 높이 계산
      let height = viewBounds.width / aspectRatio
      let offsetY = (viewBounds.height - height) / 2
      previewFrame = CGRect(x: 0, y: offsetY, width: viewBounds.width, height: height)
    }
    
    newPreviewLayer.frame = previewFrame
    
    // 실제 송출 영역과 일치: resizeAspectFill 사용
    // 카메라 이미지가 프레임을 완전히 채우도록 설정
    newPreviewLayer.videoGravity = .resizeAspectFill

    if #available(iOS 17.0, *) {
      newPreviewLayer.connection?.videoRotationAngle = 0
    } else {
      newPreviewLayer.connection?.videoOrientation = .portrait
    }

    layer.insertSublayer(newPreviewLayer, at: 0)
    previewLayer = newPreviewLayer

    logInfo("AVFoundation 프리뷰 레이어 설정 완료", category: .camera)
    logDebug("16:9 비율 프레임: \(previewFrame)", category: .camera)
    logDebug("videoGravity: resizeAspectFill (송출 영역과 일치)", category: .camera)
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    // 프리뷰 레이어 프레임 업데이트 (16:9 비율 유지)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      
      // 16:9 비율 계산
      let aspectRatio: CGFloat = 16.0 / 9.0
      let viewBounds = self.bounds
      
      // 16:9 비율에 맞는 프레임 재계산
      let previewFrame: CGRect
      if viewBounds.width / viewBounds.height > aspectRatio {
        // 세로가 기준: 높이에 맞춰서 너비 계산
        let width = viewBounds.height * aspectRatio
        let offsetX = (viewBounds.width - width) / 2
        previewFrame = CGRect(x: offsetX, y: 0, width: width, height: viewBounds.height)
      } else {
        // 가로가 기준: 너비에 맞춰서 높이 계산
        let height = viewBounds.width / aspectRatio
        let offsetY = (viewBounds.height - height) / 2
        previewFrame = CGRect(x: 0, y: offsetY, width: viewBounds.width, height: height)
      }
      
      // 프리뷰 레이어 프레임 업데이트 (16:9 비율 적용)
      self.previewLayer?.frame = previewFrame
      self.hkPreviewLayer?.frame = previewFrame

      // 레이어가 올바르게 표시되도록 강제 레이아웃 업데이트
      if let layer = self.previewLayer {
        layer.setNeedsLayout()
        layer.layoutIfNeeded()
      }
      
      logDebug("레이아웃 업데이트 - 16:9 프레임: \(previewFrame)", category: .camera)
    }
  }

  // MARK: - Gesture Handlers

  @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
    let point = gesture.location(in: self)
    let focusPoint = CGPoint(
      x: point.x / bounds.width,
      y: point.y / bounds.height
    )

    setFocusPoint(focusPoint)
    showFocusIndicator(at: point)
  }

  @objc private func handleExposureDoubleTap(_ gesture: UITapGestureRecognizer) {
    let point = gesture.location(in: self)
    let exposurePoint = CGPoint(
      x: point.x / bounds.width,
      y: point.y / bounds.height
    )

    setExposurePoint(exposurePoint)
    showExposureIndicator(at: point)
  }

  @objc private func handleZoomPinch(_ gesture: UIPinchGestureRecognizer) {
    guard let device = getCurrentCameraDevice() else { return }

    do {
      try device.lockForConfiguration()

      let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 4.0)
      let currentZoom = device.videoZoomFactor
      let newZoom = currentZoom * gesture.scale

      device.videoZoomFactor = max(1.0, min(newZoom, maxZoom))

      device.unlockForConfiguration()
      gesture.scale = 1.0

    } catch {
      logError("Zoom adjustment failed: \(error)", category: .camera)
    }
  }

  // MARK: - Camera Control Methods

  private func setFocusPoint(_ point: CGPoint) {
    guard let device = getCurrentCameraDevice() else { return }

    do {
      try device.lockForConfiguration()

      if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = point
        device.focusMode = .autoFocus
      }

      if device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = point
        device.exposureMode = .autoExpose
      }

      device.unlockForConfiguration()
    } catch {
      logError("Focus adjustment failed: \(error)", category: .camera)
    }
  }

  private func setExposurePoint(_ point: CGPoint) {
    guard let device = getCurrentCameraDevice() else { return }

    do {
      try device.lockForConfiguration()

      if device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = point
        device.exposureMode = .continuousAutoExposure
      }

      device.unlockForConfiguration()
    } catch {
      logError("Exposure adjustment failed: \(error)", category: .camera)
    }
  }

  private func getCurrentCameraDevice() -> AVCaptureDevice? {
    return captureSession?.inputs.compactMap { input in
      (input as? AVCaptureDeviceInput)?.device
    }.first { $0.hasMediaType(.video) }
  }

  // MARK: - Visual Feedback

  private func showFocusIndicator(at point: CGPoint) {
    let indicator = FocusIndicatorView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
    indicator.center = point
    addSubview(indicator)

    indicator.animate {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        indicator.removeFromSuperview()
      }
    }
  }

  private func showExposureIndicator(at point: CGPoint) {
    let indicator = ExposureIndicatorView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
    indicator.center = point
    addSubview(indicator)

    indicator.animate {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        indicator.removeFromSuperview()
      }
    }
  }

  // MARK: - Streaming State Management

  func updateStreamingState(_ isStreaming: Bool) {
    self.isStreaming = isStreaming
    streamingStatusView.isHidden = !isStreaming
    updatePreviewLayer()
  }

  func updateStreamingStats(_ stats: StreamStats) {
    streamingStatusView.updateStats(stats)
  }
}

// MARK: - CameraControlOverlayDelegate

extension CameraPreviewUIView: CameraControlOverlayDelegate {
  func didTapRecord() {
    // 녹화 기능은 제외
    logInfo("Recording functionality not implemented", category: .general)
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraPreviewUIView: AVCaptureVideoDataOutputSampleBufferDelegate {
  /// AVCaptureVideoDataOutput에서 프레임을 받는 델리게이트 메서드
  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    // 🎬 화면 캡처 모드: 실시간 카메라 프레임 저장 (CameraScreenCapture.swift)
    processVideoFrameForScreenCapture(sampleBuffer)
    
    // 📡 일반 스트리밍 모드: HaishinKit에 프레임 통계 전달
    guard isStreaming, let manager = haishinKitManager else { return }

    // HaishinKit에 프레임 통계 정보 전달 (비동기 처리)
    Task {
      await manager.processVideoFrame(sampleBuffer)
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    // 프레임 드롭은 정상적인 현상이므로 로그 비활성화
  }
} 