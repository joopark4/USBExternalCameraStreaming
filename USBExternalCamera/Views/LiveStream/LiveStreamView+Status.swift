import SwiftUI
import AVFoundation

extension LiveStreamView {
    // MARK: - Status Dashboard
    
    private var statusDashboard: some View {
        VStack(spacing: 16) {
            HStack {
                Text(NSLocalizedString("streaming_status", comment: "스트리밍 상태"))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                statusIndicator
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(NSLocalizedString("status_label", comment: "상태:"))
                        .foregroundColor(.secondary)
                    
                                    Text(statusText)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                }
                
                if viewModel.isScreenCaptureStreaming {
                    HStack {
                        Text(NSLocalizedString("duration_label", comment: "지속 시간:"))
                            .foregroundColor(.secondary)
                        
                        Text("00:00")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .scaleEffect(viewModel.isScreenCaptureStreaming ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: viewModel.isScreenCaptureStreaming)
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(statusColor)
        }
    }
    
}
