import SwiftUI
import AVFoundation

extension LiveStreamView {
    // MARK: - Streaming Info Section
    
    private var streamingInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("streaming_info", comment: "스트리밍 정보"))
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                
                // 비디오 품질
                InfoCard(
                    icon: "video.fill",
                    title: "비디오 품질",
                    value: "\(viewModel.settings.videoWidth)×\(viewModel.settings.videoHeight)",
                    color: .blue
                )
                
                // 네트워크 상태  
                InfoCard(
                    icon: "wifi",
                    title: "네트워크 상태",
                    value: viewModel.networkQuality.displayName,
                    color: Color(viewModel.networkQuality.color)
                )
                
                // 비트레이트
                InfoCard(
                    icon: "speedometer",
                    title: "비트레이트",
                    value: "\(viewModel.settings.videoBitrate) kbps",
                    color: .green
                )
                
                // 해상도
                InfoCard(
                    icon: "rectangle.fill",
                    title: "해상도",
                    value: resolutionText,
                    color: .purple
                )
            }
            

            
            // 실시간 송출 데이터 섹션 (스트리밍 중일 때만 표시)
            if viewModel.isScreenCaptureStreaming {
                realTimeTransmissionSection
            }
        }
    }
    
}
