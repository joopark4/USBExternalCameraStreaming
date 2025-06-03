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
        discoverExternalCameras()
        
        // 첫 번째 카메라 자동 선택
        if let firstCamera = externalCameras.first {
            switchToCamera(firstCamera)
        }
    }

    /// 외장 카메라 디바이스 검색
    /// - AVCaptureDevice.DiscoverySession을 사용하여 외장 카메라 검색
    /// - 검색된 카메라를 CameraDevice 모델로 변환하여 저장
    private func discoverExternalCameras() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )

        externalCameras = discoverySession.devices.map { CameraDevice(device: $0) }
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
    
    /// 소멸자
    /// - 세션 정리는 명시적으로 호출해야 함
    /// - 비동기 작업이 포함되어 있어 deinit에서 직접 호출 불가
    deinit {
        // 세션 정리는 명시적으로 호출해야 합니다.
    }
} 
