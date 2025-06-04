//
//  LiveStreamSettingsView.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import SwiftUI
import AVFoundation

/// 라이브 스트리밍 설정 뷰
/// 유튜브 RTMP 스트리밍을 위한 설정을 관리합니다.
struct LiveStreamSettingsView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // 기본 설정 섹션
                Section(NSLocalizedString("basic_settings", comment: "")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("stream_title", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("stream_title_placeholder", comment: ""), text: $viewModel.settings.streamTitle)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("stream_key", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField(NSLocalizedString("stream_key_placeholder", comment: ""), text: $viewModel.settings.streamKey)
                            .textFieldStyle(.roundedBorder)
                        
                        if !viewModel.settings.streamKey.isEmpty && !viewModel.validateStreamKey(viewModel.settings.streamKey) {
                            Text(NSLocalizedString("stream_key_invalid", comment: ""))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("rtmp_server_url", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(NSLocalizedString("rtmp_url_placeholder", comment: ""), text: $viewModel.settings.rtmpURL)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                        
                        if !viewModel.validateRTMPURL(viewModel.settings.rtmpURL) {
                            Text(NSLocalizedString("rtmp_url_invalid", comment: ""))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // 비디오 설정 섹션
                Section(NSLocalizedString("video_settings", comment: "")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("resolution", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker(NSLocalizedString("resolution", comment: ""), selection: Binding(
                            get: {
                                VideoResolution.allCases.first { resolution in
                                    resolution.width == viewModel.settings.videoWidth &&
                                    resolution.height == viewModel.settings.videoHeight
                                } ?? .fullHD
                            },
                            set: { resolution in
                                viewModel.settings.videoWidth = resolution.width
                                viewModel.settings.videoHeight = resolution.height
                            }
                        )) {
                            ForEach(VideoResolution.allCases, id: \.self) { resolution in
                                Text(resolution.displayName).tag(resolution)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: NSLocalizedString("video_bitrate", comment: ""), viewModel.settings.videoBitrate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.videoBitrate) },
                                set: { viewModel.settings.videoBitrate = Int($0) }
                            ),
                            in: 500...10000,
                            step: 100
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: NSLocalizedString("frame_rate", comment: ""), viewModel.settings.frameRate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker(NSLocalizedString("frame_rate_picker", comment: ""), selection: $viewModel.settings.frameRate) {
                            Text(NSLocalizedString("fps_24", comment: "")).tag(24)
                            Text(NSLocalizedString("fps_30", comment: "")).tag(30)
                            Text(NSLocalizedString("fps_60", comment: "")).tag(60)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                // 오디오 설정 섹션
                Section(NSLocalizedString("audio_settings", comment: "")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: NSLocalizedString("audio_bitrate", comment: ""), viewModel.settings.audioBitrate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker(NSLocalizedString("audio_bitrate_picker", comment: ""), selection: $viewModel.settings.audioBitrate) {
                            Text(NSLocalizedString("kbps_64", comment: "")).tag(64)
                            Text(NSLocalizedString("kbps_128", comment: "")).tag(128)
                            Text(NSLocalizedString("kbps_192", comment: "")).tag(192)
                            Text(NSLocalizedString("kbps_256", comment: "")).tag(256)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                // 고급 설정 섹션
                Section(NSLocalizedString("advanced_settings", comment: "")) {
                    Toggle(NSLocalizedString("auto_reconnect", comment: ""), isOn: $viewModel.settings.autoReconnect)
                        .toggleStyle(SwitchToggleStyle())
                    
                    Toggle(NSLocalizedString("streaming_enabled", comment: ""), isOn: $viewModel.settings.isEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                // 설정 관리 섹션
                Section(NSLocalizedString("settings_management", comment: "")) {
                    Button(NSLocalizedString("reset_settings", comment: "")) {
                        viewModel.resetSettings()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle(NSLocalizedString("live_streaming_settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("save", comment: "")) {
                        viewModel.saveSettings()
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}

/// 라이브 스트리밍 컨트롤 뷰
/// 스트리밍 시작/중지 및 상태 표시를 담당합니다.
struct LiveStreamControlView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    let captureSession: AVCaptureSession?
    
    var body: some View {
        VStack(spacing: 16) {
            // 스트리밍 상태 표시
            HStack {
                Image(systemName: viewModel.streamingStatus.iconName)
                    .foregroundColor(statusColor)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.streamingStatus.description)
                        .font(.headline)
                        .foregroundColor(statusColor)
                    
                    if !viewModel.statusMessage.isEmpty {
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            // 스트리밍 통계 (스트리밍 중일 때만 표시)
            if viewModel.streamingStatus == .streaming {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("streaming_statistics", comment: ""))
                        .font(.headline)
                    
                    Text(viewModel.formatStreamStats())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
            
            // 컨트롤 버튼
            HStack(spacing: 16) {
                Button(action: {
                    if let session = captureSession {
                        viewModel.toggleStreaming(with: session)
                    }
                }) {
                    HStack {
                        Image(systemName: streamButtonIcon)
                        Text(viewModel.streamControlButtonText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.streamControlButtonColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(!viewModel.isStreamControlButtonEnabled || captureSession == nil)
                
                Button(NSLocalizedString("settings", comment: "")) {
                    viewModel.showingSettings = true
                }
                .frame(width: 80)
                .padding()
                .background(Color.secondary.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(8)
            }
        }
        .padding()
        .sheet(isPresented: $viewModel.showingSettings) {
            LiveStreamSettingsView(viewModel: viewModel)
        }
        .alert(NSLocalizedString("streaming_error", comment: ""), isPresented: $viewModel.showingErrorAlert) {
            Button(NSLocalizedString("ok", comment: "")) { }
        } message: {
            Text(viewModel.currentErrorMessage)
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        switch viewModel.streamingStatus {
        case .idle:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .streaming:
            return .blue
        case .disconnecting:
            return .orange
        case .error:
            return .red
        }
    }
    
    private var streamButtonIcon: String {
        switch viewModel.streamingStatus {
        case .idle, .error:
            return "play.circle.fill"
        case .streaming, .connected, .connecting:
            return "stop.circle.fill"
        case .disconnecting:
            return "stop.circle"
        }
    }
}

#Preview {
    // Preview를 위한 더미 뷰모델
    struct PreviewWrapper: View {
        @State private var dummyViewModel: LiveStreamViewModel?
        
        var body: some View {
            Group {
                if let viewModel = dummyViewModel {
                    LiveStreamSettingsView(viewModel: viewModel)
                } else {
                    ProgressView()
                        .onAppear {
                            // Preview용 더미 ModelContext 생성 (실제 앱에서는 사용하지 않음)
                            // dummyViewModel = LiveStreamViewModel(modelContext: dummyContext)
                        }
                }
            }
        }
    }
    
    return PreviewWrapper()
} 