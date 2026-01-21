import SwiftUI
import AVFoundation

extension LiveStreamView {
    // MARK: - Control Buttons
    
    var controlButtons: some View {
        VStack(spacing: 16) {
            // 메인 제어 버튼
            Button(action: toggleStreaming) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: viewModel.isScreenCaptureStreaming ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    
                    Text(streamingButtonText)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(streamingButtonColor)
                .foregroundColor(.white)
                .cornerRadius(25)
                .disabled(viewModel.isLoading)
            }
            
            // 보조 버튼들 (첫 번째 줄)
            HStack(spacing: 12) {
                // 연결 테스트 버튼
                Button(action: testConnection) {
                    HStack {
                        Image(systemName: "network")
                        Text(NSLocalizedString("connection_test", comment: "연결 테스트"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    .font(.system(size: 14, weight: .medium))
                }
                .disabled(viewModel.isLoading || viewModel.isScreenCaptureStreaming)
                
                // 빠른 진단 버튼
                Button(action: performQuickCheck) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text(NSLocalizedString("quick_diagnosis", comment: "빠른 진단"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    .font(.system(size: 14, weight: .medium))
                }
            }
            
            // 보조 버튼들 (두 번째 줄)
            HStack(spacing: 12) {
                // 전체 진단 버튼
                Button(action: {
                    Task {
                        await performFullDiagnostics()
                    }
                }) {
                    HStack {
                        Image(systemName: "stethoscope")
                        Text(NSLocalizedString("full_diagnosis", comment: "전체 진단"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    .font(.system(size: 14, weight: .medium))
                }
                
                // 설정 버튼
                NavigationLink(destination: LiveStreamSettingsView(viewModel: LiveStreamViewModel(modelContext: modelContext))) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text(NSLocalizedString("settings", comment: "설정"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    .font(.system(size: 14, weight: .medium))
                }
            }
        }
    }
    
}
