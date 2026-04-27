import SwiftUI
import UIKit
import AVFoundation
import Combine

/// 카메라/마이크 권한 상태를 SwiftUI 가 관찰할 수 있도록 노출하는 ViewModel.
/// `PermissionManager` 의 시스템 권한 상태를 mirror 하면서 `areAllPermissionsGranted`
/// 같은 파생 값을 계산하고, 권한 요청 / 시스템 설정 앱 라우팅 / foreground 자동 갱신을 담당합니다.
@MainActor
final class PermissionViewModel: ObservableObject {

    // MARK: - Dependencies

    let permissionManager: PermissionManager

    // MARK: - Published Properties (UI State)

    @Published var cameraStatus: PermissionStatus
    @Published var microphoneStatus: PermissionStatus
    @Published var areAllPermissionsGranted: Bool = false

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
        self.cameraStatus = permissionManager.cameraStatus
        self.microphoneStatus = permissionManager.microphoneStatus

        updateAllPermissionsStatus()

        // 사용자가 시스템 설정 앱에서 권한을 변경하고 돌아오면 즉시 UI 에 반영.
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshStatus()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods (User Actions)

    /// 시스템 권한 상태를 다시 읽어들여 published 프로퍼티 + `areAllPermissionsGranted` 를 동기화합니다.
    /// 카메라 세션이 켜지며 떴던 시스템 다이얼로그처럼, 앱이 명시적 `requestXxxPermission`
    /// 을 거치지 않고 권한이 바뀐 경로에서도 UI 가 최신 상태를 반영하도록 합니다.
    /// 변경 감지 가드를 적용해, foreground 마다 호출되어도 값이 같으면 publish 가 발생하지 않습니다.
    func refreshStatus() {
        permissionManager.checkPermissions()
        if cameraStatus != permissionManager.cameraStatus {
            cameraStatus = permissionManager.cameraStatus
        }
        if microphoneStatus != permissionManager.microphoneStatus {
            microphoneStatus = permissionManager.microphoneStatus
        }
        updateAllPermissionsStatus()
    }

    /// 카메라 권한 요청.
    /// `.notDetermined` 만 시스템 다이얼로그를 띄울 수 있고, `.denied`/`.restricted` 는
    /// iOS 가 다이얼로그를 다시 띄우지 않으므로 시스템 설정 앱으로 사용자를 이동시킵니다.
    func requestCameraPermission() async {
        if permissionManager.cameraStatus.requiresSystemSettings {
            await openSystemSettings()
            return
        }
        await permissionManager.requestCameraPermission()
        cameraStatus = permissionManager.cameraStatus
        updateAllPermissionsStatus()
    }

    /// 마이크 권한 요청. 카메라와 동일한 분기 정책.
    func requestMicrophonePermission() async {
        if permissionManager.microphoneStatus.requiresSystemSettings {
            await openSystemSettings()
            return
        }
        await permissionManager.requestMicrophonePermission()
        microphoneStatus = permissionManager.microphoneStatus
        updateAllPermissionsStatus()
    }

    private func openSystemSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        await UIApplication.shared.open(url)
    }

    // MARK: - Derived Values

    /// 권한 안내 화면(`PermissionRequiredView`) 에 표시할 메시지.
    /// `.notDetermined` 도 "허용 안 됨" 으로 잡습니다 — 사용자 입장에서는 아직 응답하지 않은
    /// 상태나 거부한 상태나 모두 "허용되지 않은" 상태이기 때문입니다.
    var permissionGuideMessage: String {
        let pending = pendingPermissions
        if pending.isEmpty {
            return NSLocalizedString("all_permissions_granted", comment: "모든 권한 허용됨")
        }
        return String(
            format: NSLocalizedString("permissions_required_message", comment: "권한 필요 메시지"),
            pending.joined(separator: ", ")
        )
    }

    private var pendingPermissions: [String] {
        var pending: [String] = []
        if cameraStatus != .authorized {
            pending.append(NSLocalizedString("permission_camera", comment: "카메라"))
        }
        if microphoneStatus != .authorized {
            pending.append(NSLocalizedString("permission_microphone", comment: "마이크"))
        }
        return pending
    }

    // MARK: - Private Methods

    /// 변경 감지 가드 — `areAllPermissionsGranted` 가 실제로 변할 때만 publish.
    private func updateAllPermissionsStatus() {
        let granted = cameraStatus == .authorized && microphoneStatus == .authorized
        if areAllPermissionsGranted != granted {
            areAllPermissionsGranted = granted
        }
    }
}
