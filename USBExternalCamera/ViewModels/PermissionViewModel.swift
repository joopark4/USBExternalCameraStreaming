import SwiftUI
import UIKit
import AVFoundation
import Combine

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

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
        self.cameraStatus = permissionManager.cameraStatus
        self.microphoneStatus = permissionManager.microphoneStatus

        // 초기 권한 상태 업데이트
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

    /// 카메라 권한 요청.
    /// 현재 상태가 `.notDetermined` 인 경우에만 시스템 다이얼로그를 띄울 수 있습니다.
    /// 이미 `.denied`/`.restricted` 라면 iOS 가 다이얼로그를 더 이상 보여주지 않으므로
    /// 시스템 설정 앱으로 사용자를 이동시킵니다.
    func requestCameraPermission() async {
        if permissionManager.cameraStatus.requiresSystemSettings {
            await openSystemSettings()
            return
        }
        await permissionManager.requestCameraPermission()
        cameraStatus = permissionManager.cameraStatus
        updateAllPermissionsStatus()
    }

    /// 마이크 권한 요청.
    /// 카메라와 동일한 정책 — `.denied`/`.restricted` 면 시스템 설정 앱으로 이동.
    func requestMicrophonePermission() async {
        if permissionManager.microphoneStatus.requiresSystemSettings {
            await openSystemSettings()
            return
        }
        await permissionManager.requestMicrophonePermission()
        microphoneStatus = permissionManager.microphoneStatus
        updateAllPermissionsStatus()
    }

    /// iOS 시스템 설정 앱의 본 앱 페이지를 엽니다.
    private func openSystemSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        guard await UIApplication.shared.canOpenURL(url) else { return }
        await UIApplication.shared.open(url)
    }

    // MARK: - Utility Methods

    /// 권한 row 의 액션 버튼 라벨을 권한 상태에 따라 결정합니다.
    /// `.notDetermined` 면 시스템 다이얼로그를 띄울 수 있으므로 "권한 요청",
    /// `.denied`/`.restricted` 면 iOS 가 다이얼로그를 더 띄우지 않으므로 "설정 열기",
    /// `.authorized` 면 더 할 일이 없으므로 "허용됨".
    func actionButtonTitle(for status: PermissionStatus) -> String {
        switch status {
        case .notDetermined:
            return NSLocalizedString("permissions_request", comment: "권한 요청")
        case .denied, .restricted:
            return NSLocalizedString("permissions_open_settings", comment: "설정 열기")
        case .authorized:
            return NSLocalizedString("permission_status_authorized", comment: "허용됨")
        }
    }

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