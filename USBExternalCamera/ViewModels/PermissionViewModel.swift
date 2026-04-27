import SwiftUI
import UIKit
import AVFoundation
import Combine

/// 카메라/마이크 권한 상태를 SwiftUI 가 관찰할 수 있도록 노출하는 ViewModel.
/// 권한 자체는 `PermissionManager` 가 단일 source of truth — 이 ViewModel 은 그 값을
/// computed 로 forward 하면서 권한 요청 / 시스템 설정 앱 라우팅 / foreground 자동 갱신과
/// 같은 사용자 액션 측 책임만 추가합니다.
@MainActor
final class PermissionViewModel: ObservableObject {

    // MARK: - Dependencies

    let permissionManager: PermissionManager

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager

        // PermissionManager 의 published 변경을 본 ViewModel 의 objectWillChange 로 forward.
        // SwiftUI 는 ObservableObject 의 objectWillChange 만 보므로, computed 프로퍼티 (cameraStatus
        // 등) 를 읽는 뷰가 manager 변경에도 자동으로 재평가됩니다.
        permissionManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // 사용자가 시스템 설정 앱에서 권한을 변경하고 돌아오면 즉시 UI 에 반영.
        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.permissionManager.checkPermissions()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Derived State (manager 가 single source of truth)

    var cameraStatus: PermissionStatus { permissionManager.cameraStatus }
    var microphoneStatus: PermissionStatus { permissionManager.microphoneStatus }
    var areAllPermissionsGranted: Bool {
        cameraStatus == .authorized && microphoneStatus == .authorized
    }

    /// 외부 (예: `MainViewModel`) 가 권한 상태 변화에만 반응하고 싶을 때 구독할 publisher.
    /// `objectWillChange` 와 다르게 외부에 안정적인 인터페이스를 제공하고, `RunLoop.main` 으로
    /// 한 tick 미뤄서 willSet 시점의 stale-value race 를 회피하는 구독측 코드를 단순화합니다.
    var permissionStatusChanges: AnyPublisher<Void, Never> {
        permissionManager.objectWillChange
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    // MARK: - Public Methods (User Actions)

    func refreshStatus() {
        permissionManager.checkPermissions()
    }

    /// 카메라 권한 요청.
    /// `.notDetermined` 만 시스템 다이얼로그를 띄울 수 있고, `.denied`/`.restricted` 는
    /// iOS 가 다이얼로그를 다시 띄우지 않으므로 시스템 설정 앱으로 사용자를 이동시킵니다.
    func requestCameraPermission() async {
        if cameraStatus.requiresSystemSettings {
            await openSystemSettings()
            return
        }
        await permissionManager.requestCameraPermission()
    }

    /// 마이크 권한 요청. 카메라와 동일한 분기 정책.
    func requestMicrophonePermission() async {
        if microphoneStatus.requiresSystemSettings {
            await openSystemSettings()
            return
        }
        await permissionManager.requestMicrophonePermission()
    }

    private func openSystemSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        await UIApplication.shared.open(url)
    }

    // MARK: - Derived Values

    /// 권한 안내 화면(`PermissionRequiredView`) 에 표시할 메시지.
    /// `.notDetermined` 도 "허용 안 됨" 으로 잡습니다 — 사용자 입장에서는 응답 전과 거부 모두
    /// "허용되지 않은" 상태이기 때문입니다.
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
}
