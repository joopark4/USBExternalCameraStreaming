import AVFoundation
import Foundation

/// 카메라 세션 관리 프로토콜
/// - 카메라 세션 관련 기능을 추상화하여 테스트와 확장성을 높임
/// - AnyObject: 클래스 타입만 프로토콜을 채택할 수 있도록 제한
public protocol CameraSessionManaging: AnyObject {
    /// 현재 카메라 세션
    /// - 카메라 입력과 출력을 관리하는 AVCaptureSession 인스턴스
    var captureSession: AVCaptureSession { get }
    
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
public final class CameraSessionManager: NSObject, CameraSessionManaging {
    /// 카메라 캡처 세션
    /// - 카메라 입력과 출력을 관리하는 핵심 객체
    public let captureSession = AVCaptureSession()
    
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
            
            // 고품질 비디오 프리셋 설정
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
            
            // 비디오 출력 설정
            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }
            
            self.captureSession.commitConfiguration()
        }
    }
    
    /// 카메라 전환 처리
    /// - 기존 입력 제거
    /// - 새로운 카메라 입력 추가
    /// - 세션 재시작
    /// - 세션 큐에서 안전하게 실행
    public func switchToCamera(_ camera: CameraDevice) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 실행 중인 세션 중지
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            
            self.captureSession.beginConfiguration()
            
            // 기존 입력 제거
            if let currentInput = self.videoInput {
                self.captureSession.removeInput(currentInput)
            }
            
            // 새로운 카메라 입력 추가
            do {
                let input = try AVCaptureDeviceInput(device: camera.device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.videoInput = input
                }
            } catch {
                print("카메라 전환 중 오류 발생: \(error.localizedDescription)")
            }
            
            self.captureSession.commitConfiguration()
            
            // 세션 재시작
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
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
        // 여기서 프레임 데이터를 처리할 수 있습니다.
        // 예: 이미지 처리, 스트리밍 등
    }
} 