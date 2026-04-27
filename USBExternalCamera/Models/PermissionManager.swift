import AVFoundation
import SwiftUI

enum PermissionStatus {
    case notDetermined
    case restricted
    case denied
    case authorized

    /// 한 번 거부된 카메라/마이크 권한은 iOS 가 더 이상 시스템 다이얼로그를 보여주지 않으므로,
    /// 이 케이스에서는 본 앱이 직접 시스템 설정 앱으로 사용자를 보내야 합니다.
    var requiresSystemSettings: Bool {
        switch self {
        case .denied, .restricted: return true
        case .notDetermined, .authorized: return false
        }
    }
}

/// 카메라/마이크 권한만 사용 (사진첩 저장 기능 미사용).
class PermissionManager: ObservableObject {
    @Published var cameraStatus: PermissionStatus = .notDetermined
    @Published var microphoneStatus: PermissionStatus = .notDetermined

    init() {
        checkPermissions()
    }

    func checkPermissions() {
        cameraStatus = Self.mapStatus(AVCaptureDevice.authorizationStatus(for: .video))
        microphoneStatus = Self.mapStatus(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestCameraPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            cameraStatus = granted ? .authorized : .denied
        }
    }

    func requestMicrophonePermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphoneStatus = granted ? .authorized : .denied
        }
    }

    private static func mapStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        @unknown default: return .notDetermined
        }
    }
}
