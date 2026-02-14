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
import LiveStreamingCore

/// 실제 카메라 미리보기를 담당하는 UIView
final class CameraPreviewUIView: UIView {

  // MARK: - Properties

  /// AVFoundation 카메라 미리보기 레이어
  private var previewLayer: AVCaptureVideoPreviewLayer?

  /// HaishinKit 미리보기 레이어 (스트리밍 중일 때 사용)
  private var hkPreviewLayer: UIView?

  /// 비디오 출력 (화면 캡처 스트리밍용 프레임 수신 + 스트리밍 통계)
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
  private var isStreaming: Bool = false

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

  // MARK: - Text Overlay Properties (Deprecated - 호환성 유지용)

  /// 텍스트 오버레이 표시 여부
  /// - Note: 실제 기능은 SwiftUI의 TextOverlayDisplayView에서 처리
  /// - 이 프로퍼티는 인터페이스 호환성을 위해 유지됨
  var showTextOverlay: Bool = false

  /// 텍스트 오버레이 내용
  /// - Note: 실제 기능은 SwiftUI의 TextOverlayDisplayView에서 처리
  /// - 이 프로퍼티는 인터페이스 호환성을 위해 유지됨
  var overlayText: String = ""

  // MARK: - Internal Runtime Properties

  /// 런타임 상태 관리를 위한 Associated Object 키
  private struct AssociatedKeys {
    static var captureOutputDelegate = "captureOutputDelegate"
    static var captureOutputIsOwned = "captureOutputIsOwned"
  }

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

    // 컨트롤 오버레이 추가
    addSubview(controlOverlay)

    setupConstraints()
    setupGestureRecognizers()
    setupNotifications()
  }

  private func setupNotifications() {
    // 화면 캡처 제어 notification 구독
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleStartScreenCapture(_:)),
      name: .startScreenCapture,
      object: nil
    )

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleStopScreenCapture),
      name: .stopScreenCapture,
      object: nil
    )
  }

  @objc private func handleStartScreenCapture(_ notification: Notification) {
    logInfo("화면 캡처 시작 notification 수신", category: .streaming)
    if let userInfo = notification.userInfo,
       let width = userInfo["videoWidth"] as? Int,
       let height = userInfo["videoHeight"] as? Int {
      logInfo("시작 해상도 전달값 수신: \(width)×\(height)", category: .streaming)
    } else {
      logWarning("시작 notification에 해상도 정보가 없어 기본 설정으로 시작합니다", category: .streaming)
    }
    startScreenCapture(notification)
  }

  @objc private func handleStopScreenCapture() {
    logDebug("화면 캡처 중지 notification 수신", category: .streaming)
    clearStreamingTargetSize()
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

  /// 비디오 프레임 수신 설정 (화면 캡처 스트리밍 + 통계)
  /// - 화면 캡처 모드: 수신된 프레임을 latestCameraFrame에 저장하여 UI와 합성
  /// - 일반 스트리밍 모드: HaishinKit에 프레임 통계 전달
  func setupVideoFrameCapture(with session: AVCaptureSession) {
    let existingOutput = session.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }.first

    if let existingOutput {
      // 현재 세션에 이미 연결된 AVCaptureVideoDataOutput이 있으면 재사용
      // 새 아웃풋을 계속 추가/제거하면 프레임 전달이 끊길 수 있으므로 델리게이트만 교체
      if let previousDelegate = existingOutput.sampleBufferDelegate,
         !(previousDelegate is CameraPreviewUIView)
      {
        logInfo("기존 비디오 출력 델리게이트 백업: \(type(of: previousDelegate))", category: .camera)
        setCurrentCaptureOutput(previousDelegate)
      }

      session.beginConfiguration()
      existingOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

      // 비디오 설정 (가벼운 처리용)
      existingOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]

      // 프레임 드롭 허용 (성능 최적화)
      existingOutput.alwaysDiscardsLateVideoFrames = true

      session.commitConfiguration()

      // 이 출력은 외부 소유이므로 제거하지 않음
      setCaptureOutputReuseMode(false)
      videoOutput = existingOutput
      logInfo("기존 비디오 출력 델리게이트를 화면 캡처 모드로 전환", category: .camera)
      return
    }

    // 세션에 비디오 출력이 없다면 새 출력 추가
    let newVideoOutput = AVCaptureVideoDataOutput()
    newVideoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

    // 비디오 설정 (가벼운 처리용)
    newVideoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    // 프레임 드롭 허용 (성능 최적화)
    newVideoOutput.alwaysDiscardsLateVideoFrames = true

    session.beginConfiguration()

    // 세션에 추가
    if session.canAddOutput(newVideoOutput) {
      session.addOutput(newVideoOutput)
      videoOutput = newVideoOutput
      setCaptureOutputReuseMode(true)
      clearCaptureOutputOriginalDelegate()
      logInfo("화면 캡처 전용 비디오 출력 추가", category: .camera)
    } else {
      logError("비디오 프레임 수신 설정 실패", category: .camera)
      clearCaptureOutputReuseMode()
    }

    session.commitConfiguration()
  }

  /// 비디오 프레임 수신 해제
  func removeVideoFrameCapture() {
    guard let session = captureSession, let output = videoOutput else { return }

    if usesCapturedVideoOutputOwnerShip {
      session.beginConfiguration()
      session.removeOutput(output)
      session.commitConfiguration()
      logInfo("화면 캡처 전용 비디오 출력 제거 완료", category: .camera)
    } else if let originalDelegate = currentCaptureOutputDelegate {
      output.setSampleBufferDelegate(originalDelegate, queue: videoOutputQueue)
      logInfo("기존 비디오 출력 델리게이트 복원: \(type(of: originalDelegate))", category: .camera)
    } else {
      output.setSampleBufferDelegate(nil, queue: nil)
      logWarning("기존 비디오 출력 델리게이트 복원 대상 없음", category: .camera)
    }

    videoOutput = nil
    usesCapturedVideoOutputOwnerShip = false
    clearCaptureOutputOriginalDelegate()
  }

  // MARK: - Internal Camera Output State

  /// 기존 output 델리게이트 백업
  private var currentCaptureOutputDelegate: AVCaptureVideoDataOutputSampleBufferDelegate? {
    get {
      objc_getAssociatedObject(self, &AssociatedKeys.captureOutputDelegate) as?
        AVCaptureVideoDataOutputSampleBufferDelegate
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.captureOutputDelegate, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  /// 화면 캡처용 출력 소유 여부
  private var usesCapturedVideoOutputOwnerShip: Bool {
    get {
      (objc_getAssociatedObject(self, &AssociatedKeys.captureOutputIsOwned) as? NSNumber)?.boolValue
        ?? false
    }
    set {
      objc_setAssociatedObject(
        self, &AssociatedKeys.captureOutputIsOwned, NSNumber(value: newValue),
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  private func setCaptureOutputReuseMode(_ ownsOutput: Bool) {
    usesCapturedVideoOutputOwnerShip = ownsOutput
    logInfo("비디오 출력 소유 모드 변경: ownsOutput=\(ownsOutput)", category: .camera)
  }

  private func clearCaptureOutputReuseMode() {
    usesCapturedVideoOutputOwnerShip = false
  }

  private func setCurrentCaptureOutput(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
    if currentCaptureOutputDelegate == nil {
      currentCaptureOutputDelegate = delegate
    }
  }

  private func clearCaptureOutputOriginalDelegate() {
    currentCaptureOutputDelegate = nil
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

        // 스트리밍 표시 추가 및 비디오 프레임 수신 설정
        DispatchQueue.main.async { [weak self] in
          self?.addStreamingIndicatorOnly()
          // 프리뷰 레이어가 활성 상태인지 확인하고 필요시 복구
          self?.ensurePreviewLayerActive()
          // 비디오 프레임 수신 설정 (화면 캡처 스트리밍 + 통계)
          if let session = self?.captureSession {
            self?.setupVideoFrameCapture(with: session)
          }
        }
      } else {
        logInfo("스트리밍 종료됨 - 스트리밍 표시 제거", category: .streaming)

        // 스트리밍 표시 제거 및 비디오 프레임 수신 해제
        DispatchQueue.main.async { [weak self] in
          self?.removeStreamingIndicator()
          // 비디오 프레임 수신 해제
          self?.removeVideoFrameCapture()
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
    // 스트리밍 상태 업데이트는 다른 방식으로 처리됨
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
    NotificationCenter.default.removeObserver(self)
    // textOverlayLabel 제거됨 - SwiftUI에서 관리
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

    // 🔄 카메라 타입에 따른 미러링 설정 (외장 카메라 좌우 반전 문제 해결)
    if let connection = newPreviewLayer.connection {
      // 현재 연결된 카메라 디바이스 확인
      let currentDevice = getCurrentCameraDevice()
      let isExternalCamera = currentDevice?.deviceType == .external
      let isFrontCamera = currentDevice?.position == .front

      if connection.isVideoMirroringSupported {
        // 중요: 수동 미러링 설정을 위해 자동 조정 비활성화
        connection.automaticallyAdjustsVideoMirroring = false

        if isExternalCamera {
          // 외장 카메라: 미러링 끄기 (좌우 반전 방지)
          connection.isVideoMirrored = false
          logInfo("외장 카메라 미러링 OFF - 좌우 반전 방지", category: .camera)
        } else if isFrontCamera {
          // 내장 전면 카메라: 미러링 켜기 (일반적인 셀카 모드)
          connection.isVideoMirrored = true
          logInfo("내장 전면 카메라 미러링 ON - 셀카 모드", category: .camera)
        } else {
          // 내장 후면 카메라: 미러링 끄기
          connection.isVideoMirrored = false
          logInfo("내장 후면 카메라 미러링 OFF", category: .camera)
        }
      } else {
        logWarning("현재 연결에서 비디오 미러링이 지원되지 않음", category: .camera)
      }

      // 현재 카메라 정보 로깅
      if let device = currentDevice {
        logDebug(
          "현재 카메라: \(device.localizedName), 타입: \(device.deviceType), 위치: \(device.position)",
          category: .camera)
      }
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
    updatePreviewLayer()
  }
}

// MARK: - CameraControlOverlayDelegate

extension CameraPreviewUIView: CameraControlOverlayDelegate {
  /// 녹화 버튼 탭 처리
  /// - Note: 녹화 기능은 현재 앱 범위에서 제외됨 (스트리밍 전용 앱)
  func didTapRecord() {
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

// MARK: - Text Overlay Management (Removed)
// 텍스트 오버레이는 SwiftUI 레이어의 TextOverlayDisplayView에서 처리됩니다.
// CameraPreviewUIView에서는 중복 구현을 제거했습니다.
