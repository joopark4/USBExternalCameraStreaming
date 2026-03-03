import SwiftUI
import LiveStreamingCore

// MARK: - Live Stream Components

/// 라이브 스트리밍 섹션 View 컴포넌트
/// 라이브 스트리밍 관련 메뉴를 표시하는 독립적인 컴포넌트입니다.
struct LiveStreamSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    let onShowSettings: () -> Void
    
    var body: some View {
        Section(header: Text(NSLocalizedString("live_streaming_section", comment: "라이브 스트리밍 섹션"))) {
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.status == .streaming ? Color.red : Color.gray)
                    .frame(width: 8, height: 8)
                Text(NSLocalizedString("current_status", comment: "현재 상태"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(viewModel.status.description)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            // 라이브 스트리밍 설정 메뉴
            Button {
                onShowSettings()
            } label: {
                Label(NSLocalizedString("live_streaming_settings", comment: "라이브 스트리밍 설정"), 
                      systemImage: "gear")
            }
        }
    }
}
