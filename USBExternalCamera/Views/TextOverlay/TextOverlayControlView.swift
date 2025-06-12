import SwiftUI

/// 텍스트 오버레이 컨트롤 View
/// 
/// 텍스트 표시/숨김 토글 및 텍스트 추가 버튼을 제공하는 컴포넌트입니다.
/// 프리뷰 옆에 세로로 배치되어 사용자가 텍스트 오버레이를 제어할 수 있습니다.
struct TextOverlayControlView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // 텍스트 표시/숨김 토글 버튼
            Button(action: {
                viewModel.toggleTextOverlay()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.showTextOverlay ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: 20))
                    Text(viewModel.showTextOverlay ? NSLocalizedString("text_overlay_hide", comment: "텍스트 숨김") : NSLocalizedString("text_overlay_show", comment: "텍스트 표시"))
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(viewModel.showTextOverlay ? .white : .blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(width: 100, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(viewModel.showTextOverlay ? Color.blue : Color.blue.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            
            // 텍스트 설정 버튼
            Button(action: {
                viewModel.showTextSettings()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "textformat.alt")
                        .font(.system(size: 20))
                    Text(NSLocalizedString("text_overlay_settings", comment: "텍스트 설정"))
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(width: 100, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// Preview removed due to complex dependencies 