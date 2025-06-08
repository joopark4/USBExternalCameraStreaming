//
//  CameraPreviewView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import HaishinKit
import SwiftUI
import UIKit
import Foundation

// MARK: - String Extension for Regex

extension String {
  func matches(for regex: String) -> [String] {
    do {
      let regex = try NSRegularExpression(pattern: regex)
      let results = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
      return results.map {
        String(self[Range($0.range, in: self)!])
      }
    } catch {
      return []
    }
  }
}

/// **실제 HaishinKit RTMP 스트리밍을 위한 카메라 미리보기**
struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession
  var streamViewModel: LiveStreamViewModel?
  var haishinKitManager: HaishinKitManager?

  init(
    session: AVCaptureSession, streamViewModel: LiveStreamViewModel? = nil,
    haishinKitManager: HaishinKitManager? = nil
  ) {
    self.session = session
    self.streamViewModel = streamViewModel
    self.haishinKitManager = haishinKitManager
  }

  func makeUIView(context: Context) -> UIView {
    // 항상 AVCaptureVideoPreviewLayer 사용하여 카메라 미리보기 유지
    // HaishinKit은 백그라운드에서 스트리밍만 처리
    let view = CameraPreviewUIView()
    view.captureSession = session
    view.haishinKitManager = haishinKitManager
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    if let previewView = uiView as? CameraPreviewUIView {
      // 세션이나 매니저가 변경된 경우에만 업데이트
      let sessionChanged = previewView.captureSession !== session
      let managerChanged = previewView.haishinKitManager !== haishinKitManager

      if sessionChanged {
        logInfo("캡처 세션 변경 감지 - 업데이트", category: .camera)
        previewView.captureSession = session
      }

      if managerChanged {
        logInfo("HaishinKit 매니저 변경 감지 - 업데이트", category: .camera)
        previewView.haishinKitManager = haishinKitManager
      }

      // 프리뷰 새로고침은 하지 않음 (안정성 향상)
      logInfo("업데이트 완료 - 프리뷰 새로고침 건너뜀", category: .camera)
    }
  }

  // MARK: - Screen Capture Control Methods

  /// 화면 캡처 송출 시작 (외부에서 호출 가능)
  func startScreenCapture() {
    // UIViewRepresentable에서 UIView에 접근하는 방법이 제한적이므로
    // HaishinKitManager를 통해 제어하는 것을 권장
    logInfo("화면 캡처 요청됨 - HaishinKitManager 사용 권장", category: .streaming)
  }

  /// 화면 캡처 송출 중지 (외부에서 호출 가능)
  func stopScreenCapture() {
    logInfo("화면 캡처 중지 요청됨", category: .streaming)

    // 화면 캡처 중지 알림 전송
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .stopScreenCapture, object: nil)
    }
  }
}

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

  /// 화면 캡처용 타이머
  private var screenCaptureTimer: Timer?

  /// 화면 캡처 상태
  private var isScreenCapturing: Bool = false
  
  /// 최근 카메라 프레임 (화면 캡처용)
  private var latestCameraFrame: CVPixelBuffer?
  private let frameProcessingQueue = DispatchQueue(label: "CameraFrameProcessing", qos: .userInteractive)
  
  /// 프레임 카운터 (통계 출력용)
  private var frameCounter = 0

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
    // addSubview(streamingStatusView) // 중복 제거

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

      // 스트리밍 상태 표시 제약 제거 (중복 방지)
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
            // print("📹 [CameraPreview] 비디오 프레임 모니터링 설정") // 반복적인 로그 비활성화

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
                  // print("✅ [CameraPreview] 비디오 프레임 모니터링 설정 완료") // 반복적인 로그 비활성화
        } else {
            logError("비디오 프레임 모니터링 설정 실패", category: .camera)
    }
  }

  /// 비디오 프레임 모니터링 해제
  private func removeVideoMonitoring() {
    guard let session = captureSession, let output = videoOutput else { return }

            // print("📹 [CameraPreview] 비디오 프레임 모니터링 해제") // 반복적인 로그 비활성화
    session.removeOutput(output)
    videoOutput = nil
  }

  /// 스트리밍 상태 업데이트 (개선된 버전)
  private func updateStreamingStatus() {
    guard let manager = haishinKitManager else {
      isStreaming = false
      // StreamingStatusView는 사용하지 않음 (중복 방지)
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
    // 작은 라이브 표시만 사용
    //        print("📊 [CameraPreview] 상세 상태 업데이트 건너뜀 (중복 방지)")
  }

  /// 스트리밍 상태 표시 뷰 업데이트 (비활성화 - 중복 방지)
  private func updateStreamingStatusView() {
    // StreamingStatusView 사용하지 않음 (중복 방지)
    // 작은 라이브 표시만 사용
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
    
            // print("✅ [CameraPreview] 화면 캡처 타이머 시작됨 (25fps - 성능 최적화)") // 반복적인 로그 비활성화
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
                    // print("❌ [화면캡처] UIImage 렌더링 실패 - 프레임 스킵") // 반복적인 로그 비활성화
        return
      }
      
      // 성능 최적화: 프레임별 상세 로그 제거 (CPU 부하 감소)
      // print("✅ [화면캡처] 화면 렌더링 성공: \(capturedImage.size)")

      // Step 2: UIImage를 CVPixelBuffer로 변환 (HaishinKit 호환 포맷)
      guard let pixelBuffer = capturedImage.toCVPixelBuffer() else {
                    // print("❌ [화면캡처] CVPixelBuffer 변환 실패 - 프레임 스킵") // 반복적인 로그 비활성화
        return
      }
      
      // 성능 최적화: 변환 성공 로그 제거
      // let width = CVPixelBufferGetWidth(pixelBuffer)
      // let height = CVPixelBufferGetHeight(pixelBuffer)
      // print("✅ [화면캡처] CVPixelBuffer 변환 성공: \(width)x\(height)")

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
      // 케이스 1: 카메라 프레임 + UI 합성 (고해상도)
              // print("🎥 [고해상도 렌더링] 카메라 프레임 + UI 합성 모드") // 반복적인 로그 비활성화
      return renderCameraFrameWithUIForStreaming(cameraFrame: cameraFrame, streamingSize: streamingSize)
    } else {
      // 케이스 2: UI만 고해상도 캡처 (카메라 프레임 없음)
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
      // 케이스 1: 카메라 프레임 + UI 합성 (단말 크기)
              // print("🎥 [단말렌더링] 카메라 프레임 + UI 합성 모드") // 반복적인 로그 비활성화
      return renderCameraFrameWithUI(cameraFrame: cameraFrame, viewSize: size)
    } else {
      // 케이스 2: UI만 캡처 (단말 크기)
      logDebug("UI만 캡처 모드", category: .performance)
      let renderer = UIGraphicsImageRenderer(bounds: bounds)
      return renderer.image { context in
        layer.render(in: context.cgContext)
      }
    }
  }
  
  /// 송출용 고해상도 카메라 프레임과 UI 합성
  /// 
  /// 1920x1080 크기로 고품질 렌더링하여 업스케일링으로 인한 화질 저하 방지
  /// 
  /// - Parameter cameraFrame: 실시간 카메라 프레임 (CVPixelBuffer)
  /// - Parameter streamingSize: 송출 목표 해상도 (1920x1080)
  /// - Returns: 고해상도 합성 이미지 또는 nil
  private func renderCameraFrameWithUIForStreaming(cameraFrame: CVPixelBuffer, streamingSize: CGSize) -> UIImage? {
    
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
  private func calculateCameraPreviewRect(in containerSize: CGSize) -> CGRect {
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
  private func calculateActualVideoRect(previewLayer: AVCaptureVideoPreviewLayer) -> CGRect {
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
  private func renderUIOnlyForStreaming(streamingSize: CGSize) -> UIImage? {
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
  private func renderCameraFrameWithUI(cameraFrame: CVPixelBuffer, viewSize: CGSize) -> UIImage? {
    
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
    // 성능 최적화: 프레임별 전송 로그 제거 (CPU 부하 감소)
    // let width = CVPixelBufferGetWidth(pixelBuffer)
    // let height = CVPixelBufferGetHeight(pixelBuffer)
            // print("📡 [전송] HaishinKit 프레임 전달: \(width)x\(height)") // 이미 비활성화됨

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

  /// 송출 해상도에 따른 최적 캡처 사이즈 계산 (16:9 비율 고정)
  /// 
  /// **16:9 비율 강제 적용:**
  /// - 480p(854x480) → 16:9 비율로 수정 후 2배 업스케일
  /// - 720p(1280x720) → 2배 업스케일  
  /// - 1080p(1920x1080) → 동일 해상도 캡처
  /// - 모든 해상도를 16:9 비율로 강제 변환
  /// 
  /// - Returns: 16:9 비율이 보장된 최적 캡처 해상도
  private func getOptimalCaptureSize() -> CGSize {
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
      completion(false, NSError(domain: "CameraPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "화면 캡처 실패"]))
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

  // MARK: - Usage Example & Notes

  /*
   사용 예시:
  
   1. 일반 카메라 스트리밍: (제거됨 - 화면 캡처 스트리밍만 사용)
      // try await haishinKitManager.startStreaming(with: settings, captureSession: captureSession)
  
   2. 화면 캡처 스트리밍:
      // Step 1: 화면 캡처 모드로 스트리밍 시작
      try await haishinKitManager.startScreenCaptureStreaming(with: settings)
  
      // Step 2: CameraPreviewUIView에서 화면 캡처 시작
      cameraPreviewUIView.startScreenCapture()
  
      // Step 3: 중지할 때
      cameraPreviewUIView.stopScreenCapture()
      await haishinKitManager.stopStreaming()
  
   주의사항:
   - 화면 캡처는 30fps로 동작하므로 성능에 영향을 줄 수 있습니다
   - UIView 렌더링은 메인 스레드에서 실행되므로 UI 블로킹 가능성이 있습니다
   - 화면에 보이는 모든 UI 요소(버튼, 라벨 등)가 송출에 포함됩니다
   - 실제 HaishinKit manual capture 구현은 추가 작업이 필요합니다
   */
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
  /// 
  /// **이 메서드의 두 가지 역할:**
  /// 1. **화면 캡처 모드**: 실시간 카메라 프레임을 저장하여 UI와 합성
  /// 2. **일반 스트리밍 모드**: HaishinKit에 프레임 통계 정보 전달
  ///
  /// **성능 최적화:**
  /// - 화면 캡처 중일 때만 프레임을 저장하여 메모리 사용량 최소화
  /// - 백그라운드 큐에서 프레임 저장 작업 수행하여 메인 스레드 블록킹 방지
  ///
  /// - Parameter output: 출력 객체 (AVCaptureVideoDataOutput)
  /// - Parameter sampleBuffer: 카메라에서 캡처된 프레임 데이터
  /// - Parameter connection: 입력과 출력 간의 연결 정보
  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
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
        // print("✅ [프레임저장] 최신 카메라 프레임 업데이트됨") // 반복적인 로그 비활성화
      }
    }
    
    // 📡 일반 스트리밍 모드: HaishinKit에 프레임 통계 전달
    // 화면 캡처가 아닌 일반 카메라 스트리밍 시 성능 모니터링용
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
        // print("⚠️ [CameraPreview] 비디오 프레임 드롭됨 - 성능 최적화 필요할 수 있음")
  }
}

// MARK: - Supporting Views

/// 카메라 컨트롤 오버레이
protocol CameraControlOverlayDelegate: AnyObject {
  func didTapRecord()
}

final class CameraControlOverlay: UIView {
  weak var delegate: CameraControlOverlayDelegate?

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    // 버튼들을 제거했으므로 빈 뷰로 설정
  }
}

/// 스트리밍 상태 표시 뷰
final class StreamingStatusView: UIView {

  private lazy var containerView: UIView = {
    let view = UIView()
    view.backgroundColor = UIColor.red.withAlphaComponent(0.8)
    view.layer.cornerRadius = 8
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var liveLabel: UILabel = {
    let label = UILabel()
    label.text = "🔴 LIVE"
    label.textColor = .white
    label.font = .boldSystemFont(ofSize: 14)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var statsLabel: UILabel = {
    let label = UILabel()
    label.textColor = .white
    label.font = .systemFont(ofSize: 12)
    label.numberOfLines = 2
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    addSubview(containerView)
    containerView.addSubview(liveLabel)
    containerView.addSubview(statsLabel)

    NSLayoutConstraint.activate([
      containerView.topAnchor.constraint(equalTo: topAnchor),
      containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

      liveLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
      liveLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
      liveLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),

      statsLabel.topAnchor.constraint(equalTo: liveLabel.bottomAnchor, constant: 4),
      statsLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
      statsLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
      statsLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
    ])
  }

  func updateStatus(_ status: String) {
    liveLabel.text = status
  }

  /// 재연결 상태 업데이트
  func updateReconnectingStatus(_ attempt: Int, _ maxAttempts: Int, _ delay: Int) {
    liveLabel.text = "🔄 재연결 중"
    statsLabel.text = "시도: \(attempt)/\(maxAttempts)\n\(delay)초 후 재시도"

    // 재연결 중일 때 배경색을 주황색으로 변경
    containerView.backgroundColor = UIColor.orange.withAlphaComponent(0.8)
  }

  /// 연결 실패 상태 업데이트
  func updateFailedStatus(_ message: String) {
    liveLabel.text = "❌ 연결 실패"
    statsLabel.text = message

    // 실패 시 배경색을 빨간색으로 변경
    containerView.backgroundColor = UIColor.red.withAlphaComponent(0.8)
  }

  /// 정상 스트리밍 상태로 복원
  func updateStreamingStatus() {
    liveLabel.text = "🔴 LIVE"

    // 정상 상태로 배경색 복원
    containerView.backgroundColor = UIColor.red.withAlphaComponent(0.8)
  }

  func updateStats(_ stats: StreamStats) {
    let duration = formatDuration(Int(stats.duration))
    statsLabel.text = "\(duration)\n\(Int(stats.videoBitrate))kbps"
  }

  private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    } else {
      return String(format: "%02d:%02d", minutes, secs)
    }
  }
}

/// 포커스 인디케이터 뷰
final class FocusIndicatorView: UIView {

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    backgroundColor = .clear
    layer.borderColor = UIColor.yellow.cgColor
    layer.borderWidth = 2
    alpha = 0
  }

  func animate(completion: @escaping () -> Void) {
    UIView.animate(
      withDuration: 0.2,
      animations: {
        self.alpha = 1.0
        self.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
      }
    ) { _ in
      UIView.animate(
        withDuration: 0.3,
        animations: {
          self.alpha = 0.8
          self.transform = CGAffineTransform.identity
        }
      ) { _ in
        UIView.animate(
          withDuration: 1.0,
          animations: {
            self.alpha = 0
          },
          completion: { _ in
            completion()
          })
      }
    }
  }
}

/// 노출 인디케이터 뷰
final class ExposureIndicatorView: UIView {

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    backgroundColor = .clear
    layer.borderColor = UIColor.orange.cgColor
    layer.borderWidth = 2
    layer.cornerRadius = 30
    alpha = 0

    let sunIcon = UILabel()
    sunIcon.text = "☀️"
    sunIcon.font = .systemFont(ofSize: 24)
    sunIcon.textAlignment = .center
    sunIcon.translatesAutoresizingMaskIntoConstraints = false
    addSubview(sunIcon)

    NSLayoutConstraint.activate([
      sunIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
      sunIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  func animate(completion: @escaping () -> Void) {
    UIView.animate(
      withDuration: 0.2,
      animations: {
        self.alpha = 1.0
        self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
      }
    ) { _ in
      UIView.animate(
        withDuration: 0.3,
        animations: {
          self.alpha = 0.8
          self.transform = CGAffineTransform.identity
        }
      ) { _ in
        UIView.animate(
          withDuration: 1.0,
          animations: {
            self.alpha = 0
          },
          completion: { _ in
            completion()
          })
      }
    }
  }
}

// MARK: - Extensions

/// CVPixelBuffer를 UIImage로 변환하는 확장
/// 
/// **용도:**
/// - 실시간 카메라 프레임(CVPixelBuffer)을 UI 합성이 가능한 UIImage로 변환
/// - AVCaptureVideoDataOutput에서 받은 프레임을 화면 캡처 시 사용
///
/// **변환 과정:**
/// 1. CVPixelBuffer → CIImage 변환
/// 2. CIImage → CGImage 변환 (Core Graphics 호환)
/// 3. CGImage → UIImage 변환 (UIKit 호환)
extension CVPixelBuffer {
  
  /// CVPixelBuffer를 UIImage로 변환
  /// 
  /// Core Image 프레임워크를 사용하여 픽셀 버퍼를 이미지로 변환합니다.
  /// 이 과정은 GPU 가속을 활용하여 효율적으로 수행됩니다.
  ///
  /// **성능 고려사항:**
  /// - CIContext는 GPU 리소스를 사용하므로 재사용 권장
  /// - 현재는 매번 새로 생성하지만, 향후 캐싱 최적화 가능
  ///
  /// - Returns: 변환된 UIImage 또는 변환 실패 시 nil
  func toUIImage() -> UIImage? {
    // Step 1: CVPixelBuffer를 CIImage로 변환
    // Core Image가 픽셀 버퍼를 직접 처리할 수 있는 형태로 변환
    let ciImage = CIImage(cvPixelBuffer: self)
    
    // Step 2: CIContext 생성 (GPU 가속 활용)
    // TODO: 성능 최적화를 위해 전역 CIContext 캐싱 고려
    let context = CIContext()
    
    // Step 3: CIImage를 CGImage로 변환
    // extent: 이미지의 전체 영역을 의미 (원본 크기 유지)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      print("❌ [CVPixelBuffer] CIImage → CGImage 변환 실패")
      return nil
    }
    
    // Step 4: CGImage를 UIImage로 변환 (UIKit 호환)
    // 최종적으로 UIKit에서 사용 가능한 형태로 변환 완료
    return UIImage(cgImage: cgImage)
  }
}

/// UIImage를 CVPixelBuffer로 변환하는 확장
extension UIImage {
  func toCVPixelBuffer() -> CVPixelBuffer? {
    let attrs =
      [
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any,
        kCVPixelBufferIOSurfacePropertiesKey: [:],
      ] as CFDictionary

    var pixelBuffer: CVPixelBuffer?

    // BGRA 포맷 사용 (HaishinKit과 호환성 향상)
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
      kCVPixelFormatType_32BGRA,
      attrs,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      print("❌ [CVPixelBuffer] 생성 실패: \(status)")
      return nil
    }

    CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
    defer {
      CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
    }

    let pixelData = CVPixelBufferGetBaseAddress(buffer)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

    // BGRA 포맷에 맞는 컨텍스트 생성
    guard
      let context = CGContext(
        data: pixelData,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: rgbColorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else {
      print("❌ [CVPixelBuffer] CGContext 생성 실패")
      return nil
    }

    // 이미지 그리기 (Y축 뒤집기)
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1.0, y: -1.0)

    UIGraphicsPushContext(context)
    draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    UIGraphicsPopContext()

    print("✅ [CVPixelBuffer] 생성 성공: \(Int(size.width))x\(Int(size.height)) BGRA")
    return buffer
  }
}

