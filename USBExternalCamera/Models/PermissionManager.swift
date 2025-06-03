import AVFoundation
import Photos
import SwiftUI

/// 권한 상태를 나타내는 열거형
enum PermissionStatus {
    case notDetermined
    case restricted
    case denied
    case authorized
}

/// 권한 관리를 위한 클래스
class PermissionManager: ObservableObject {
    /// 카메라 권한 상태
    @Published var cameraStatus: PermissionStatus = .notDetermined
    /// 마이크 권한 상태
    @Published var microphoneStatus: PermissionStatus = .notDetermined
    /// 사진첩 권한 상태
    @Published var photoLibraryStatus: PermissionStatus = .notDetermined

    /// 초기화
    init() {
        checkPermissions()
    }

    /// 모든 권한 상태 확인
    func checkPermissions() {
        checkCameraPermission()
        checkMicrophonePermission()
        checkPhotoLibraryPermission()
    }

    /// 카메라 권한 확인
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            cameraStatus = .notDetermined
        case .restricted:
            cameraStatus = .restricted
        case .denied:
            cameraStatus = .denied
        case .authorized:
            cameraStatus = .authorized
        @unknown default:
            cameraStatus = .notDetermined
        }
    }

    /// 마이크 권한 확인
    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .restricted:
            microphoneStatus = .restricted
        case .denied:
            microphoneStatus = .denied
        case .authorized:
            microphoneStatus = .authorized
        @unknown default:
            microphoneStatus = .notDetermined
        }
    }

    /// 사진첩 권한 확인
    private func checkPhotoLibraryPermission() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined:
            photoLibraryStatus = .notDetermined
        case .restricted:
            photoLibraryStatus = .restricted
        case .denied:
            photoLibraryStatus = .denied
        case .authorized, .limited:
            photoLibraryStatus = .authorized
        @unknown default:
            photoLibraryStatus = .notDetermined
        }
    }

    /// 카메라 권한 요청
    func requestCameraPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            cameraStatus = granted ? .authorized : .denied
        }
    }

    /// 마이크 권한 요청
    func requestMicrophonePermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphoneStatus = granted ? .authorized : .denied
        }
    }

    /// 사진첩 권한 요청
    func requestPhotoLibraryPermission() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            switch status {
            case .authorized, .limited:
                photoLibraryStatus = .authorized
            case .denied:
                photoLibraryStatus = .denied
            case .restricted:
                photoLibraryStatus = .restricted
            case .notDetermined:
                photoLibraryStatus = .notDetermined
            @unknown default:
                photoLibraryStatus = .notDetermined
            }
        }
    }
} 