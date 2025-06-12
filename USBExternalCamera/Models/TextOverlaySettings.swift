import SwiftUI
import Foundation

/// 텍스트 오버레이 설정 모델
public struct TextOverlaySettings: Equatable {
    public var text: String = ""
    public var fontSize: CGFloat = 24.0
    public var textColor: Color = .white
    public var fontName: String = "System"
    
    public init(text: String = "", fontSize: CGFloat = 24.0, textColor: Color = .white, fontName: String = "System") {
        self.text = text
        self.fontSize = fontSize
        self.textColor = textColor
        self.fontName = fontName
    }
    
    /// 시스템 폰트를 UIFont로 변환
    public var uiFont: UIFont {
        switch fontName {
        case "System":
            return UIFont.systemFont(ofSize: fontSize, weight: .medium)
        case "System Bold":
            return UIFont.boldSystemFont(ofSize: fontSize)
        case "Helvetica":
            return UIFont(name: "Helvetica", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        case "Helvetica Bold":
            return UIFont(name: "Helvetica-Bold", size: fontSize) ?? UIFont.boldSystemFont(ofSize: fontSize)
        case "Arial":
            return UIFont(name: "Arial", size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        case "Arial Bold":
            return UIFont(name: "Arial-BoldMT", size: fontSize) ?? UIFont.boldSystemFont(ofSize: fontSize)
        default:
            return UIFont.systemFont(ofSize: fontSize)
        }
    }
    
    /// 텍스트 색상을 UIColor로 변환
    public var uiColor: UIColor {
        return UIColor(textColor)
    }
    
    // MARK: - Equatable
    public static func == (lhs: TextOverlaySettings, rhs: TextOverlaySettings) -> Bool {
        return lhs.text == rhs.text &&
               lhs.fontSize == rhs.fontSize &&
               lhs.fontName == rhs.fontName &&
               lhs.textColor == rhs.textColor
    }
}

/// 텍스트 히스토리 아이템
struct TextHistoryItem: Identifiable, Codable {
    let id = UUID()
    var text: String
    var usedDate: Date
    
    init(text: String) {
        self.text = text
        self.usedDate = Date()
    }
}

/// 사용 가능한 폰트 목록
enum AvailableFont: String, CaseIterable {
    case system = "System"
    case systemBold = "System Bold"
    case helvetica = "Helvetica"
    case helveticaBold = "Helvetica Bold"
    case arial = "Arial"
    case arialBold = "Arial Bold"
    
    var displayName: String {
        return self.rawValue
    }
    
    /// 미리보기용 폰트
    var previewFont: Font {
        switch self {
        case .system:
            return .system(size: 16, weight: .medium)
        case .systemBold:
            return .system(size: 16, weight: .bold)
        case .helvetica:
            return .custom("Helvetica", size: 16)
        case .helveticaBold:
            return .custom("Helvetica-Bold", size: 16)
        case .arial:
            return .custom("Arial", size: 16)
        case .arialBold:
            return .custom("Arial-BoldMT", size: 16)
        }
    }
}

/// 사전 정의된 텍스트 색상
enum TextOverlayColor: String, CaseIterable {
    case white = "White"
    case black = "Black"
    case red = "Red"
    case blue = "Blue"
    case green = "Green"
    case yellow = "Yellow"
    case orange = "Orange"
    case purple = "Purple"
    
    var color: Color {
        switch self {
        case .white: return .white
        case .black: return .black
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .purple: return .purple
        }
    }
    
    var displayName: String {
        switch self {
        case .white: return NSLocalizedString("color_white", comment: "흰색")
        case .black: return NSLocalizedString("color_black", comment: "검은색")
        case .red: return NSLocalizedString("color_red", comment: "빨간색")
        case .blue: return NSLocalizedString("color_blue", comment: "파란색")
        case .green: return NSLocalizedString("color_green", comment: "초록색")
        case .yellow: return NSLocalizedString("color_yellow", comment: "노란색")
        case .orange: return NSLocalizedString("color_orange", comment: "주황색")
        case .purple: return NSLocalizedString("color_purple", comment: "보라색")
        }
    }
} 