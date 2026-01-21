import AVFoundation
import LiveStreamingCore

/// 카메라 디바이스 모델
/// - Identifiable: SwiftUI에서 리스트 표시를 위한 고유 식별자 프로토콜
/// - AVCaptureDevice를 래핑하여 카메라 정보를 쉽게 접근할 수 있도록 함
public struct CameraDevice: Identifiable {
  /// 카메라 디바이스의 고유 식별자
  /// - 디바이스 타입, 위치, uniqueID를 조합하여 완전히 고유한 ID 생성
  public let id: String

  /// 카메라 디바이스의 표시 이름
  /// - AVCaptureDevice의 localizedName을 사용하여 사용자 친화적인 이름 제공
  public let name: String

  /// 실제 AVCaptureDevice 인스턴스
  /// - 카메라 설정 및 제어에 사용되는 기본 디바이스 객체
  public let device: AVCaptureDevice

  /// 카메라 타입 (내장/외장 구분용)
  public let deviceType: String

  /// 카메라 위치 (전면/후면 구분용)
  public let position: String

  /// AVCaptureDevice를 CameraDevice로 변환하는 이니셜라이저
  /// - device: 변환할 AVCaptureDevice 인스턴스
  public init(device: AVCaptureDevice) {
    self.device = device
    self.name = device.localizedName

    // 디바이스 타입 문자열 생성 (더 구체적으로)
    let deviceTypeString: String
    switch device.deviceType {
    case .builtInWideAngleCamera:
      deviceTypeString = "builtInWide"
    case .builtInUltraWideCamera:
      deviceTypeString = "builtInUltraWide"
    case .builtInTelephotoCamera:
      deviceTypeString = "builtInTelephoto"
    case .external:
      deviceTypeString = "external"
    default:
      deviceTypeString = device.deviceType.rawValue
    }
    self.deviceType = deviceTypeString

    // 디바이스 위치 문자열 생성
    switch device.position {
    case .front:
      self.position = "front"
    case .back:
      self.position = "back"
    case .unspecified:
      self.position = "unspecified"
    @unknown default:
      self.position = "unknown"
    }

    // 고유 ID 생성: 디바이스 고유 정보만 사용 (타임스탬프 제거)
    // 형식: deviceType_position_uniqueID
    // 동일한 디바이스는 항상 동일한 ID를 가지도록 보장
    self.id = "\(deviceTypeString)_\(self.position)_\(device.uniqueID)"

    #if DEBUG
    logDebug("📹 CameraDevice created: \(self.name) (ID: \(self.id))", category: .camera)
    #endif
  }
}

// MARK: - Equatable 구현
extension CameraDevice: Equatable {
  public static func == (lhs: CameraDevice, rhs: CameraDevice) -> Bool {
    return lhs.id == rhs.id
  }
}

// MARK: - Hashable 구현
extension CameraDevice: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}
