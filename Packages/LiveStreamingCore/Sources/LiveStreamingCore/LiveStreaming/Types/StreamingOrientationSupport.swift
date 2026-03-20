import CoreGraphics
import Foundation

public enum StreamOrientation: String, Codable, CaseIterable, Sendable {
  case landscape
  case portrait

  public var isPortrait: Bool {
    self == .portrait
  }

  public var layoutProfile: StreamLayoutProfile {
    StreamLayoutProfile(orientation: self)
  }

  public var rotationPolicy: StreamRotationPolicy {
    isPortrait ? .rotate90Clockwise : .none
  }
}

public enum StreamRotationPolicy: Sendable {
  case none
  case rotate90Clockwise

  public var degrees: CGFloat {
    switch self {
    case .none:
      return 0
    case .rotate90Clockwise:
      return 90
    }
  }
}

public struct StreamLayoutProfile: Sendable {
  public let orientation: StreamOrientation

  public init(orientation: StreamOrientation) {
    self.orientation = orientation
  }

  public var aspectRatio: CGFloat {
    orientation.isPortrait ? (9.0 / 16.0) : (16.0 / 9.0)
  }

  public var rotationPolicy: StreamRotationPolicy {
    orientation.rotationPolicy
  }
}

public enum StreamResolutionClass: String, CaseIterable, Sendable {
  case p480
  case p720
  case p1080
  case p4k
  case custom
}

public struct StreamResolutionDescriptor: Sendable, Equatable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  public var longEdge: Int {
    max(width, height)
  }

  public var shortEdge: Int {
    min(width, height)
  }

  public var orientation: StreamOrientation {
    height > width ? .portrait : .landscape
  }

  public var resolutionClass: StreamResolutionClass {
    switch (longEdge, shortEdge) {
    case (848...854, 480), (640, 480):
      return .p480
    case (1280, 720):
      return .p720
    case (1920, 1080):
      return .p1080
    case (3840, 2160):
      return .p4k
    default:
      return .custom
    }
  }

  public static func presetSize(
    for resolutionClass: StreamResolutionClass,
    orientation: StreamOrientation
  ) -> (width: Int, height: Int)? {
    let landscapeSize: (width: Int, height: Int)?
    switch resolutionClass {
    case .p480:
      landscapeSize = (848, 480)
    case .p720:
      landscapeSize = (1280, 720)
    case .p1080:
      landscapeSize = (1920, 1080)
    case .p4k:
      landscapeSize = (3840, 2160)
    case .custom:
      landscapeSize = nil
    }

    guard let landscapeSize else { return nil }
    if orientation.isPortrait {
      return (landscapeSize.height, landscapeSize.width)
    }
    return landscapeSize
  }
}

