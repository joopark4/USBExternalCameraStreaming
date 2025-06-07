//
//  LiveStreamSettingsView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import UIKit
import Combine

/// 라이브 스트리밍 설정 뷰
/// 유튜브 RTMP 스트리밍을 위한 완전한 설정 관리 팝업
struct LiveStreamSettingsView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showResetAlert = false
    @State private var showTestConnectionAlert = false
    @State private var showHelpSheet = false
    @State private var selectedHelpTopic: String = "rtmpURL"
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 상태 표시
                    StatusSectionView(viewModel: viewModel)
                    
                    // 기본 설정
                    BasicSettingsSectionView(viewModel: viewModel)
                    
                    // 비디오 설정
                    VideoSettingsSectionView(viewModel: viewModel)
                    
                    // 오디오 설정
                    AudioSettingsSectionView(viewModel: viewModel)
                    
                    // 고급 설정
                    AdvancedSettingsSectionView(viewModel: viewModel)
                    
                    // 프리셋
                    PresetSectionView(viewModel: viewModel)
                    
                    // 액션 버튼들
                    ActionButtonsView(
                        viewModel: viewModel,
                        showTestConnectionAlert: $showTestConnectionAlert,
                        showResetAlert: $showResetAlert
                    )
                }
                .padding()
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
                    .disabled(!isValidConfiguration)
                    .fontWeight(.semibold)
                }
            }
        }
        .alert(NSLocalizedString("reset_settings_confirmation", comment: ""), isPresented: $showResetAlert) {
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("reset", comment: ""), role: .destructive) {
                viewModel.resetToDefaults()
            }
        } message: {
            Text(NSLocalizedString("reset_settings_message", comment: ""))
        }
        .alert(NSLocalizedString("connection_test", comment: ""), isPresented: $showTestConnectionAlert) {
            Button(NSLocalizedString("ok", comment: "")) { }
        } message: {
            Text(viewModel.connectionTestResult)
        }
        .sheet(isPresented: $showHelpSheet) {
            HelpDetailView(topic: selectedHelpTopic, viewModel: viewModel)
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(isValidConfiguration ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Text(isValidConfiguration ? NSLocalizedString("configuration_complete", comment: "") : NSLocalizedString("configuration_required", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(isValidConfiguration ? .green : .red)
                
                Spacer()
                
                if !isValidConfiguration {
                    Button(NSLocalizedString("help", comment: "")) {
                        showHelpSheet = true
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
                }
            }
            
            if viewModel.status != .idle {
                // 스트리밍 중일 때는 제한된 설정만 변경 가능
                Text("스트리밍 중에는 일부 설정을 변경할 수 없습니다")
                    .foregroundColor(.orange)
                    .font(.caption)
                    .padding(.bottom)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Connection Settings Section
    private var connectionSettingsSection: some View {
        SettingsSectionView(title: NSLocalizedString("connection_settings", comment: ""), icon: "link") {
            VStack(spacing: 16) {
                // 스트림 제목
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("stream_title", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(NSLocalizedString("optional", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    TextField(NSLocalizedString("stream_title_placeholder", comment: ""), text: $viewModel.settings.streamTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // RTMP 서버 URL
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("rtmp_server_url", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Button(action: {
                            selectedHelpTopic = "rtmpURL"
                            showHelpSheet = true
                        }) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        
                        Spacer()
                        if viewModel.validateRTMPURL(viewModel.settings.rtmpURL) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    
                    TextField("rtmp://a.rtmp.youtube.com/live2/", text: $viewModel.settings.rtmpURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                    
                    if !viewModel.validateRTMPURL(viewModel.settings.rtmpURL) {
                        Text(NSLocalizedString("rtmp_url_invalid", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                // 스트림 키
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("stream_key", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Button(action: {
                            selectedHelpTopic = "streamKey"
                            showHelpSheet = true
                        }) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        
                        Spacer()
                        if !viewModel.settings.streamKey.isEmpty && viewModel.validateStreamKey(viewModel.settings.streamKey) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else if !viewModel.settings.streamKey.isEmpty {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                    
                    SecureField(NSLocalizedString("stream_key_placeholder", comment: ""), text: $viewModel.settings.streamKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                    
                    if !viewModel.settings.streamKey.isEmpty && !viewModel.validateStreamKey(viewModel.settings.streamKey) {
                        Text(NSLocalizedString("stream_key_invalid", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
    
    // MARK: - Video Settings Section
    private var videoSettingsSection: some View {
        SettingsSectionView(title: NSLocalizedString("video_settings", comment: ""), icon: "video") {
            VStack(spacing: 16) {
                // 비트레이트 설정
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("video_bitrate", comment: ""))
                        Spacer()
                        Text("\(viewModel.settings.videoBitrate) kbps")
                            .foregroundColor(bitrateColor)
                            .fontWeight(.medium)
                    }
                    
                    // 비트레이트 슬라이더
                    Slider(value: Binding(
                        get: { Double(viewModel.settings.videoBitrate) },
                        set: { viewModel.settings.videoBitrate = Int($0) }
                    ), in: 500...10000, step: 100)
                    
                    // YouTube Live 권장사항 및 경고
                    bitrateWarningView
                }
                
                // 해상도 설정 (단순화)
                VStack(alignment: .leading, spacing: 8) {
                    Text("해상도")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text("\(viewModel.settings.videoWidth) × \(viewModel.settings.videoHeight)")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                // 프레임레이트
                VStack(alignment: .leading, spacing: 8) {
                    Text("프레임 레이트")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("프레임 레이트", selection: $viewModel.settings.frameRate) {
                        Text("24fps").tag(24)
                        Text("30fps").tag(30)
                        Text("60fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
    
    // MARK: - Audio Settings Section
    private var audioSettingsSection: some View {
        SettingsSectionView(title: NSLocalizedString("audio_settings", comment: ""), icon: "speaker.wave.2") {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("audio_bitrate_picker", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(viewModel.settings.audioBitrate) kbps")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                    
                    Picker(NSLocalizedString("audio_bitrate_picker", comment: ""), selection: $viewModel.settings.audioBitrate) {
                        Text(NSLocalizedString("kbps_64_low", comment: "")).tag(64)
                        Text(NSLocalizedString("kbps_128_standard", comment: "")).tag(128)
                        Text(NSLocalizedString("kbps_192_high", comment: "")).tag(192)
                        Text(NSLocalizedString("kbps_256_highest", comment: "")).tag(256)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
    
    // MARK: - Advanced Settings Section
    private var advancedSettingsSection: some View {
        SettingsSectionView(title: NSLocalizedString("advanced_settings", comment: ""), icon: "gear") {
            VStack(spacing: 16) {
                // 자동 재연결
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("auto_reconnect", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(NSLocalizedString("auto_reconnect_description", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.settings.autoReconnect)
                }
                
                // 스트리밍 활성화
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("streaming_enabled", comment: ""))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(NSLocalizedString("streaming_enabled_description", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.settings.isEnabled)
                }
            }
        }
    }
    
    // MARK: - Bottom Buttons Section
    private var bottomButtonsSection: some View {
        VStack(spacing: 12) {
            if isValidConfiguration {
                Button(NSLocalizedString("save", comment: "")) {
                    viewModel.saveSettings()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("required_items_message", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(missingRequirements, id: \.self) { requirement in
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text(requirement)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            Button(NSLocalizedString("reset_settings", comment: "")) {
                showResetAlert = true
            }
            .buttonStyle(DestructiveButtonStyle())
        }
    }
    
    // MARK: - Computed Properties
    private var isValidConfiguration: Bool {
        !viewModel.settings.streamKey.isEmpty &&
        viewModel.validateStreamKey(viewModel.settings.streamKey) &&
        viewModel.validateRTMPURL(viewModel.settings.rtmpURL)
    }
    
    private var missingRequirements: [String] {
        var requirements: [String] = []
        
        if viewModel.settings.streamKey.isEmpty {
            requirements.append(NSLocalizedString("stream_key", comment: ""))
        } else if !viewModel.validateStreamKey(viewModel.settings.streamKey) {
            requirements.append(NSLocalizedString("stream_key_invalid", comment: ""))
        }
        
        if !viewModel.validateRTMPURL(viewModel.settings.rtmpURL) {
            requirements.append(NSLocalizedString("rtmp_url_invalid", comment: ""))
        }
        
        return requirements
    }
    
    private var statusColor: Color {
        switch viewModel.status {
        case .idle: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .streaming: return .blue
        case .disconnecting: return .orange
        case .error: return .red
        }
    }
    
    // MARK: - Helper Methods
    private func getResolutionDimensions(_ resolution: ResolutionPreset) -> (width: Int, height: Int) {
        switch resolution {
        case .sd480p: return (854, 480)
        case .hd720p: return (1280, 720)
        case .fhd1080p: return (1920, 1080)
        case .uhd4k: return (3840, 2160)
        }
    }
    
    /// 비트레이트 색상 (권장사항 기준)
    private var bitrateColor: Color {
        switch viewModel.settings.videoBitrate {
        case 1500...4000: return .green      // YouTube Live 권장 범위
        case 1000..<1500: return .orange     // 낮음
        default: return .red                 // 너무 높음
        }
    }
    
    /// 비트레이트 경고 및 권장사항 뷰
    @ViewBuilder
    private var bitrateWarningView: some View {
        if viewModel.settings.videoBitrate > 4000 {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚠️ 비트레이트가 너무 높습니다")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    Text("YouTube Live에서 연결이 끊어질 수 있습니다. 권장: 1500-4000 kbps")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        } else if viewModel.settings.videoBitrate >= 1500 && viewModel.settings.videoBitrate <= 4000 {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("✅ YouTube Live 1080p 권장 범위")
                    .font(.caption)
                    .foregroundColor(.green)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        } else {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                Text("📹 낮은 비트레이트 - 화질이 떨어질 수 있습니다")
                    .font(.caption)
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        
        // 빠른 설정 버튼들
        HStack(spacing: 12) {
            Button("720p (1000)") {
                viewModel.settings.videoBitrate = 1000
                viewModel.settings.videoWidth = 1280
                viewModel.settings.videoHeight = 720
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(4)
            
            Button("1080p (1500)") {
                viewModel.settings.videoBitrate = 1500
                viewModel.settings.videoWidth = 1920
                viewModel.settings.videoHeight = 1080
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.1))
            .foregroundColor(.green)
            .cornerRadius(4)
            
            Button("1080p (2500)") {
                viewModel.settings.videoBitrate = 2500
                viewModel.settings.videoWidth = 1920
                viewModel.settings.videoHeight = 1080
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(4)
            
            Spacer()
        }
    }
}

// MARK: - Supporting Views

/// 상태 표시 섹션
struct StatusSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        SettingsSectionView(title: NSLocalizedString("status", comment: ""), icon: "antenna.radiowaves.left.and.right") {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(viewModel.statusMessage)
                    .font(.body)
                Spacer()
            }
        }
    }
    
    private var statusColor: Color {
        switch viewModel.status {
        case .idle: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .streaming: return .blue
        case .disconnecting: return .orange
        case .error: return .red
        }
    }
}

/// 기본 설정 섹션
struct BasicSettingsSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        SettingsSectionView(title: NSLocalizedString("basic_settings", comment: ""), icon: "gear") {
            VStack(spacing: 16) {
                // RTMP URL
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("rtmp_url", comment: ""))
                        .font(.headline)
                    TextField(NSLocalizedString("rtmp_url_placeholder", comment: ""), text: $viewModel.settings.rtmpURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                // Stream Key
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("stream_key", comment: ""))
                        .font(.headline)
                    SecureField(NSLocalizedString("stream_key_placeholder", comment: ""), text: $viewModel.settings.streamKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
    }
}

/// 비디오 설정 섹션
struct VideoSettingsSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        SettingsSectionView(title: NSLocalizedString("video_settings", comment: ""), icon: "video") {
            VStack(spacing: 16) {
                // 비트레이트 설정
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("video_bitrate", comment: ""))
                        Spacer()
                        Text("\(viewModel.settings.videoBitrate) kbps")
                            .foregroundColor(bitrateColor)
                            .fontWeight(.medium)
                    }
                    
                    // 비트레이트 슬라이더
                    Slider(value: Binding(
                        get: { Double(viewModel.settings.videoBitrate) },
                        set: { viewModel.settings.videoBitrate = Int($0) }
                    ), in: 500...10000, step: 100)
                    
                    // YouTube Live 권장사항 및 경고
                    bitrateWarningView
                }
                
                // 해상도 설정 (단순화)
                VStack(alignment: .leading, spacing: 8) {
                    Text("해상도")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text("\(viewModel.settings.videoWidth) × \(viewModel.settings.videoHeight)")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                
                // 프레임레이트
                VStack(alignment: .leading, spacing: 8) {
                    Text("프레임 레이트")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("프레임 레이트", selection: $viewModel.settings.frameRate) {
                        Text("24fps").tag(24)
                        Text("30fps").tag(30)
                        Text("60fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
    
    /// 비트레이트 색상 (권장사항 기준)
    private var bitrateColor: Color {
        switch viewModel.settings.videoBitrate {
        case 1500...4000: return .green      // YouTube Live 권장 범위
        case 1000..<1500: return .orange     // 낮음
        default: return .red                 // 너무 높음
        }
    }
    
    /// 비트레이트 경고 및 권장사항 뷰
    @ViewBuilder
    private var bitrateWarningView: some View {
        if viewModel.settings.videoBitrate > 4000 {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚠️ 비트레이트가 너무 높습니다")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    Text("YouTube Live에서 연결이 끊어질 수 있습니다. 권장: 1500-4000 kbps")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        } else if viewModel.settings.videoBitrate >= 1500 && viewModel.settings.videoBitrate <= 4000 {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("✅ YouTube Live 1080p 권장 범위")
                    .font(.caption)
                    .foregroundColor(.green)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        } else {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.orange)
                Text("📹 낮은 비트레이트 - 화질이 떨어질 수 있습니다")
                    .font(.caption)
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
        
        // 빠른 설정 버튼들
        HStack(spacing: 12) {
            Button("720p (1000)") {
                viewModel.settings.videoBitrate = 1000
                viewModel.settings.videoWidth = 1280
                viewModel.settings.videoHeight = 720
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(4)
            
            Button("1080p (1500)") {
                viewModel.settings.videoBitrate = 1500
                viewModel.settings.videoWidth = 1920
                viewModel.settings.videoHeight = 1080
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.1))
            .foregroundColor(.green)
            .cornerRadius(4)
            
            Button("1080p (2500)") {
                viewModel.settings.videoBitrate = 2500
                viewModel.settings.videoWidth = 1920
                viewModel.settings.videoHeight = 1080
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(4)
            
            Spacer()
        }
    }
}

/// 오디오 설정 섹션
struct AudioSettingsSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        SettingsSectionView(title: NSLocalizedString("audio_settings", comment: ""), icon: "speaker.wave.2") {
            VStack(spacing: 16) {
                HStack {
                    Text(NSLocalizedString("audio_bitrate", comment: ""))
                    Spacer()
                    Text("\(viewModel.settings.audioBitrate) kbps")
                        .foregroundColor(.secondary)
                }
                
                Slider(value: Binding(
                    get: { Double(viewModel.settings.audioBitrate) },
                    set: { viewModel.settings.audioBitrate = Int($0) }
                ), in: 64...320, step: 32)
            }
        }
    }
}

/// 고급 설정 섹션
struct AdvancedSettingsSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        SettingsSectionView(title: NSLocalizedString("advanced_settings", comment: ""), icon: "gearshape.2") {
            VStack(spacing: 16) {
                HStack {
                    Text(NSLocalizedString("frame_rate", comment: ""))
                    Spacer()
                    Text("\(viewModel.settings.frameRate) fps")
                        .foregroundColor(.secondary)
                }
                
                Picker(NSLocalizedString("frame_rate", comment: ""), selection: $viewModel.settings.frameRate) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
    }
}

/// 프리셋 섹션
struct PresetSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        SettingsSectionView(title: NSLocalizedString("presets", comment: ""), icon: "slider.horizontal.3") {
            Text(NSLocalizedString("preset_description", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// 액션 버튼 섹션
struct ActionButtonsView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    @Binding var showTestConnectionAlert: Bool
    @Binding var showResetAlert: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Button(NSLocalizedString("test_connection", comment: "")) {
                Task {
                    await viewModel.testConnection()
                    showTestConnectionAlert = true
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            
            Button(NSLocalizedString("reset_settings", comment: "")) {
                showResetAlert = true
            }
            .buttonStyle(DestructiveButtonStyle())
        }
    }
}

/// 설정 섹션 래퍼 뷰
struct SettingsSectionView<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            content
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(Color.blue)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.red)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color.red.opacity(0.1))
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Help Detail View

struct HelpDetailView: View {
    let topic: String
    let viewModel: LiveStreamViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let helpContent = getHelpContentFor(topic)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(helpContent.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(helpContent.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    if !helpContent.recommendedValues.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("recommended_settings_help", comment: "권장 설정"))
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            ForEach(helpContent.recommendedValues, id: \.self) { value in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text(value)
                                        .font(.body)
                                }
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("help", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func getHelpContentFor(_ topic: String) -> (title: String, description: String, recommendedValues: [String]) {
        switch topic {
        case "rtmpURL":
            return (
                title: "RTMP 서버 URL",
                description: "RTMP 스트리밍을 위한 서버 URL입니다. 유튜브 스트리밍을 위해서는 이 URL을 사용해야 합니다.",
                recommendedValues: [
                    "rtmp://a.rtmp.youtube.com/live2/"
                ]
            )
        case "streamKey":
            return (
                title: "스트림 키",
                description: "스트림을 식별하는 고유한 키입니다. 유튜브 스트리밍을 위해서는 이 키를 사용해야 합니다.",
                recommendedValues: []
            )
        default:
            return (
                title: "설정 도움말",
                description: "이 설정에 대한 자세한 정보가 필요합니다.",
                recommendedValues: []
            )
        }
    }
} 
