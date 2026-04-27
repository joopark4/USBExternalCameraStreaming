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

    /// 시스템 권한 상태를 다시 읽어들여 published 프로퍼티 + `areAllPermissionsGranted` 를
    /// 즉시 동기화합니다. 카메라 세션이 켜지며 자동으로 떴던 시스템 다이얼로그에 사용자가
    /// 응답한 직후처럼, 앱이 명시적으로 `requestXxxPermission` 을 호출하지 않고 권한이 바뀐
    /// 케이스에서도 UI 가 최신 상태를 반영하도록 합니다.
    func refreshStatus() {
        permissionManager.checkPermissions()
        cameraStatus = permissionManager.cameraStatus
        microphoneStatus = permissionManager.microphoneStatus
        updateAllPermissionsStatus()
    }

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

    /// 아직 `.authorized` 가 아닌 권한 항목들의 사용자 표시 이름 목록.
    /// `.notDetermined`(아직 묻지 않음) 와 `.denied`/`.restricted` 모두 포함합니다 —
    /// 카메라 세션이 사용자의 응답을 받기 전까지는 사용자 입장에서 둘 다 "허용 안 됨" 이기 때문입니다.
    var pendingPermissions: [String] {
        var pending: [String] = []
        if cameraStatus != .authorized {
            pending.append(NSLocalizedString("permission_camera", comment: "카메라 권한"))
        }
        if microphoneStatus != .authorized {
            pending.append(NSLocalizedString("permission_microphone", comment: "마이크 권한"))
        }
        return pending
    }

    /// 권한 설정 가이드 메시지 생성.
    /// 권한이 모두 허용된 경우 안내 메시지를, 그렇지 않으면 어떤 권한이 필요한지 나열합니다.
    var permissionGuideMessage: String {
        if pendingPermissions.isEmpty {
            return NSLocalizedString("all_permissions_granted", comment: "모든 권한 허용됨")
        } else {
            return String(
                format: NSLocalizedString("permissions_required_message", comment: "권한 필요 메시지"),
                pendingPermissions.joined(separator: ", ")
            )
        }
    }

    // MARK: - Private Methods

    /// 모든 권한 상태를 확인하여 areAllPermissionsGranted 업데이트
    private func updateAllPermissionsStatus() {
        areAllPermissionsGranted = cameraStatus == .authorized &&
                                  microphoneStatus == .authorized
    }
}