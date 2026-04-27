import SwiftUI
import AVFoundation

/// 권한 관리를 위한 ViewModel.
/// MVVM 패턴에서 View와 Model(PermissionManager) 사이의 중간층 역할을 담당합니다.
/// 이 앱은 카메라/마이크 권한만 사용합니다 (사진첩 저장 기능 미사용).
@MainActor
final class PermissionViewModel: ObservableObject {

    // MARK: - Dependencies

    /// 권한 매니저 - 실제 권한 관련 비즈니스 로직을 담당
    let permissionManager: PermissionManager

    // MARK: - Published Properties (UI State)

    /// 카메라 권한 상태
    @Published var cameraStatus: PermissionStatus

    /// 마이크 권한 상태
    @Published var microphoneStatus: PermissionStatus

    /// 모든 필수 권한이 허용되었는지 여부
    @Published var areAllPermissionsGranted: Bool = false

    // MARK: - Initialization

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
        self.cameraStatus = permissionManager.cameraStatus
        self.microphoneStatus = permissionManager.microphoneStatus

        // 초기 권한 상태 업데이트
        updateAllPermissionsStatus()
    }

    // MARK: - Public Methods (User Actions)

    /// 카메라 권한 요청
    func requestCameraPermission() async {
        await permissionManager.requestCameraPermission()
        cameraStatus = permissionManager.cameraStatus
        updateAllPermissionsStatus()
    }

    /// 마이크 권한 요청
    func requestMicrophonePermission() async {
        await permissionManager.requestMicrophonePermission()
        microphoneStatus = permissionManager.microphoneStatus
        updateAllPermissionsStatus()
    }

    // MARK: - Utility Methods

    /// 권한 상태를 사용자에게 표시할 텍스트로 변환
    func permissionStatusText(_ status: PermissionStatus) -> String {
        switch status {
        case .notDetermined:
            return NSLocalizedString("permission_status_not_determined", comment: "권한 상태 미결정")
        case .restricted:
            return NSLocalizedString("permission_status_restricted", comment: "권한 상태 제한됨")
        case .denied:
            return NSLocalizedString("permission_status_denied", comment: "권한 상태 거부됨")
        case .authorized:
            return NSLocalizedString("permission_status_authorized", comment: "권한 상태 허용됨")
        }
    }

    /// 권한이 거부된 항목 목록 반환
    var deniedPermissions: [String] {
        var denied: [String] = []
        if cameraStatus == .denied {
            denied.append(NSLocalizedString("permission_camera", comment: "카메라 권한"))
        }
        if microphoneStatus == .denied {
            denied.append(NSLocalizedString("permission_microphone", comment: "마이크 권한"))
        }
        return denied
    }

    /// 권한 설정 가이드 메시지 생성
    var permissionGuideMessage: String {
        if deniedPermissions.isEmpty {
            return NSLocalizedString("all_permissions_granted", comment: "모든 권한 허용됨")
        } else {
            return String(format: NSLocalizedString("permissions_denied_message", comment: "권한 거부 메시지"),
                         deniedPermissions.joined(separator: ", "))
        }
    }

    // MARK: - Private Methods

    /// 모든 권한 상태를 확인하여 areAllPermissionsGranted 업데이트
    private func updateAllPermissionsStatus() {
        areAllPermissionsGranted = cameraStatus == .authorized &&
                                  microphoneStatus == .authorized
    }
}