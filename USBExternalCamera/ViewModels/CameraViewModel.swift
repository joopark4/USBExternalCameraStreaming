import AVFoundation
import Combine
import Foundation
import SwiftUI

/// 카메라 관련 기능을 관리하는 뷰모델
/// - @MainActor: UI 관련 작업은 메인 스레드에서 실행
/// - ObservableObject: SwiftUI 뷰와 데이터 바인딩을 위한 프로토콜
@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    /// 연결된 외장 카메라 디바이스 목록
    /// - @Published: 변경 시 SwiftUI 뷰에 자동으로 알림
    /// - private(set): 외부에서 읽기만 가능하고 수정은 불가능
    @Published private(set) var externalCameras: [CameraDevice] = []
    
    /// 연결된 내장 카메라 디바이스 목록
    /// - @Published: 변경 시 SwiftUI 뷰에 자동으로 알림
    /// - private(set): 외부에서 읽기만 가능하고 수정은 불가능
    @Published private(set) var builtInCameras: [CameraDevice] = []
    
    /// 현재 선택된 카메라 디바이스
    /// - @Published: 변경 시 SwiftUI 뷰에 자동으로 알림
    /// - 선택된 카메라가 변경될 때마다 UI가 자동으로 업데이트
    @Published var selectedCamera: CameraDevice?
    
    /// 카메라 세션 매니저
    /// - 카메라 세션 관리 및 카메라 전환 처리
    private let sessionManager: CameraSessionManager
    
    /// 카메라 세션 접근자
    /// - 현재 카메라 세션에 대한 읽기 전용 접근 제공
    var captureSession: AVCaptureSession {
        sessionManager.captureSession
    }

    /// 초기화
    /// - 카메라 세션 매니저 생성
    /// - 외장 카메라 검색
    /// - 첫 번째 카메라 자동 선택
    override init() {
        self.sessionManager = CameraSessionManager()
        super.init()
        
        // 비동기 초기화를 위해 Task 사용
        Task {
            await discoverCameras()
            
            // 첫 번째 카메라 자동 선택
            if let firstCamera = builtInCameras.first ?? externalCameras.first {
                switchToCamera(firstCamera)
            }
        }
        
        // 외장 카메라 연결 상태 모니터링
        setupDeviceNotifications()
    }

    /// 외장 카메라 연결 상태 모니터링 설정
    private func setupDeviceNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnected),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceDisconnected),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }
    
    /// 외장 카메라 연결 시 호출
    @objc private func handleDeviceConnected(_ notification: Notification) {
        Task {
            await discoverCameras()
        }
    }
    
    /// 외장 카메라 연결 해제 시 호출
    @objc private func handleDeviceDisconnected(_ notification: Notification) {
        Task {
            // 현재 선택된 카메라가 외장 카메라인지 확인
            if let selectedCamera = selectedCamera,
               externalCameras.contains(where: { $0.id == selectedCamera.id }) {
                // 외장 카메라가 연결 해제된 경우 기본 카메라로 전환
                await discoverCameras()
                if let firstBuiltInCamera = builtInCameras.first {
                    switchToCamera(firstBuiltInCamera)
                } else {
                    self.selectedCamera = nil
                }
            } else {
                // 선택된 카메라가 외장 카메라가 아닌 경우 목록만 업데이트
                await discoverCameras()
            }
        }
    }

    /// 카메라 디바이스 검색
    /// - AVCaptureDevice.DiscoverySession을 사용하여 외장 및 내장 카메라 검색
    /// - 검색된 카메라를 CameraDevice 모델로 변환하여 저장
    private func discoverCameras() async {
        // 내장 카메라 검색
        let builtInDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        // 외장 카메라 검색
        let externalDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )

        // 메인 스레드에서 UI 업데이트
        await MainActor.run {
            builtInCameras = builtInDiscoverySession.devices.map { CameraDevice(device: $0) }
            externalCameras = externalDiscoverySession.devices.map { CameraDevice(device: $0) }
        }
    }

    /// 선택된 카메라로 전환
    /// - sessionManager를 통해 카메라 전환 처리
    /// - 선택된 카메라 상태 업데이트
    func switchToCamera(_ camera: CameraDevice) {
        sessionManager.switchToCamera(camera)
        selectedCamera = camera
    }

    /// 카메라 세션 중지
    /// - @MainActor: 메인 스레드에서 실행
    /// - sessionManager를 통해 세션 안전하게 중지
    @MainActor
    func stopSession() async {
        await sessionManager.stopSession()
    }
    
    /// 카메라 리스트 새로고침
    func refreshCameraList() async {
        let currentSelectedId = selectedCamera?.id
        
        // 현재 카메라 목록 저장
        let currentBuiltInCameras = builtInCameras
        let currentExternalCameras = externalCameras
        
        // 카메라 목록 새로고침
        await discoverCameras()
        
        // 이전에 선택된 카메라가 있었다면 다시 선택
        if let selectedId = currentSelectedId {
            if let camera = builtInCameras.first(where: { $0.id == selectedId }) {
                selectedCamera = camera
            } else if let camera = externalCameras.first(where: { $0.id == selectedId }) {
                selectedCamera = camera
            } else {
                // 이전에 선택된 카메라를 찾을 수 없는 경우
                // 외장 카메라가 연결 해제된 경우 기본 카메라로 전환
                if currentExternalCameras.contains(where: { $0.id == selectedId }) {
                    // 이전에 선택된 카메라가 외장 카메라였고, 현재 연결이 끊어진 경우
                    if let firstBuiltInCamera = builtInCameras.first {
                        switchToCamera(firstBuiltInCamera)
                    } else {
                        selectedCamera = nil
                    }
                } else {
                    selectedCamera = nil
                }
            }
        }
    }
    
    /// 소멸자
    /// - 세션 정리는 명시적으로 호출해야 함
    /// - 비동기 작업이 포함되어 있어 deinit에서 직접 호출 불가
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 
