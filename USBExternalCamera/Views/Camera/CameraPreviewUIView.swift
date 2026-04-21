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
  #if DEBUG
    private static let isPreviewDebugLoggingEnabled =
      ProcessInfo.processInfo.arguments.contains("--preview-debug-log")
      || UserDefaults.standard.bool(forKey: "Debug.previewDebugLoggingEnabled")
  #endif

  // MARK: - Properties

  /// AVFoundation 카메라 미리보기 레이어
  private var previewLayer: AVCaptureVideoPreviewLayer?

  /// HaishinKit 미리보기 레이어 (스트리밍 중일 때 사용)
  private var hkPreviewLayer: UIView?

  /// 프리뷰가 수신할 카메라 프레임 라우터
  weak var frameRouter: CameraPreviewFrameRouting? {
    didSet {
      if oldValue !== frameRouter, isFrameConsumerRegistered {
        oldValue?.removePreviewFrameConsumer(screenCaptureFrameConsumer)
        isFrameConsumerRegistered = false
      }
      updateFrameConsumerRegistration()
    }
  }

  /// 프리뷰 프레임 소비자 등록 여부
  private var isFrameConsumerRegistered = false

  /// 화면 캡처용 최신 프레임 저장소
  let screenCaptureFrameStore = ScreenCaptureFrameStore()

  /// 화면 캡처용 프레임 소비자
  lazy var screenCaptureFrameConsumer = ScreenCaptureFrameConsumer(
    frameStore: screenCaptureFrameStore
  )

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

  /// 프리뷰와 송출 레이아웃 기준이 되는 현재 스트리밍 설정
  var streamingSettings: LiveStreamSettings? {
    didSet {
      guard hasMeaningfulStreamingSettingChange(from: oldValue, to: streamingSettings) else { return }
      requestPreviewPresentationUpdate(forceConnectionRefresh: false)
    }
  }

  /// 스트리밍 상태
  private var isStreaming: Bool = false

  /// 스트리밍 상태 모니터링 타이머
  private var statusMonitorTimer: Timer?

  /// 비디오 출력 연결 설정 캐시 키 (카메라/방향 변화 시에만 재설정)
  private var videoOutputConnectionConfigKey: String?

  /// 프리뷰 레이어 지오메트리 재구성 캐시 키
  private var previewGeometryConfigKey: String?

  /// 프리뷰 레이어 지오메트리 갱신 작업 (중복 스케줄 방지)
  private var pendingPreviewPresentationUpdate: DispatchWorkItem?

  /// 프리뷰 갱신 시 비디오 output sync까지 함께 요청할지 여부
  private var pendingPreviewConnectionRefresh = false

  /// 회전 중 발생하는 중간 레이아웃 변화를 한 번으로 합치기 위한 짧은 지연
  private let previewPresentationDebounceInterval: TimeInterval = 0.03

  #if DEBUG
    /// 마지막으로 기록한 프리뷰 디버그 스냅샷
    private var lastPreviewDebugSnapshot: String?
  #endif

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

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateFrameConsumerRegistration()
  }

  func updateFrameConsumerRegistration() {
    guard let frameRouter else {
      isFrameConsumerRegistered = false
      return
    }

    if window != nil && isScreenCapturing {
      guard !isFrameConsumerRegistered else { return }
      frameRouter.addPreviewFrameConsumer(screenCaptureFrameConsumer)
      isFrameConsumerRegistered = true
      logInfo("프리뷰 프레임 소비자 등록 완료", category: .camera)
      return
    }

    if isFrameConsumerRegistered {
      frameRouter.removePreviewFrameConsumer(screenCaptureFrameConsumer)
      isFrameConsumerRegistered = false
      logInfo("프리뷰 프레임 소비자 해제 완료", category: .camera)
    }
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

    // 카메라 입력이 교체되면 새 AVCaptureConnection 이 기본 orientation 으로 만들어지므로
    // 프리뷰 레이어의 회전/방향을 다시 적용해야 함 (세로 모드 회귀 방지).
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleCameraDidSwitch(_:)),
      name: .cameraSessionDidSwitchCamera,
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

  @objc private func handleCameraDidSwitch(_ notification: Notification) {
    logInfo("카메라 전환 notification 수신 - 프리뷰 연결 재적용", category: .camera)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      // 새 AVCaptureDeviceInput 으로 갈아끼워지면 프리뷰 레이어 connection 은 기본 orientation 으로
      // 재생성될 수 있다. 캐시 키를 무효화한 뒤 강제 refresh 를 요청하면
      // `performPreviewPresentationUpdate` 내부에서 프리뷰 connection 재적용과
      // `refreshVideoOutputConnectionIfNeeded(force:)` 가 함께 수행된다.
      self.invalidatePreviewGeometryConfigCache()
      self.invalidateVideoOutputConnectionConfigCache()
      self.requestPreviewPresentationUpdate(forceConnectionRefresh: true)
    }
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

  private func hasMeaningfulStreamingSettingChange(
    from oldValue: LiveStreamSettings?,
    to newValue: LiveStreamSettings?
  ) -> Bool {
    switch (oldValue, newValue) {
    case (nil, nil):
      return false
    case (nil, _), (_, nil):
      return true
    case let (oldValue?, newValue?):
      return oldValue.videoWidth != newValue.videoWidth
        || oldValue.videoHeight != newValue.videoHeight
        || oldValue.streamOrientation != newValue.streamOrientation
    }
  }

  private var activeStreamingSettings: LiveStreamSettings {
    streamingSettings ?? haishinKitManager?.getCurrentSettings() ?? LiveStreamSettings()
  }

  private var activeStreamLayoutProfile: StreamLayoutProfile {
    activeStreamingSettings.streamLayoutProfile
  }

  private var previewAspectRatio: CGFloat {
    let aspectRatio = activeStreamingSettings.streamAspectRatio
    return aspectRatio > 0 ? aspectRatio : activeStreamLayoutProfile.aspectRatio
  }

  private var currentInterfaceOrientation: UIInterfaceOrientation? {
    window?.windowScene?.interfaceOrientation
  }

  private var previewNeedsVisualQuarterTurn: Bool {
    false
  }

  private var previewVisualRotationAngle: CGFloat {
    0
  }

  private func calculatePreviewFrame(in viewBounds: CGRect) -> CGRect {
    let aspectRatio = previewAspectRatio
    guard viewBounds.width > 0, viewBounds.height > 0, aspectRatio > 0 else {
      return viewBounds
    }

    if viewBounds.width / viewBounds.height > aspectRatio {
      let width = viewBounds.height * aspectRatio
      let offsetX = (viewBounds.width - width) / 2
      return CGRect(x: offsetX, y: 0, width: width, height: viewBounds.height)
    }

    let height = viewBounds.width / aspectRatio
    let offsetY = (viewBounds.height - height) / 2
    return CGRect(x: 0, y: offsetY, width: viewBounds.width, height: height)
  }

  private var previewConnectionOrientation: PreviewVideoOrientation {
    if let interfaceOrientation = currentInterfaceOrientation {
      return previewVideoOrientation(for: interfaceOrientation)
    }

    if let deviceOrientation = fallbackPreviewVideoOrientationFromDevice() {
      return deviceOrientation
    }

    return .portrait
  }

  private var previewConnectionRotationAngle: CGFloat? {
    return nil
  }

  private var videoOutputRotationAngle: CGFloat? {
    previewConnectionRotationAngle
  }

  private var videoOutputOrientation: PreviewVideoOrientation {
    previewConnectionOrientation
  }

  private func previewLayerBounds(for previewFrame: CGRect) -> CGRect {
    CGRect(origin: .zero, size: previewFrame.size)
  }

  private func applyPreviewConnectionOrientation(to connection: AVCaptureConnection?) {
    guard let connection else { return }

    guard connection.isVideoOrientationSupported else { return }

    switch previewConnectionOrientation {
    case .portrait:
      connection.videoOrientation = .portrait
    case .portraitUpsideDown:
      connection.videoOrientation = .portraitUpsideDown
    case .landscapeRight:
      connection.videoOrientation = .landscapeRight
    case .landscapeLeft:
      connection.videoOrientation = .landscapeLeft
    }
  }

  private func previewVideoOrientation(for interfaceOrientation: UIInterfaceOrientation)
    -> PreviewVideoOrientation
  {
    switch interfaceOrientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    default:
      return .portrait
    }
  }

  private func fallbackPreviewVideoOrientationFromDevice() -> PreviewVideoOrientation? {
    switch UIDevice.current.orientation {
    case .portrait:
      return .portrait
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeRight
    case .landscapeRight:
      return .landscapeLeft
    default:
      return nil
    }
  }

  private func roundedPreviewDimension(_ value: CGFloat) -> Int {
    Int(value.rounded(.toNearestOrAwayFromZero))
  }

  private func makePreviewGeometryConfigKey() -> String {
    let previewFrame = calculatePreviewFrame(in: bounds)
    let interfaceOrientation = window?.windowScene?.interfaceOrientation.rawValue ?? -1
    let sessionIdentifier = captureSession.map { ObjectIdentifier($0).hashValue } ?? 0

    return [
      "bounds:\(roundedPreviewDimension(bounds.width))x\(roundedPreviewDimension(bounds.height))",
      "preview:\(roundedPreviewDimension(previewFrame.width))x\(roundedPreviewDimension(previewFrame.height))",
      "stream:\(activeStreamingSettings.streamOrientation.rawValue)",
      "interface:\(interfaceOrientation)",
      "session:\(sessionIdentifier)",
    ].joined(separator: "|")
  }

  private func invalidatePreviewGeometryConfigCache() {
    previewGeometryConfigKey = nil
  }

  private func requestPreviewPresentationUpdate(forceConnectionRefresh: Bool = false) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.requestPreviewPresentationUpdate(forceConnectionRefresh: forceConnectionRefresh)
      }
      return
    }

    if forceConnectionRefresh {
      pendingPreviewConnectionRefresh = true
    }

    pendingPreviewPresentationUpdate?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.pendingPreviewPresentationUpdate = nil
      self.performPreviewPresentationUpdate()
    }

    pendingPreviewPresentationUpdate = workItem
    let delay = forceConnectionRefresh ? 0 : previewPresentationDebounceInterval
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func performPreviewPresentationUpdate() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.performPreviewPresentationUpdate()
      }
      return
    }

    let forceConnectionRefresh = pendingPreviewConnectionRefresh
    pendingPreviewConnectionRefresh = false

    guard let session = captureSession else { return }

    let previewFrame = calculatePreviewFrame(in: bounds)
    let geometryKey = makePreviewGeometryConfigKey()
    let needsPreviewLayerRebuild =
      previewLayer == nil
      || previewLayer?.session !== session

    guard forceConnectionRefresh || needsPreviewLayerRebuild || previewGeometryConfigKey != geometryKey else {
      return
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewGeometryConfigKey = geometryKey
    previewLayer?.bounds = previewLayerBounds(for: previewFrame)
    previewLayer?.position = CGPoint(x: previewFrame.midX, y: previewFrame.midY)
    hkPreviewLayer?.frame = previewFrame
    applyPreviewConnectionOrientation(to: previewLayer?.connection)
    previewLayer?.setAffineTransform(CGAffineTransform(rotationAngle: previewVisualRotationAngle))
    CATransaction.commit()

    logPreviewDebugSnapshot(context: "updatePreviewPresentation")

    refreshVideoOutputConnectionIfNeeded(force: forceConnectionRefresh)
  }

  private func previewLayerPointToDevicePoint(_ point: CGPoint) -> CGPoint {
    guard let previewLayer else {
      let x = bounds.width > 0 ? point.x / bounds.width : 0.5
      let y = bounds.height > 0 ? point.y / bounds.height : 0.5
      return CGPoint(x: x, y: y)
    }

    let layerPoint = layer.convert(point, to: previewLayer)
    return previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
  }

  // MARK: - Preview Layer Management

  private func updatePreviewLayer() {
    invalidatePreviewGeometryConfigCache()
    pendingPreviewPresentationUpdate?.cancel()
    pendingPreviewPresentationUpdate = nil
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
    }

    requestPreviewPresentationUpdate(forceConnectionRefresh: false)

    logDebug("프리뷰 레이어 보호 완료", category: .camera)
  }

  /// 비디오 프레임 수신 설정 (화면 캡처 스트리밍 + 통계)
  /// - 화면 캡처 모드: 수신된 프레임을 latestCameraFrame에 저장하여 UI와 합성
  /// - 일반 스트리밍 모드: HaishinKit에 프레임 통계 전달
  func setupVideoFrameCapture(with session: AVCaptureSession) {
    guard captureSession === session else {
      captureSession = session
      return
    }
    updateFrameConsumerRegistration()
    invalidatePreviewGeometryConfigCache()
    invalidateVideoOutputConnectionConfigCache()
    refreshVideoOutputConnectionIfNeeded(force: true)
  }

  /// 화면 캡처용 비디오 출력 연결을 프리뷰와 동일한 방향으로 정렬
  private func syncVideoOutputConnection() {
    guard let frameRouter else { return }

    let currentDevice = getCurrentCameraDevice()
    let isExternalCamera = currentDevice?.deviceType == .external
    let isFrontCamera = currentDevice?.position == .front
    let previewMirrored = previewLayer?.connection?.isVideoMirroringSupported == true
      ? (previewLayer?.connection?.isVideoMirrored ?? false)
      : (!isExternalCamera && isFrontCamera)

    frameRouter.syncPreviewVideoOutputConnection(
      rotationAngle: videoOutputRotationAngle,
      orientation: videoOutputOrientation,
      isMirrored: previewMirrored
    )
  }

  private func refreshVideoOutputConnectionIfNeeded(force: Bool = false) {
    let configKey = makeVideoOutputConnectionConfigKey()
    guard force || videoOutputConnectionConfigKey != configKey else {
      return
    }

    syncVideoOutputConnection()
    videoOutputConnectionConfigKey = configKey
  }

  private func invalidateVideoOutputConnectionConfigCache() {
    videoOutputConnectionConfigKey = nil
  }

  private func makeVideoOutputConnectionConfigKey() -> String {
    var keyComponents: [String] = []

    if let previewConnection = previewLayer?.connection {
      if #available(iOS 17.0, *) {
        keyComponents.append("angle:\(previewConnection.videoRotationAngle)")
      } else {
        keyComponents.append("orientation:\(previewConnection.videoOrientation.rawValue)")
      }

      if previewConnection.isVideoMirroringSupported {
        keyComponents.append("mirrored:\(previewConnection.isVideoMirrored)")
      } else {
        keyComponents.append("mirrored:unsupported")
      }
    } else {
      keyComponents.append("preview:none")
    }

    if let currentDevice = getCurrentCameraDevice() {
      keyComponents.append("device:\(currentDevice.uniqueID)")
      keyComponents.append("position:\(currentDevice.position.rawValue)")
      keyComponents.append("external:\(currentDevice.deviceType == .external)")
    } else {
      keyComponents.append("device:none")
    }

    return keyComponents.joined(separator: "|")
  }

  /// 비디오 프레임 수신 해제
  func removeVideoFrameCapture() {
    updateFrameConsumerRegistration()
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
    pendingPreviewPresentationUpdate?.cancel()
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
    let previewFrame = calculatePreviewFrame(in: bounds)
    newPreviewLayer.bounds = previewLayerBounds(for: previewFrame)
    newPreviewLayer.position = CGPoint(x: previewFrame.midX, y: previewFrame.midY)

    // 프리뷰는 카메라 원본 방향을 유지하고 남는 영역은 검은색으로 둡니다.
    newPreviewLayer.videoGravity = .resizeAspect

    applyPreviewConnectionOrientation(to: newPreviewLayer.connection)
    newPreviewLayer.setAffineTransform(.identity)

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
    previewGeometryConfigKey = makePreviewGeometryConfigKey()
    invalidateVideoOutputConnectionConfigCache()
    pendingPreviewConnectionRefresh = true
    performPreviewPresentationUpdate()
    logPreviewDebugSnapshot(context: "setupAVFoundationPreview")

    logInfo("AVFoundation 프리뷰 레이어 설정 완료", category: .camera)
    logDebug("송출 비율 프레임: \(previewFrame)", category: .camera)
    logDebug("videoGravity: resizeAspect (카메라 원본 비율 유지)", category: .camera)
  }

  #if DEBUG
    private func logPreviewDebugSnapshot(context: String) {
      guard Self.isPreviewDebugLoggingEnabled else { return }

      let previewFrame = calculatePreviewFrame(in: bounds)
      let connectionDescription: String = {
        guard let connection = previewLayer?.connection else { return "none" }

        if #available(iOS 17.0, *) {
          return "angle=\(Int(connection.videoRotationAngle))"
        }

        return "orientation=\(connection.videoOrientation.rawValue)"
      }()

      let snapshot = [
        "context=\(context)",
        "stream=\(activeStreamingSettings.streamOrientation.rawValue)",
        "interface=\(currentInterfaceOrientation?.rawValue ?? -1)",
        "previewFrame=\(Int(previewFrame.width))x\(Int(previewFrame.height))",
        "layerBounds=\(Int(previewLayer?.bounds.width ?? 0))x\(Int(previewLayer?.bounds.height ?? 0))",
        "visualTurn=\(previewNeedsVisualQuarterTurn)",
        "visualAngle=\(Int(previewVisualRotationAngle * 180 / .pi))",
        "connection=\(connectionDescription)",
      ].joined(separator: " | ")

      guard snapshot != lastPreviewDebugSnapshot else { return }
      lastPreviewDebugSnapshot = snapshot

      let message = "\(ISO8601DateFormatter().string(from: Date())) | \(snapshot)\n"
      persistPreviewDebugMessage(message)
      logDebug("프리뷰 디버그: \(snapshot)", category: .camera)
    }

    private func persistPreviewDebugMessage(_ message: String) {
      DispatchQueue.global(qos: .utility).async {
        guard
          let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
          ).first
        else {
          return
        }

        let fileURL = documentsURL.appendingPathComponent("preview-debug.log")
        let data = Data(message.utf8)

        if FileManager.default.fileExists(atPath: fileURL.path) == false {
          try? data.write(to: fileURL, options: .atomic)
          return
        }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
          defer { try? handle.close() }
          try? handle.seekToEnd()
          try? handle.write(contentsOf: data)
        }
      }
    }
  #else
    private func logPreviewDebugSnapshot(context: String) {}
  #endif

  override func layoutSubviews() {
    super.layoutSubviews()
    requestPreviewPresentationUpdate(forceConnectionRefresh: false)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    let horizontalSizeClassChanged =
      previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass
    let verticalSizeClassChanged =
      previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass
    guard horizontalSizeClassChanged || verticalSizeClassChanged else { return }
    requestPreviewPresentationUpdate(forceConnectionRefresh: false)
  }

  // MARK: - Gesture Handlers

  @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
    let point = gesture.location(in: self)
    let focusPoint = previewLayerPointToDevicePoint(point)

    setFocusPoint(focusPoint)
    showFocusIndicator(at: point)
  }

  @objc private func handleExposureDoubleTap(_ gesture: UITapGestureRecognizer) {
    let point = gesture.location(in: self)
    let exposurePoint = previewLayerPointToDevicePoint(point)

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

// MARK: - AVCaptureVideoDataOutput Delegate Queue Tracking

private struct VideoOutputAssociatedKeys {
  static var delegateQueue: UInt8 = 0
}

extension AVCaptureVideoDataOutput {
  var trackedSampleBufferDelegateQueue: DispatchQueue? {
    objc_getAssociatedObject(self, &VideoOutputAssociatedKeys.delegateQueue) as? DispatchQueue
  }

  func setTrackedSampleBufferDelegate(
    _ delegate: AVCaptureVideoDataOutputSampleBufferDelegate?,
    queue: DispatchQueue?
  ) {
    setSampleBufferDelegate(delegate, queue: queue)
    objc_setAssociatedObject(
      self,
      &VideoOutputAssociatedKeys.delegateQueue,
      queue,
      .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
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

// MARK: - Text Overlay Management (Removed)
// 텍스트 오버레이는 SwiftUI 레이어의 TextOverlayDisplayView에서 처리됩니다.
// CameraPreviewUIView에서는 중복 구현을 제거했습니다.
