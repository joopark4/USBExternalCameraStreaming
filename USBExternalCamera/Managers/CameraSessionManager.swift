import AVFoundation
import Foundation
import LiveStreamingCore

/// 카메라 전환 완료를 알리는 델리게이트
public protocol CameraSwitchDelegate: AnyObject {
    /// 카메라 전환이 완료되었을 때 호출
    func didSwitchCamera(to camera: AVCaptureDevice, session: AVCaptureSession) async
}

/// 카메라 세션 관리 프로토콜
/// - 카메라 세션 관련 기능을 추상화하여 테스트와 확장성을 높임
/// - AnyObject: 클래스 타입만 프로토콜을 채택할 수 있도록 제한
public protocol CameraSessionManaging: AnyObject {
    /// 현재 카메라 세션
    /// - 카메라 입력과 출력을 관리하는 AVCaptureSession 인스턴스
    var captureSession: AVCaptureSession { get }
    
    /// 카메라 프레임 델리게이트
    var frameDelegate: CameraFrameDelegate? { get set }
    
    /// 카메라 전환 델리게이트
    var switchDelegate: CameraSwitchDelegate? { get set }
    
    /// 특정 카메라로 전환
    /// - camera: 전환할 카메라 디바이스
    /// - 기존 입력을 제거하고 새로운 카메라 입력을 추가
    func switchToCamera(_ camera: CameraDevice)
    
    /// 카메라 세션 중지
    /// - 비동기로 실행되어 세션 종료를 안전하게 처리
    /// - 세션 큐에서 실행되어 스레드 안전성 보장
    func stopSession() async
}

/// 카메라 세션 관리를 담당하는 클래스
/// - AVCaptureSession을 관리하고 카메라 전환을 처리
/// - 비디오 데이터 출력을 처리하기 위한 델리게이트 구현
public final class CameraSessionManager: NSObject, CameraSessionManaging, @unchecked Sendable {
    /// 카메라 캡처 세션
    /// - 카메라 입력과 출력을 관리하는 핵심 객체
    public let captureSession = AVCaptureSession()
    
    /// 카메라 프레임 델리게이트
    /// - 캡처된 비디오 프레임을 스트리밍 매니저로 전달
    public weak var frameDelegate: CameraFrameDelegate?
    
    /// 카메라 전환 델리게이트
    public weak var switchDelegate: CameraSwitchDelegate?
    
    /// 현재 연결된 비디오 입력
    /// - 카메라 전환 시 이전 입력을 제거하고 새로운 입력을 설정
    private var videoInput: AVCaptureDeviceInput?
    
    /// 비디오 데이터 출력
    /// - 캡처된 비디오 프레임을 처리하기 위한 출력 설정
    private let videoOutput = AVCaptureVideoDataOutput()
    
    /// 세션 작업을 위한 전용 큐
    /// - 카메라 작업은 메인 스레드에서 실행하면 안 되므로 별도 큐 사용
    /// - 스레드 안전성 보장을 위해 모든 세션 작업은 이 큐에서 실행
    private let sessionQueue = DispatchQueue(label: "com.heavyarm.sessionQueue")
    
    /// 프레임 통계 (sessionQueue에서 단일 스레드로 갱신)
    private var frameCount: Int = 0
    private var lastFrameTime: CFTimeInterval = 0
    
    /// 현재 적용된 스트리밍 설정 (중복 설정 방지용 캐시)
    private var currentStreamingSettings: LiveStreamSettings?
    
    /// 초기화 및 기본 세션 설정
    /// - 세션 프리셋과 비디오 출력을 초기화
    public override init() {
        super.init()
        setupCaptureSession()
    }
    
    /// 카메라 세션 초기 설정
    /// - 세션 프리셋 설정
    /// - 비디오 출력 설정
    /// - 세션 큐에서 안전하게 실행
    private func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            
            // 기본 고품질 비디오 프리셋 설정 (스트리밍 설정 없을 때)
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
            
            // 비디오 출력 설정
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            
            // 비디오 출력 포맷 설정 (스트리밍에 최적화)
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            // 프레임 드랍 허용 (성능 향상)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
                logInfo("✅ 비디오 출력이 카메라 세션에 추가되었습니다", category: .camera)
            } else {
                logError("❌ 비디오 출력을 카메라 세션에 추가할 수 없습니다", category: .camera)
            }
            
            self.captureSession.commitConfiguration()
            logInfo("🎥 카메라 세션이 초기화되었습니다", category: .camera)
        }
    }
    
    /// 스트리밍 설정에 맞춰 카메라 하드웨어 품질 최적화
    /// - 해상도, 프레임레이트를 스트리밍 설정에 맞춰 조정
    /// - 불필요한 업/다운스케일링 방지로 성능 향상
    public func optimizeForStreamingSettings(_ settings: LiveStreamSettings) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 동일한 설정이면 재적용 생략
            if let current = self.currentStreamingSettings,
               current.videoWidth == settings.videoWidth &&
               current.videoHeight == settings.videoHeight &&
               current.frameRate == settings.frameRate {
                return
            }
            
            self.currentStreamingSettings = settings
            
            logInfo("🎛️ 스트리밍 설정에 맞춰 카메라 하드웨어 최적화 시작", category: .camera)
            logInfo("  📺 목표: \(settings.videoWidth)×\(settings.videoHeight) @ \(settings.frameRate)fps", category: .camera)
            
            self.captureSession.beginConfiguration()
            
            // 1. 세션 프리셋 최적화 (해상도 기반)
            self.optimizeSessionPreset(for: settings)
            
            // 2. 카메라 디바이스 포맷 최적화 (고급 설정)
            self.optimizeCameraFormat(for: settings)
            
            self.captureSession.commitConfiguration()
            
            logInfo("✅ 카메라 하드웨어 최적화 완료", category: .camera)
        }
    }
    
    /// 스트리밍 설정에 맞는 세션 프리셋 선택
    /// - 지원 해상도: 480p, 720p, 1080p (정확한 해상도 매칭)
    /// - 미지원 해상도는 .high 프리셋으로 폴백
    private func optimizeSessionPreset(for settings: LiveStreamSettings) {
        let targetResolution = (width: settings.videoWidth, height: settings.videoHeight)

        // 해상도별 프리셋 매핑 (정확한 매칭만 지원)
        let optimalPreset: AVCaptureSession.Preset
        switch targetResolution {
        case (854, 480), (848, 480), (640, 480):
            optimalPreset = .vga640x480
            logInfo("📐 480p 스트리밍 → VGA 프리셋 적용", category: .camera)
            
        case (1280, 720):
            optimalPreset = .hd1280x720
            logInfo("📐 720p 스트리밍 → HD 프리셋 적용", category: .camera)
            
        case (1920, 1080):
            optimalPreset = .hd1920x1080
            logInfo("📐 1080p 스트리밍 → Full HD 프리셋 적용", category: .camera)
            
        case (3840, 2160):
            if self.captureSession.canSetSessionPreset(.hd4K3840x2160) {
                optimalPreset = .hd4K3840x2160
                logInfo("📐 4K 스트리밍 → 4K 프리셋 적용", category: .camera)
            } else {
                optimalPreset = .hd1920x1080
                logInfo("📐 4K 스트리밍 (지원안함) → Full HD 프리셋으로 대체", category: .camera)
            }
            
        default:
            optimalPreset = .high
            logInfo("📐 사용자 정의 해상도 → High 프리셋 적용", category: .camera)
        }
        
        // 프리셋 적용
        if self.captureSession.canSetSessionPreset(optimalPreset) {
            self.captureSession.sessionPreset = optimalPreset
            logInfo("✅ 세션 프리셋 적용: \(optimalPreset.rawValue)", category: .camera)
        } else {
            logWarning("⚠️ 프리셋 적용 실패, 기본 .high 유지", category: .camera)
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
        }
    }
    
    /// 카메라 디바이스 고급 포맷 최적화 (프레임레이트 등)
    private func optimizeCameraFormat(for settings: LiveStreamSettings) {
        guard let device = self.videoInput?.device else {
            logWarning("⚠️ 비디오 입력 디바이스를 찾을 수 없음", category: .camera)
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            // 프레임레이트 최적화
            self.optimizeFrameRate(device: device, targetFPS: settings.frameRate)
            
            // 기타 카메라 설정 최적화
            self.optimizeCameraSettings(device: device, settings: settings)
            
            device.unlockForConfiguration()
            
        } catch {
            logError("❌ 카메라 디바이스 설정 실패: \(error.localizedDescription)", category: .camera)
        }
    }
    
    /// 프레임레이트 최적화
    private func optimizeFrameRate(device: AVCaptureDevice, targetFPS: Int) {
        let targetFrameRate = Double(targetFPS)
        
        // 현재 포맷에서 지원하는 프레임레이트 범위 확인
        let frameRateRanges = device.activeFormat.videoSupportedFrameRateRanges
        
        for range in frameRateRanges {
            if targetFrameRate >= range.minFrameRate && targetFrameRate <= range.maxFrameRate {
                let frameDuration = CMTimeMake(value: 1, timescale: CMTimeScale(targetFPS))
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
                
                logInfo("🎬 프레임레이트 최적화: \(targetFPS)fps 적용", category: .camera)
                return
            }
        }
        
        // 목표 프레임레이트가 지원되지 않으면 가장 가까운 값 사용
        if let closestRange = frameRateRanges.min(by: { abs($0.maxFrameRate - targetFrameRate) < abs($1.maxFrameRate - targetFrameRate) }) {
            let adjustedFPS = min(targetFrameRate, closestRange.maxFrameRate)
            let frameDuration = CMTimeMake(value: 1, timescale: CMTimeScale(adjustedFPS))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            
            logInfo("🎬 프레임레이트 조정: \(Int(adjustedFPS))fps (목표 \(targetFPS)fps)", category: .camera)
        }
    }
    
    /// 기타 카메라 설정 최적화
    private func optimizeCameraSettings(device: AVCaptureDevice, settings: LiveStreamSettings) {
        // 고해상도 스트리밍을 위한 카메라 최적화
        if settings.videoWidth >= 1920 && settings.videoHeight >= 1080 {
            // 1080p 이상: 안정성 우선 설정
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            logInfo("🔧 고해상도 모드: 연속 자동 포커스/노출 활성화", category: .camera)
            
        } else {
            // 720p 이하: 성능 우선 설정
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
            
            logInfo("🔧 표준 해상도 모드: 자동 포커스/노출 설정", category: .camera)
        }
        
        // 화이트 밸런스 최적화
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
    }
    
    /// 현재 적용된 카메라 하드웨어 설정 정보 반환
    public func getCurrentHardwareSettings() -> (resolution: String, frameRate: String, preset: String) {
        let preset = self.captureSession.sessionPreset.rawValue
        
        let frameRate: String
        if let device = self.videoInput?.device {
            let currentFPS = 1.0 / CMTimeGetSeconds(device.activeVideoMinFrameDuration)
            frameRate = String(format: "%.0f fps", currentFPS)
        } else {
            frameRate = NSLocalizedString("unknown", comment: "알 수 없음")
        }
        
        // 세션 프리셋에서 대략적인 해상도 추정
        let resolution: String
        switch self.captureSession.sessionPreset {
        case .vga640x480:
            resolution = "640×480"
        case .hd1280x720:
            resolution = "1280×720"
        case .hd1920x1080:
            resolution = "1920×1080"
        case .hd4K3840x2160:
            resolution = "3840×2160"
        case .high:
            resolution = "High (가변)"
        default:
            resolution = NSLocalizedString("unknown", comment: "알 수 없음")
        }
        
        return (resolution, frameRate, preset)
    }
    
    /// 카메라 전환 처리
    /// - 기존 입력 제거
    /// - 새로운 카메라 입력 추가
    /// - 세션 재시작
    /// - 세션 큐에서 안전하게 실행
    public func switchToCamera(_ camera: CameraDevice) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            logInfo("🔄 카메라 전환 시작: \(camera.name)", category: .camera)
            
            // 개선: 세션 중지 없이 즉시 입력 교체하여 지연 최소화
            self.captureSession.beginConfiguration()
            
            // 기존 입력 제거
            if let currentInput = self.videoInput {
                self.captureSession.removeInput(currentInput)
                logInfo("🗑️ 이전 카메라 입력 제거됨", category: .camera)
            }
            
            // 새로운 카메라 입력 추가
            do {
                let input = try AVCaptureDeviceInput(device: camera.device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.videoInput = input
                    logInfo("✅ 새 카메라 입력 추가됨: \(camera.name)", category: .camera)
                } else {
                    logError("❌ 카메라 입력을 추가할 수 없습니다: \(camera.name)", category: .camera)
                }
            } catch {
                logError("❌ 카메라 입력 생성 실패: \(error.localizedDescription)", category: .camera)
            }
            
            self.captureSession.commitConfiguration()
            
            // 세션이 중지되어 있는 경우에만 재시작
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
                logInfo("▶️ 카메라 세션이 시작되었습니다", category: .camera)
            }
            
            // 프레임 카운터 리셋
            self.frameCount = 0
            self.lastFrameTime = CACurrentMediaTime()
            
            logInfo("🎥 카메라 전환 완료: \(camera.name)", category: .camera)
            
            // 카메라 전환 완료를 델리게이트에 알림 (스트리밍 동기화용)
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.switchDelegate?.didSwitchCamera(to: camera.device, session: self.captureSession)
            }
        }
    }
    
    /// 카메라 세션 중지
    /// - 비동기로 실행되어 세션 종료를 안전하게 처리
    /// - 세션 큐에서 실행되어 스레드 안전성 보장
    public func stopSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                    logInfo("⏹️ 카메라 세션이 중지되었습니다", category: .camera)
                }
                continuation.resume()
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
/// 비디오 프레임 데이터 처리
/// - 캡처된 비디오 프레임을 처리하기 위한 델리게이트 메서드
extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// 비디오 프레임 데이터 수신
    /// - output: 데이터를 출력한 AVCaptureOutput
    /// - sampleBuffer: 캡처된 비디오 프레임 데이터
    /// - connection: 캡처 연결 정보
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 프레임 통계 업데이트 (성능 모니터링)
        frameCount += 1
        let currentTime = CACurrentMediaTime()
        
        // FPS 계산 (1초마다 갱신)
        if currentTime - lastFrameTime >= 1.0 {
            let fps = Double(frameCount) / (currentTime - lastFrameTime)

            // 로깅만 백그라운드 큐에서 처리 (캡처 콜백 부하 최소화)
            DispatchQueue.global(qos: .utility).async {
                logDebug("📊 카메라 FPS: \(String(format: "%.1f", fps))", category: .camera)
            }
            
            frameCount = 0
            lastFrameTime = currentTime
        }
        
        // 프레임을 스트리밍 매니저로 전달
        frameDelegate?.didReceiveVideoFrame(sampleBuffer, from: connection)
    }
    
    /// 프레임 드랍 발생 시 호출
    nonisolated public func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 드롭 이벤트 자체는 흔하지 않다면 처리량 초과 또는 포맷 미스매치 의심 포인트
        Task { @Sendable in
            logWarning("⚠️ 비디오 프레임이 드랍되었습니다", category: .camera)
        }
    }
}
