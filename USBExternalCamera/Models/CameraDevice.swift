import AVFoundation
import Foundation

/// 카메라 디바이스 모델
/// - Identifiable: SwiftUI에서 리스트 표시를 위한 고유 식별자 프로토콜
/// - AVCaptureDevice를 래핑하여 카메라 정보를 쉽게 접근할 수 있도록 함
public struct CameraDevice: Identifiable {
    /// 카메라 디바이스의 고유 식별자
    /// - AVCaptureDevice의 uniqueID를 사용하여 각 카메라를 구분
    public let id: String
    
    /// 카메라 디바이스의 표시 이름
    /// - AVCaptureDevice의 localizedName을 사용하여 사용자 친화적인 이름 제공
    public let name: String
    
    /// 실제 AVCaptureDevice 인스턴스
    /// - 카메라 설정 및 제어에 사용되는 기본 디바이스 객체
    public let device: AVCaptureDevice
    
    /// AVCaptureDevice를 CameraDevice로 변환하는 이니셜라이저
    /// - device: 변환할 AVCaptureDevice 인스턴스
    public init(device: AVCaptureDevice) {
        self.id = device.uniqueID
        self.name = device.localizedName
        self.device = device
    }
} 