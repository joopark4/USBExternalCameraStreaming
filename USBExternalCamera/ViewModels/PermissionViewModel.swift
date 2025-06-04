import SwiftUI
import AVFoundation
import Photos

/// 권한 관리를 위한 ViewModel
@MainActor
final class PermissionViewModel: ObservableObject {
    /// 권한 매니저
    private let permissionManager: PermissionManager
    
    /// 카메라 권한 상태
    @Published var cameraStatus: PermissionStatus
    /// 마이크 권한 상태
    @Published var microphoneStatus: PermissionStatus
    /// 사진첩 권한 상태
    @Published var photoLibraryStatus: PermissionStatus
    
    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
        self.cameraStatus = permissionManager.cameraStatus
        self.microphoneStatus = permissionManager.microphoneStatus
        self.photoLibraryStatus = permissionManager.photoLibraryStatus
    }
    
    /// 카메라 권한 요청
    func requestCameraPermission() async {
        await permissionManager.requestCameraPermission()
        cameraStatus = permissionManager.cameraStatus
    }
    
    /// 마이크 권한 요청
    func requestMicrophonePermission() async {
        await permissionManager.requestMicrophonePermission()
        microphoneStatus = permissionManager.microphoneStatus
    }
    
    /// 사진첩 권한 요청
    func requestPhotoLibraryPermission() async {
        await permissionManager.requestPhotoLibraryPermission()
        photoLibraryStatus = permissionManager.photoLibraryStatus
    }
    
    /// 권한 상태를 텍스트로 변환
    func permissionStatusText(_ status: PermissionStatus) -> String {
        switch status {
        case .notDetermined:
            return NSLocalizedString("permission_status_not_determined", comment: "")
        case .restricted:
            return NSLocalizedString("permission_status_restricted", comment: "")
        case .denied:
            return NSLocalizedString("permission_status_denied", comment: "")
        case .authorized:
            return NSLocalizedString("permission_status_authorized", comment: "")
        }
    }
    
    /// 모든 필수 권한이 허용되었는지 확인
    var areAllPermissionsGranted: Bool {
        cameraStatus == .authorized &&
        microphoneStatus == .authorized &&
        photoLibraryStatus == .authorized
    }
    
    /// 권한이 거부된 항목 목록
    var deniedPermissions: [String] {
        var denied: [String] = []
        if cameraStatus == .denied { denied.append(NSLocalizedString("permission_camera", comment: "")) }
        if microphoneStatus == .denied { denied.append(NSLocalizedString("permission_microphone", comment: "")) }
        if photoLibraryStatus == .denied { denied.append(NSLocalizedString("permission_photo_library", comment: "")) }
        return denied
    }
    
    /// 권한 설정 가이드 메시지
    var permissionGuideMessage: String {
        if deniedPermissions.isEmpty {
            return NSLocalizedString("all_permissions_granted", comment: "")
        } else {
            return String(format: NSLocalizedString("permissions_denied_message", comment: ""), deniedPermissions.joined(separator: ", "))
        }
    }
} 