import SwiftUI
import AVFoundation
import LiveStreamingCore

extension LiveStreamView {
    // MARK: - RTMP Debugging Section
    
    private var rtmpDebuggingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network.badge.shield.half.filled")
                    .foregroundColor(.orange)
                Text(NSLocalizedString("rtmp_connection_debug", comment: "RTMP 연결 디버깅"))
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Spacer()
                
                // RTMP 연결 테스트 버튼
                Button(action: {
                    Task {
                        await testRTMPConnection()
                    }
                }) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(NSLocalizedString("test_connection", comment: "연결 테스트"))
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            
            VStack(spacing: 8) {
                // 기본 설정 정보
                rtmpSettingsCard
                
                // 실시간 연결 상태 (스트리밍 중일 때만)
                if viewModel.isScreenCaptureStreaming {
                    rtmpStatusCard
                }
                
                // 상세 디버그 정보 (스트리밍 중일 때만)
                if viewModel.isScreenCaptureStreaming {
                    rtmpDebugCard
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var rtmpSettingsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.blue)
                Text(NSLocalizedString("rtmp_settings", comment: "RTMP 설정"))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Group {
                HStack {
                    Text("URL:")
                        .fontWeight(.medium)
                        .frame(width: 60, alignment: .leading)
                    Text(viewModel.settings.rtmpURL.isEmpty ? NSLocalizedString("not_configured", comment: "설정되지 않음") : viewModel.settings.rtmpURL)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(viewModel.settings.rtmpURL.isEmpty ? .red : .primary)
                }
                
                HStack {
                    Text(NSLocalizedString("stream_key_label", comment: "스트림 키:"))
                        .fontWeight(.medium)
                        .frame(width: 60, alignment: .leading)
                    Text(viewModel.settings.streamKey.isEmpty ? NSLocalizedString("not_configured", comment: "설정되지 않음") : "\(viewModel.settings.streamKey.count)자 (\(String(viewModel.settings.streamKey.prefix(8)))...)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(viewModel.settings.streamKey.isEmpty ? .red : .primary)
                }
                
                HStack {
                    Text(NSLocalizedString("validity_label", comment: "유효성:"))
                        .fontWeight(.medium)
                        .frame(width: 60, alignment: .leading)
                    
                    if viewModel.validateRTMPURL(viewModel.settings.rtmpURL) && viewModel.validateStreamKey(viewModel.settings.streamKey) {
                        Label("설정 완료", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("설정 필요", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var rtmpStatusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.green)
                Text(NSLocalizedString("connection_status", comment: "연결 상태"))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // HaishinKitManager에서 연결 상태 가져오기
            if let haishinKitManager = viewModel.liveStreamService as? HaishinKitManager {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(NSLocalizedString("status_label", comment: "상태:"))
                            .fontWeight(.medium)
                            .frame(width: 60, alignment: .leading)
                        Text(haishinKitManager.connectionStatus)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("broadcast_label", comment: "송출:"))
                            .fontWeight(.medium)
                            .frame(width: 60, alignment: .leading)
                        Text(NSLocalizedString("screen_capture_streaming", comment: "화면 캡처 스트리밍 중"))
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            } else {
                                        Text(NSLocalizedString("streaming_manager_not_initialized", comment: "스트리밍 매니저가 초기화되지 않음"))
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var rtmpDebugCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "ladybug")
                    .foregroundColor(.purple)
                Text(NSLocalizedString("debug_info", comment: "디버그 정보"))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // HaishinKitManager에서 디버그 정보 가져오기
            if viewModel.liveStreamService is HaishinKitManager {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(NSLocalizedString("screen_capture_streaming_enabled", comment: "화면 캡처 스트리밍 활성화됨"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 4)
                }
            } else {
                Text(NSLocalizedString("debug_info_unavailable", comment: "디버그 정보를 사용할 수 없음"))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(8)
    }
    
}
