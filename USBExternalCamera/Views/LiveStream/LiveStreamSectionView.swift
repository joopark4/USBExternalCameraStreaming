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
            // 기존 일반 스트리밍 버튼 제거 - 화면 캡처 스트리밍만 사용
            
            // MARK: - Screen Capture Streaming Button
            
            /// 🎬 화면 캡처 스트리밍 시작/중지 토글 버튼
            /// 
            /// **기능:**
            /// - CameraPreviewContainerView의 전체 화면(카메라 + UI)을 실시간 캡처
            /// - 30fps로 HaishinKit을 통해 스트리밍 서버에 전송
            /// - 일반 카메라 스트리밍과 독립적으로 동작
            ///
            /// **UI 상태:**
            /// - 버튼 텍스트: "스트리밍 시작 - 캡처" ↔ "스트리밍 중지 - 캡처"
            /// - 아이콘: camera.metering.partial ↔ stop.circle.fill
            /// - 상태 표시: Live 배지 표시 (스트리밍 중일 때)
            ///
            /// **사용자 경험:**
            /// - 처리 중일 때 "처리 중..." 텍스트 표시
            /// - 스트리밍 중일 때 빨간색 Live 배지로 시각적 피드백
            /// - 버튼 비활성화는 일반 스트리밍 버튼과 연동
            Button {
                logInfo("Streaming button tapped", category: .ui)
                viewModel.toggleScreenCaptureStreaming()
            } label: {
                HStack {
                    Label(
                        viewModel.streamingButtonText,
                        systemImage: viewModel.isScreenCaptureStreaming ? "stop.circle.fill" : "play.circle.fill"
                    )
                    Spacer()
                    
                    // 스트리밍 상태 표시
                    if viewModel.isScreenCaptureStreaming {
                        Text(NSLocalizedString("live_status", comment: "Live"))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
            }
            .disabled(viewModel.isLoading)
            .foregroundColor(viewModel.streamingButtonColor)
            
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
