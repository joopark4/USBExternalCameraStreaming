import SwiftUI
import AVFoundation

extension LiveStreamView {
    // MARK: - Real-time Transmission Section
    
    var realTimeTransmissionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("realtime_transmission_data", comment: "📡 실시간 송출 데이터"))
                    .font(.headline)
                
                Spacer()
                
                // Live 인디케이터
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseAnimation ? 1.3 : 0.7)
                        .animation(.easeInOut(duration: 1.0).repeatForever(), value: pulseAnimation)
                        .onAppear {
                            pulseAnimation = true
                        }
                    
                    Text(NSLocalizedString("live_status", comment: "LIVE"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                
                // 비디오 프레임 전송량
                TransmissionInfoCard(
                    icon: "video.fill",
                    title: "비디오 프레임",
                    value: formatFrameCount(viewModel.transmissionStats.videoFramesTransmitted),
                    subtitle: "frames sent",
                    color: .blue
                )
                
                // 현재 프레임율
                TransmissionInfoCard(
                    icon: "speedometer",
                    title: "프레임율",
                    value: String(format: "%.1f fps", viewModel.transmissionStats.averageFrameRate),
                    subtitle: "target: 30fps",
                    color: .green
                )
                
                // 총 전송 데이터량
                TransmissionInfoCard(
                    icon: "icloud.and.arrow.up.fill",
                    title: "전송량",
                    value: formatDataSize(viewModel.transmissionStats.totalBytesTransmitted),
                    subtitle: "total sent",
                    color: .purple
                )
                
                // 네트워크 지연시간
                TransmissionInfoCard(
                    icon: "wifi",
                    title: "지연시간",
                    value: String(format: "%.0fms", viewModel.transmissionStats.networkLatency * 1000),
                    subtitle: networkLatencyStatus,
                    color: networkLatencyColor
                )
                
                // 실제 비트레이트
                TransmissionInfoCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "비트레이트",
                    value: String(format: "%.0f kbps", viewModel.transmissionStats.currentVideoBitrate),
                    subtitle: "video stream",
                    color: .orange
                )
                
                // 드롭된 프레임
                TransmissionInfoCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "드롭 프레임",
                    value: "\(viewModel.transmissionStats.droppedFrames)",
                    subtitle: droppedFramesStatus,
                    color: droppedFramesColor
                )
            }
        }
        .padding()
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Helper Methods for Real-time Data
    
    private func formatFrameCount(_ count: Int64) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
    
    private func formatDataSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private var networkLatencyStatus: String {
        let latency = viewModel.transmissionStats.networkLatency * 1000
        if latency < 50 {
            return "excellent"
        } else if latency < 100 {
            return "good"
        } else if latency < 200 {
            return "fair"
        } else {
            return "poor"
        }
    }

    
    private var droppedFramesColor: Color {
        let dropped = viewModel.transmissionStats.droppedFrames
        if dropped == 0 {
            return .green
        } else if dropped < 10 {
            return .yellow
        } else if dropped < 50 {
            return .orange
        } else {
            return .red
        }
    }

    
    // MARK: - Helper Properties for Transmission Data
    
    private var networkLatencyColor: Color {
        let latency = viewModel.transmissionStats.networkLatency * 1000
        if latency < 50 {
            return .green
        } else if latency < 100 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var droppedFramesStatus: String {
        let dropped = viewModel.transmissionStats.droppedFrames
        if dropped == 0 {
            return "정상"
        } else if dropped < 10 {
            return "경미함"
        } else {
            return "심각함"
        }
    }
    
    // MARK: - Helper Methods for Data Formatting
    
    private func formatFrameCount(_ count: Int) -> String {
        if count > 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
}
