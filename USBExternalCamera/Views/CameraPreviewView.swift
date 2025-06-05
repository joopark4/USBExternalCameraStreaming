//
//  CameraPreviewView.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import SwiftUI
import AVFoundation
import HaishinKit

/// 카메라 미리보기를 표시하는 View
/// HaishinKit을 사용하여 RTMP 스트리밍 기능을 포함합니다.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var streamViewModel: LiveStreamViewModel?
    
    init(session: AVCaptureSession, streamViewModel: LiveStreamViewModel? = nil) {
        self.session = session
        self.streamViewModel = streamViewModel
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewUIView()
        view.captureSession = session
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let previewView = uiView as? CameraPreviewUIView else { return }
        previewView.captureSession = session
    }
}

/// 실제 카메라 미리보기를 담당하는 UIView
final class CameraPreviewUIView: UIView {
    
    // MARK: - Properties
    
    /// AVFoundation 카메라 미리보기 레이어
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    /// HaishinKit 미리보기 레이어 (스트리밍 중일 때 사용)
    private var hkPreviewLayer: UIView?
    
    /// 현재 캡처 세션
    var captureSession: AVCaptureSession? {
        didSet {
            updatePreviewLayer()
        }
    }
    
    /// 스트리밍 상태
    private var isStreaming: Bool = false
    
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
        
        // 컨트롤 오버레이 추가
        addSubview(controlOverlay)
        addSubview(streamingStatusView)
        
        setupConstraints()
        setupGestureRecognizers()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // 컨트롤 오버레이
            controlOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlOverlay.topAnchor.constraint(equalTo: topAnchor),
            controlOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // 스트리밍 상태 표시
            streamingStatusView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            streamingStatusView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            streamingStatusView.widthAnchor.constraint(equalToConstant: 200),
            streamingStatusView.heightAnchor.constraint(equalToConstant: 80)
        ])
    }
    
    private func setupGestureRecognizers() {
        // 포커스 탭 제스처
        let focusTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
        addGestureRecognizer(focusTapGesture)
        
        // 노출 조절 더블탭 제스처
        let exposureDoubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleExposureDoubleTap(_:)))
        exposureDoubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(exposureDoubleTapGesture)
        
        focusTapGesture.require(toFail: exposureDoubleTapGesture)
        
        // 줌 핀치 제스처
        let zoomPinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleZoomPinch(_:)))
        addGestureRecognizer(zoomPinchGesture)
    }
    
    // MARK: - Preview Layer Management
    
    private func updatePreviewLayer() {
        // 기존 레이어 제거
        previewLayer?.removeFromSuperlayer()
        hkPreviewLayer?.removeFromSuperview()
        
        guard let session = captureSession else { return }
        
        if isStreaming {
            setupHaishinKitPreview()
        } else {
            setupAVFoundationPreview(with: session)
        }
    }
    
    private func setupAVFoundationPreview(with session: AVCaptureSession) {
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
    }
    
    private func setupHaishinKitPreview() {
        // HaishinKit을 사용한 미리보기 (실제 구현 시 사용)
        let hkView = UIView(frame: bounds)
        hkView.backgroundColor = .black
        insertSubview(hkView, at: 0)
        hkPreviewLayer = hkView
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        hkPreviewLayer?.frame = bounds
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
}

// MARK: - CameraControlOverlayDelegate

extension CameraPreviewUIView: CameraControlOverlayDelegate {
    func didTapRecord() {
        // 녹화 기능은 제외
        print("📹 Recording functionality not implemented")
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
            statsLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
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
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 1.0
            self.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        }) { _ in
            UIView.animate(withDuration: 0.3, animations: {
                self.alpha = 0.8
                self.transform = CGAffineTransform.identity
            }) { _ in
                UIView.animate(withDuration: 1.0, animations: {
                    self.alpha = 0
                }, completion: { _ in
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
            sunIcon.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    func animate(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 1.0
            self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            UIView.animate(withDuration: 0.3, animations: {
                self.alpha = 0.8
                self.transform = CGAffineTransform.identity
            }) { _ in
                UIView.animate(withDuration: 1.0, animations: {
                    self.alpha = 0
                }, completion: { _ in
                    completion()
                })
            }
        }
    }
} 