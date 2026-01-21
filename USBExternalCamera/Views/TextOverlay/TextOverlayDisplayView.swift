import SwiftUI
import LiveStreamingCore

/// 텍스트 오버레이 표시 View
/// 
/// 카메라 프리뷰 위에 실제로 표시되는 텍스트 오버레이 컴포넌트입니다.
/// 사용자가 설정한 폰트, 색상, 크기로 텍스트를 표시합니다.
struct TextOverlayDisplayView: View {
    let settings: TextOverlaySettings
    let previewSize: CGSize
    
    var body: some View {
        if !settings.text.isEmpty {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(settings.text)
                        .font(fontForDisplay(settings))
                        .foregroundColor(settings.textColor)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                        .shadow(color: .black, radius: 1, x: -1, y: -1)
                        .shadow(color: .black, radius: 1, x: 1, y: -1)
                        .shadow(color: .black, radius: 1, x: -1, y: 1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.7))
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    Spacer()
                }
                .padding(.bottom, 16)
            }
            .frame(width: previewSize.width, height: previewSize.height)
        }
    }
    
    /// SwiftUI Font를 생성 (UIFont와 동일한 로직 사용)
    private func fontForDisplay(_ settings: TextOverlaySettings) -> Font {
        switch settings.fontName {
        case "System":
            return .system(size: settings.fontSize, weight: .medium)
        case "System Bold":
            return .system(size: settings.fontSize, weight: .bold)
        case "Helvetica":
            return .custom("Helvetica", size: settings.fontSize)
        case "Helvetica Bold":
            return .custom("Helvetica-Bold", size: settings.fontSize)
        case "Arial":
            return .custom("Arial", size: settings.fontSize)
        case "Arial Bold":
            return .custom("Arial-BoldMT", size: settings.fontSize)
        default:
            return .system(size: settings.fontSize, weight: .medium)
        }
    }
}

#Preview {
    let sampleSettings = TextOverlaySettings(
        text: NSLocalizedString("sample_text_overlay", comment: "샘플 텍스트 오버레이"),
        fontSize: 24,
        textColor: .white,
        fontName: "System"
    )
    
    return TextOverlayDisplayView(
        settings: sampleSettings,
        previewSize: CGSize(width: 320, height: 180)
    )
    .background(Color.black)
    .frame(width: 320, height: 180)
} 