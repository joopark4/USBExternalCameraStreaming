//
//  CameraPreviewView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import HaishinKit
import SwiftUI

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
        print("🔄 [CameraPreview] 캡처 세션 변경 감지 - 업데이트")
        previewView.captureSession = session
      }

      if managerChanged {
        print("🔄 [CameraPreview] HaishinKit 매니저 변경 감지 - 업데이트")
        previewView.haishinKitManager = haishinKitManager
      }

      // 프리뷰 새로고침은 하지 않음 (안정성 향상)
      print("🔄 [CameraPreview] 업데이트 완료 - 프리뷰 새로고침 건너뜀")
    }
  }

  // MARK: - Screen Capture Control Methods

  /// 화면 캡처 송출 시작 (외부에서 호출 가능)
  func startScreenCapture() {
    // UIViewRepresentable에서 UIView에 접근하는 방법이 제한적이므로
    // HaishinKitManager를 통해 제어하는 것을 권장
    print("🎬 [CameraPreviewView] 화면 캡처 요청됨 - HaishinKitManager 사용 권장")
  }

  /// 화면 캡처 송출 중지 (외부에서 호출 가능)
  func stopScreenCapture() {
    print("🎬 [CameraPreviewView] 화면 캡처 중지 요청됨")

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
        print("🎥 [CameraPreview] 초기 캡처 세션 설정 - 프리뷰 레이어 생성")
        updatePreviewLayer()
      } else if oldValue !== captureSession {
        print("🎥 [CameraPreview] 캡처 세션 변경 감지 - 프리뷰 레이어 업데이트")
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
    setupWatermark()
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

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleTestWatermarkCapture),
      name: NSNotification.Name("testWatermarkCapture"),
      object: nil
    )
  }

  @objc private func handleStartScreenCapture() {
    print("📩 [CameraPreview] 화면 캡처 시작 notification 수신")
    startScreenCapture()
  }

  @objc private func handleStopScreenCapture() {
    print("📩 [CameraPreview] 화면 캡처 중지 notification 수신")
    stopScreenCapture()
  }

  @objc private func handleTestWatermarkCapture() {
    print("🧪 [CameraPreview] 워터마크 캡처 테스트 notification 수신")

    // 즉시 한 번의 프레임 캡처 실행
    DispatchQueue.main.async { [weak self] in
      self?.captureCurrentFrame()
    }
  }

  private func setupWatermark() {
    // 중앙 대형 워터마크 생성
    let watermarkContainer = UIView()
    watermarkContainer.backgroundColor = UIColor.clear
    watermarkContainer.translatesAutoresizingMaskIntoConstraints = false
    watermarkContainer.tag = 8888  // 워터마크 식별용 태그

    // AAA TEST 메인 워터마크
    let mainWatermark = UILabel()
    mainWatermark.text = "AAA TEST"
    mainWatermark.font = UIFont.boldSystemFont(ofSize: 48)
    mainWatermark.textColor = .white
    mainWatermark.backgroundColor = UIColor.red.withAlphaComponent(0.9)
    mainWatermark.textAlignment = .center
    mainWatermark.layer.cornerRadius = 16
    mainWatermark.layer.borderWidth = 4
    mainWatermark.layer.borderColor = UIColor.yellow.cgColor
    mainWatermark.clipsToBounds = true
    mainWatermark.translatesAutoresizingMaskIntoConstraints = false

    // 그림자 효과
    mainWatermark.layer.shadowColor = UIColor.black.cgColor
    mainWatermark.layer.shadowOffset = CGSize(width: 2, height: 2)
    mainWatermark.layer.shadowRadius = 4
    mainWatermark.layer.shadowOpacity = 0.8

    // 서브 워터마크
    let subWatermark = UILabel()
    subWatermark.text = "🎬 SCREEN CAPTURE TEST"
    subWatermark.font = UIFont.boldSystemFont(ofSize: 20)
    subWatermark.textColor = .yellow
    subWatermark.backgroundColor = UIColor.blue.withAlphaComponent(0.8)
    subWatermark.textAlignment = .center
    subWatermark.layer.cornerRadius = 12
    subWatermark.clipsToBounds = true
    subWatermark.translatesAutoresizingMaskIntoConstraints = false

    // 라이브 표시
    let liveIndicator = UILabel()
    liveIndicator.text = "● LIVE STREAMING ●"
    liveIndicator.font = UIFont.boldSystemFont(ofSize: 16)
    liveIndicator.textColor = .green
    liveIndicator.backgroundColor = UIColor.black.withAlphaComponent(0.7)
    liveIndicator.textAlignment = .center
    liveIndicator.layer.cornerRadius = 8
    liveIndicator.clipsToBounds = true
    liveIndicator.translatesAutoresizingMaskIntoConstraints = false

    // 우하단 코너 워터마크
    let cornerWatermark = UILabel()
    cornerWatermark.text = "📱 CAPTURE\\nON AIR"
    cornerWatermark.numberOfLines = 2
    cornerWatermark.font = UIFont.boldSystemFont(ofSize: 14)
    cornerWatermark.textColor = .white
    cornerWatermark.backgroundColor = UIColor.black.withAlphaComponent(0.6)
    cornerWatermark.textAlignment = .center
    cornerWatermark.layer.cornerRadius = 8
    cornerWatermark.clipsToBounds = true
    cornerWatermark.translatesAutoresizingMaskIntoConstraints = false

    // 컨테이너에 추가
    watermarkContainer.addSubview(mainWatermark)
    watermarkContainer.addSubview(subWatermark)
    watermarkContainer.addSubview(liveIndicator)
    watermarkContainer.addSubview(cornerWatermark)

    // 메인 뷰에 추가
    addSubview(watermarkContainer)

    // 제약 조건 설정
    NSLayoutConstraint.activate([
      // 컨테이너
      watermarkContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
      watermarkContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
      watermarkContainer.topAnchor.constraint(equalTo: topAnchor),
      watermarkContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

      // 메인 워터마크 (중앙)
      mainWatermark.centerXAnchor.constraint(equalTo: watermarkContainer.centerXAnchor),
      mainWatermark.centerYAnchor.constraint(equalTo: watermarkContainer.centerYAnchor),
      mainWatermark.widthAnchor.constraint(equalToConstant: 300),
      mainWatermark.heightAnchor.constraint(equalToConstant: 80),

      // 서브 워터마크 (메인 워터마크 아래)
      subWatermark.centerXAnchor.constraint(equalTo: mainWatermark.centerXAnchor),
      subWatermark.topAnchor.constraint(equalTo: mainWatermark.bottomAnchor, constant: 16),
      subWatermark.widthAnchor.constraint(equalToConstant: 350),
      subWatermark.heightAnchor.constraint(equalToConstant: 40),

      // 라이브 표시 (서브 워터마크 아래)
      liveIndicator.centerXAnchor.constraint(equalTo: subWatermark.centerXAnchor),
      liveIndicator.topAnchor.constraint(equalTo: subWatermark.bottomAnchor, constant: 12),
      liveIndicator.widthAnchor.constraint(equalToConstant: 200),
      liveIndicator.heightAnchor.constraint(equalToConstant: 30),

      // 코너 워터마크 (우하단)
      cornerWatermark.trailingAnchor.constraint(
        equalTo: watermarkContainer.trailingAnchor, constant: -16),
      cornerWatermark.bottomAnchor.constraint(
        equalTo: watermarkContainer.bottomAnchor, constant: -20),
      cornerWatermark.widthAnchor.constraint(equalToConstant: 80),
      cornerWatermark.heightAnchor.constraint(equalToConstant: 50),
    ])

    print("🎨 [CameraPreview] 워터마크 UIView 추가 완료")
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

    print("🔴 [CameraPreview] 스트리밍 표시 추가")

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
      print("🔴 [CameraPreview] 스트리밍 표시 제거")
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
      print("❌ [CameraPreview] 캡처 세션이 없어 프리뷰 보호 불가")
      return
    }

    // 프리뷰 레이어가 없거나 세션이 다르면 복구
    if previewLayer == nil || previewLayer?.session !== session {
      print("🔧 [CameraPreview] 프리뷰 레이어 복구 필요 - 재생성")
      setupAVFoundationPreview(with: session)
    } else if let layer = previewLayer {
      // 프리뷰 레이어가 슈퍼레이어에서 제거되었으면 다시 추가
      if layer.superlayer == nil {
        print("🔧 [CameraPreview] 프리뷰 레이어 다시 추가")
        self.layer.insertSublayer(layer, at: 0)
      }

      // 프레임 업데이트
      layer.frame = bounds
    }

    print("✅ [CameraPreview] 프리뷰 레이어 보호 완료")
  }

  /// 비디오 프레임 모니터링 설정 (통계 목적)
  private func setupVideoMonitoring(with session: AVCaptureSession) {
    print("📹 [CameraPreview] 비디오 프레임 모니터링 설정")

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
      print("✅ [CameraPreview] 비디오 프레임 모니터링 설정 완료")
    } else {
      print("❌ [CameraPreview] 비디오 프레임 모니터링 설정 실패")
    }
  }

  /// 비디오 프레임 모니터링 해제
  private func removeVideoMonitoring() {
    guard let session = captureSession, let output = videoOutput else { return }

    print("📹 [CameraPreview] 비디오 프레임 모니터링 해제")
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
        print("🎥 [CameraPreview] 스트리밍 시작됨 - 스트리밍 표시 추가 및 프리뷰 보호")

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
        print("🎥 [CameraPreview] 스트리밍 종료됨 - 스트리밍 표시 제거")

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
    print("📊 [CameraPreview] 스트리밍 상태 뷰 업데이트 건너뜀 (중복 방지)")
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
    print("🔄 [CameraPreview] 프리뷰 레이어 새로고침 시작 (스트리밍: \(isStreaming))")

    guard let session = captureSession else {
      print("❌ [CameraPreview] 캡처 세션이 없어 새로고침 실패")
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

      print("🎥 [CameraPreview] AVFoundation 프리뷰 설정")
      self.setupAVFoundationPreview(with: session)

      if self.isStreaming {
        print("🎥 [CameraPreview] 스트리밍 표시 추가")
        self.addStreamingIndicator()
      }

      print("✅ [CameraPreview] 프리뷰 레이어 새로고침 완료")
    }
  }

  private func setupAVFoundationPreview(with session: AVCaptureSession) {
    print("🎥 [CameraPreview] AVFoundation 프리뷰 레이어 설정 중...")

    let newPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
    newPreviewLayer.frame = bounds
    newPreviewLayer.videoGravity = .resizeAspect

    if #available(iOS 17.0, *) {
      newPreviewLayer.connection?.videoRotationAngle = 0
    } else {
      newPreviewLayer.connection?.videoOrientation = .portrait
    }

    layer.insertSublayer(newPreviewLayer, at: 0)
    previewLayer = newPreviewLayer

    print("✅ [CameraPreview] AVFoundation 프리뷰 레이어 설정 완료")
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    // 프리뷰 레이어 프레임 업데이트
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.previewLayer?.frame = self.bounds
      self.hkPreviewLayer?.frame = self.bounds

      // 레이어가 올바르게 표시되도록 강제 레이아웃 업데이트
      if let layer = self.previewLayer {
        layer.setNeedsLayout()
        layer.layoutIfNeeded()
      }
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
      print("❌ Zoom adjustment failed: \(error)")
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
      print("❌ Focus adjustment failed: \(error)")
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
      print("❌ Exposure adjustment failed: \(error)")
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
      print("⚠️ [CameraPreview] 이미 화면 캡처가 진행 중입니다")
      return 
    }

    isScreenCapturing = true
    print("🎬 [CameraPreview] 화면 캡처 송출 시작 - 카메라 프레임 + UI 합성 모드")

    // 30fps로 화면 캡처 (1초에 30번 캡처)
    // 더 높은 프레임율은 성능에 영향을 줄 수 있으므로 30fps로 제한
    screenCaptureTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
      [weak self] _ in
      self?.captureCurrentFrame()
    }
    
    print("✅ [CameraPreview] 화면 캡처 타이머 시작됨 (30fps)")
  }
  
  /// 화면 캡처 송출 중지
  /// 
  /// 타이머를 중지하고 캡처된 프레임 데이터를 정리합니다.
  func stopScreenCapture() {
    guard isScreenCapturing else { 
      print("⚠️ [CameraPreview] 화면 캡처가 실행 중이지 않습니다")
      return 
    }

    isScreenCapturing = false
    screenCaptureTimer?.invalidate()
    screenCaptureTimer = nil
    
    // 메모리 정리: 최근 캡처된 카메라 프레임 제거
    frameProcessingQueue.async { [weak self] in
      self?.latestCameraFrame = nil
    }
    
    print("🎬 [CameraPreview] 화면 캡처 송출 중지 및 리소스 정리 완료")
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
        print("❌ [화면캡처] UIImage 렌더링 실패 - 프레임 스킵")
        return
      }
      
      print("✅ [화면캡처] 화면 렌더링 성공: \(capturedImage.size)")

      // Step 2: UIImage를 CVPixelBuffer로 변환 (HaishinKit 호환 포맷)
      guard let pixelBuffer = capturedImage.toCVPixelBuffer() else {
        print("❌ [화면캡처] CVPixelBuffer 변환 실패 - 프레임 스킵")
        return
      }
      
      let width = CVPixelBufferGetWidth(pixelBuffer)
      let height = CVPixelBufferGetHeight(pixelBuffer)
      print("✅ [화면캡처] CVPixelBuffer 변환 성공: \(width)x\(height)")

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
    let size = bounds.size
    guard size.width > 0 && size.height > 0 else { 
      print("❌ [렌더링] 유효하지 않은 뷰 크기: \(size)")
      return nil 
    }
    
    // 최근 카메라 프레임이 있는지 확인
    if let cameraFrame = latestCameraFrame {
      // 케이스 1: 카메라 프레임 + UI 합성 (권장 모드)
      print("🎥 [렌더링] 카메라 프레임 + UI 합성 모드")
      return renderCameraFrameWithUI(cameraFrame: cameraFrame, viewSize: size)
    } else {
      // 케이스 2: UI만 캡처 (카메라 프레임 없음 - 폴백 모드)
      print("📱 [렌더링] UI만 캡처 모드 (카메라 프레임 없음)")
      let renderer = UIGraphicsImageRenderer(bounds: bounds)
      return renderer.image { context in
        layer.render(in: context.cgContext)
      }
    }
  }
  
  /// 카메라 프레임과 UI를 합성하여 최종 이미지 생성
  /// 
  /// 이 메서드는 다음 3단계로 이미지를 합성합니다:
  /// 1. CVPixelBuffer(카메라 프레임)를 UIImage로 변환
  /// 2. UI 서브뷰들을 별도 이미지로 렌더링 (오버레이)
  /// 3. 카메라 이미지 위에 UI 오버레이를 합성
  ///
  /// **합성 방식:**
  /// - 카메라 이미지: aspect fit으로 배치 (비율 유지)
  /// - UI 오버레이: 전체 화면에 normal 블렌드 모드로 합성
  ///
  /// - Parameter cameraFrame: 실시간 카메라 프레임 (CVPixelBuffer)
  /// - Parameter viewSize: 최종 출력 이미지 크기
  /// - Returns: 합성된 최종 이미지 또는 nil
  private func renderCameraFrameWithUI(cameraFrame: CVPixelBuffer, viewSize: CGSize) -> UIImage? {
    
    // Step 1: 카메라 프레임을 UIImage로 변환
    guard let cameraImage = cameraFrame.toUIImage() else {
      print("❌ [합성] 카메라 프레임 → UIImage 변환 실패")
      return nil
    }
    print("✅ [합성] 카메라 이미지 변환 성공: \(cameraImage.size)")
    
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
    print("✅ [합성] UI 오버레이 생성 완료")
    
    // Step 3: 카메라 이미지와 UI 오버레이 합성
    let finalRenderer = UIGraphicsImageRenderer(size: viewSize)
    let compositeImage = finalRenderer.image { context in
      let rect = CGRect(origin: .zero, size: viewSize)
      
      // 3-1: 카메라 이미지를 뷰 크기에 맞게 그리기 (aspect fit 유지)
      // AVMakeRect: 원본 비율을 유지하면서 주어진 영역에 맞춤
      let aspectFitRect = AVMakeRect(aspectRatio: cameraImage.size, insideRect: rect)
      cameraImage.draw(in: aspectFitRect)
      
      // 3-2: UI 오버레이를 전체 화면에 합성
      // normal 블렌드 모드: 투명 영역은 그대로 두고 불투명 영역만 덮어씀
      uiOverlay.draw(in: rect, blendMode: .normal, alpha: 1.0)
    }
    
    print("✅ [합성] 최종 이미지 합성 완료: \(viewSize)")
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
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)

    print("📡 [전송] HaishinKit 프레임 전달: \(width)x\(height)")

    // HaishinKitManager를 통한 실제 프레임 전송
    if let manager = haishinKitManager {
      manager.sendManualFrame(pixelBuffer)

      // 성능 모니터링: 5초마다 전송 통계 출력
      if Int(Date().timeIntervalSince1970) % 5 == 0 {
        let stats = manager.getScreenCaptureStats()
        print("""
        📊 [화면캡처 통계] 
        - 현재 FPS: \(String(format: "%.1f", stats.currentFPS))
        - 성공 전송: \(stats.successCount)프레임
        - 실패 전송: \(stats.failureCount)프레임
        """)
      }
    } else {
      print("⚠️ [전송] HaishinKitManager 없음 - 프레임 전달 불가")
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
      print("❌ HaishinKitManager가 없음")
      return
    }

    print("🧪 화면 캡처 성능 테스트 시작...")
    manager.resetScreenCaptureStats()

    // 10프레임 연속 전송 테스트
    for i in 1...10 {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) { [weak self] in
        if let image = self?.renderToImage(),
          let pixelBuffer = image.toCVPixelBuffer()
        {
          manager.sendManualFrame(pixelBuffer)

          if i == 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
              let stats = manager.getScreenCaptureStats()
              print("🧪 테스트 완료:")
              print(stats.summary)
            }
          }
        }
      }
    }
  }

  /// 화면 캡처 상태 확인
  var isCapturingScreen: Bool {
    return isScreenCapturing
  }

  // MARK: - Usage Example & Notes

  /*
   사용 예시:
  
   1. 일반 카메라 스트리밍:
      try await haishinKitManager.startStreaming(with: settings, captureSession: captureSession)
  
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
    print("📹 Recording functionality not implemented")
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
        print("⚠️ [프레임저장] CMSampleBuffer에서 pixelBuffer 추출 실패")
        return 
      }
      
      // 백그라운드 큐에서 프레임 저장 (메인 스레드 블록킹 방지)
      frameProcessingQueue.async { [weak self] in
        self?.latestCameraFrame = pixelBuffer
        // print("✅ [프레임저장] 최신 카메라 프레임 업데이트됨") // 너무 빈번한 로그는 주석 처리
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
    print("⚠️ [CameraPreview] 비디오 프레임 드롭됨 - 성능 최적화 필요할 수 있음")
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
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
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
