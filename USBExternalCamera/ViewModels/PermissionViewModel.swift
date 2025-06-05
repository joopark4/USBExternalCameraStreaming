import SwiftUI
import AVFoundation
import Photos

/// 권한 관리를 위한 ViewModel
/// MVVM 패턴에서 View와 Model(PermissionManager) 사이의 중간층 역할을 담당합니다.
/// 권한 상태 관리, 권한 요청, UI 상태 업데이트를 담당합니다.
@MainActor
final class PermissionViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    /// 권한 매니저 - 실제 권한 관련 비즈니스 로직을 담당
    let permissionManager: PermissionManager
    
    // MARK: - Published Properties (UI State)
    
    /// 카메라 권한 상태
    /// UI에서 카메라 권한 상태를 표시하고 반응하는데 사용됩니다.
    @Published var cameraStatus: PermissionStatus
    
    /// 마이크 권한 상태
    /// UI에서 마이크 권한 상태를 표시하고 반응하는데 사용됩니다.
    @Published var microphoneStatus: PermissionStatus
    
    /// 사진첩 권한 상태
    /// UI에서 사진첩 권한 상태를 표시하고 반응하는데 사용됩니다.
    @Published var photoLibraryStatus: PermissionStatus
    
    /// 모든 필수 권한이 허용되었는지 여부
    /// MainViewModel에서 바인딩하여 UI 상태를 결정하는데 사용됩니다.
    @Published var areAllPermissionsGranted: Bool = false
    
    // MARK: - Initialization
    
    /// PermissionViewModel 초기화
    /// 의존성 주입을 통해 PermissionManager를 받아 초기화합니다.
    /// - Parameter permissionManager: 권한 관리 비즈니스 로직을 담당하는 매니저
    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
        self.cameraStatus = permissionManager.cameraStatus
        self.microphoneStatus = permissionManager.microphoneStatus
        self.photoLibraryStatus = permissionManager.photoLibraryStatus
        
        // 초기 권한 상태 업데이트
        updateAllPermissionsStatus()
    }
    
    // MARK: - Public Methods (User Actions)
    
    /// 카메라 권한 요청
    /// 비동기적으로 카메라 권한을 요청하고 상태를 업데이트합니다.
    func requestCameraPermission() async {
        await permissionManager.requestCameraPermission()
        cameraStatus = permissionManager.cameraStatus
        updateAllPermissionsStatus()
    }
    
    /// 마이크 권한 요청
    /// 비동기적으로 마이크 권한을 요청하고 상태를 업데이트합니다.
    func requestMicrophonePermission() async {
        await permissionManager.requestMicrophonePermission()
        microphoneStatus = permissionManager.microphoneStatus
        updateAllPermissionsStatus()
    }
    
    /// 사진첩 권한 요청
    /// 비동기적으로 사진첩 권한을 요청하고 상태를 업데이트합니다.
    func requestPhotoLibraryPermission() async {
        await permissionManager.requestPhotoLibraryPermission()
        photoLibraryStatus = permissionManager.photoLibraryStatus
        updateAllPermissionsStatus()
    }
    
    // MARK: - Utility Methods
    
    /// 권한 상태를 사용자에게 표시할 텍스트로 변환
    /// - Parameter status: 권한 상태
    /// - Returns: 로컬라이즈된 권한 상태 텍스트
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
    /// UI에서 어떤 권한이 거부되었는지 표시하는데 사용됩니다.
    var deniedPermissions: [String] {
        var denied: [String] = []
        if cameraStatus == .denied { 
            denied.append(NSLocalizedString("permission_camera", comment: "카메라 권한")) 
        }
        if microphoneStatus == .denied { 
            denied.append(NSLocalizedString("permission_microphone", comment: "마이크 권한")) 
        }
        if photoLibraryStatus == .denied { 
            denied.append(NSLocalizedString("permission_photo_library", comment: "사진첩 권한")) 
        }
        return denied
    }
    
    /// 권한 설정 가이드 메시지 생성
    /// 사용자에게 어떤 권한이 필요한지 안내하는 메시지를 반환합니다.
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
    /// 개별 권한 상태가 변경될 때마다 호출되어 전체 권한 상태를 갱신합니다.
    private func updateAllPermissionsStatus() {
        areAllPermissionsGranted = cameraStatus == .authorized &&
                                  microphoneStatus == .authorized &&
                                  photoLibraryStatus == .authorized
    }
} 