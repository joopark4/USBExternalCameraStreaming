import UIKit
import AVFoundation
import Combine

/// 디바이스 방향을 관리하는 클래스
class DeviceOrientationManager: ObservableObject {
    /// 현재 디바이스 방향
    @Published private(set) var orientation: UIDeviceOrientation = .portrait
    
    /// 디바이스 방향 변경 알림을 위한 NotificationCenter 구독
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 디바이스 방향 변경 알림 구독
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateOrientation()
            }
            .store(in: &cancellables)
        
        // 초기 방향 설정
        updateOrientation()
    }
    
    /// 현재 디바이스 방향 업데이트
    private func updateOrientation() {
        orientation = UIDevice.current.orientation
    }
    
    /// 디바이스 방향에 따른 비디오 방향 반환
    @available(iOS, deprecated: 17.0, message: "Use videoRotationAngle instead")
    var videoOrientation: AVCaptureVideoOrientation {
        switch orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .portrait
        }
    }
    
    /// iOS 17+ 호환 비디오 회전 각도
    @available(iOS 17.0, *)
    var videoRotationAngle: CGFloat {
        switch orientation {
        case .portrait:
            return 0
        case .portraitUpsideDown:
            return 180
        case .landscapeLeft:
            return 90
        case .landscapeRight:
            return 270
        default:
            return 0
        }
    }
} 
