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
                    
                    // 유튜브 권장 송출 셋업 프리셋
                    YouTubePresetSectionView(viewModel: viewModel)
                    
                    // 비디오 설정
                    VideoSettingsSectionView(viewModel: viewModel)
                    
                    // 오디오 설정
                    AudioSettingsSectionView(viewModel: viewModel)
                    
                    // 하드웨어 최적화 상태
                    HardwareOptimizationSectionView(viewModel: viewModel)
                    
                    // 액션 버튼들
                    ActionButtonsView(
                        viewModel: viewModel,
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
                Text(NSLocalizedString("streaming_settings_limited", comment: "스트리밍 중에는 일부 설정을 변경할 수 없습니다"))
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
                    Text(NSLocalizedString("resolution", comment: "해상도"))
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
                    Text(NSLocalizedString("frame_rate", comment: "프레임 레이트"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker(NSLocalizedString("frame_rate", comment: "프레임 레이트"), selection: $viewModel.settings.frameRate) {
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
        case .sd480p: return (848, 480)
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
                    Text(NSLocalizedString("bitrate_too_high_warning", comment: "⚠️ 비트레이트가 너무 높습니다"))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    Text(NSLocalizedString("youtube_bitrate_warning", comment: "YouTube Live에서 연결이 끊어질 수 있습니다. 권장: 1500-4000 kbps"))
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
                Text(NSLocalizedString("youtube_recommended_range", comment: "✅ YouTube Live 1080p 권장 범위"))
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
                Text(NSLocalizedString("low_bitrate_warning", comment: "📹 낮은 비트레이트 - 화질이 떨어질 수 있습니다"))
                    .font(.caption)
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
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
                    HStack {
                        Text(NSLocalizedString("stream_key", comment: ""))
                            .font(.headline)
                        Spacer()
                        // 스트림 키 검증 상태 표시
                        streamKeyValidationIcon
                    }
                    SecureField(NSLocalizedString("stream_key_placeholder", comment: ""), text: $viewModel.settings.streamKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: viewModel.settings.streamKey) { oldValue, newValue in
                            // 실시간 스트림 키 정제
                            let cleaned = cleanStreamKey(newValue)
                            if cleaned != newValue {
                                viewModel.settings.streamKey = cleaned
                            }
                        }
                    
                    // 스트림 키 상태 메시지
                    if !viewModel.settings.streamKey.isEmpty {
                        streamKeyValidationMessage
                    }
                }
            }
        }
    }
    
    /// 스트림 키 검증 아이콘
    @ViewBuilder
    private var streamKeyValidationIcon: some View {
        let key = viewModel.settings.streamKey
        let isValid = isValidStreamKey(key)
        
        if key.isEmpty {
            Image(systemName: "key")
                .foregroundColor(.gray)
        } else if isValid {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }
    
    /// 스트림 키 검증 메시지
    @ViewBuilder
    private var streamKeyValidationMessage: some View {
        let key = viewModel.settings.streamKey
        let isValid = isValidStreamKey(key)
        let cleanedLength = cleanStreamKey(key).count
        
        if !isValid {
            VStack(alignment: .leading, spacing: 4) {
                if key.count != cleanedLength {
                    Text("⚠️ 공백이나 특수문자가 제거되었습니다")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                if cleanedLength < 16 {
                    Text("❌ 스트림 키가 너무 짧습니다 (16자 이상 필요)")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if cleanedLength > 50 {
                    Text("⚠️ 스트림 키가 너무 깁니다 (50자 이하 권장)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        } else {
            Text("✅ 유효한 스트림 키입니다 (\(cleanedLength)자)")
                .font(.caption)
                .foregroundColor(.green)
        }
    }
    
    /// 스트림 키 정제 함수
    private func cleanStreamKey(_ streamKey: String) -> String {
        // 앞뒤 공백 제거
        let trimmed = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 보이지 않는 특수 문자 제거
        let cleaned = trimmed.components(separatedBy: .controlCharacters).joined()
            .components(separatedBy: CharacterSet(charactersIn: "\u{FEFF}\u{200B}\u{200C}\u{200D}")).joined()
        
        return cleaned
    }
    
    /// 스트림 키 유효성 검사
    private func isValidStreamKey(_ streamKey: String) -> Bool {
        let cleaned = cleanStreamKey(streamKey)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        
        return cleaned.count >= 16 && 
               cleaned.count <= 50 &&
               cleaned.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
}

/// 비디오 설정 섹션
struct VideoSettingsSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        SettingsSectionView(title: NSLocalizedString("video_settings", comment: ""), icon: "video") {
            VStack(spacing: 16) {
                // 해상도 선택
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("resolution", comment: "해상도"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 8) {
                        // 480p 버튼
                        ResolutionButton(
                            title: "480p",
                            subtitle: "848×480",
                            isSelected: currentResolution == .resolution480p,
                            action: {
                                setResolution(.resolution480p)
                            }
                        )
                        
                        // 720p 버튼
                        ResolutionButton(
                            title: "720p",
                            subtitle: "1280×720",
                            isSelected: currentResolution == .resolution720p,
                            action: {
                                setResolution(.resolution720p)
                            }
                        )
                        
                        // 1080p 버튼 (비활성화 - 성능상 문제로 사용 금지)
                        ResolutionButton(
                            title: "1080p",
                            subtitle: "1920×1080",
                            isSelected: false,
                            isEnabled: false,
                            action: {}
                        )
                    }
                }
                
                // 프레임레이트
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("frame_rate", comment: "프레임 레이트"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 8) {
                        FrameRateButton(
                            title: "24fps",
                            frameRate: 24,
                            isSelected: viewModel.settings.frameRate == 24,
                            isEnabled: isFrameRateSupported(24),
                            action: {
                                viewModel.settings.frameRate = 24
                            }
                        )
                        
                        FrameRateButton(
                            title: "30fps",
                            frameRate: 30,
                            isSelected: viewModel.settings.frameRate == 30,
                            isEnabled: isFrameRateSupported(30),
                            action: {
                                viewModel.settings.frameRate = 30
                            }
                        )
                        
                        FrameRateButton(
                            title: "60fps",
                            frameRate: 60,
                            isSelected: false,
                            isEnabled: false,
                            action: {}
                        )
                    }
                }
                
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
            }
        }
    }
    
    // MARK: - Helper Properties and Methods
    
    private enum Resolution {
        case resolution480p, resolution720p, resolution1080p
    }
    
    private var currentResolution: Resolution {
        let width = viewModel.settings.videoWidth
        let height = viewModel.settings.videoHeight
        
        if (width == 854 || width == 848) && height == 480 {
            return .resolution480p
        } else if width == 1280 && height == 720 {
            return .resolution720p
        } else if width == 1920 && height == 1080 {
            return .resolution1080p
        } else {
            // 기본값은 720p
            return .resolution720p
        }
    }
    
    private func setResolution(_ resolution: Resolution) {
        switch resolution {
        case .resolution480p:
            viewModel.settings.videoWidth = 848  // 16의 배수 (854 → 848)
            viewModel.settings.videoHeight = 480
            viewModel.settings.videoBitrate = 1500
            // 480p는 60fps 지원하지 않음
            if viewModel.settings.frameRate == 60 {
                viewModel.settings.frameRate = 30
            }
        case .resolution720p:
            viewModel.settings.videoWidth = 1280
            viewModel.settings.videoHeight = 720
            viewModel.settings.videoBitrate = 2500
        case .resolution1080p:
            viewModel.settings.videoWidth = 1920
            viewModel.settings.videoHeight = 1080
            viewModel.settings.videoBitrate = 4500
        }
    }
    
    private func isFrameRateSupported(_ frameRate: Int) -> Bool {
        switch currentResolution {
        case .resolution480p:
            // 480p는 24fps, 30fps만 지원
            return frameRate == 24 || frameRate == 30
        case .resolution720p, .resolution1080p:
            // 720p, 1080p는 모든 프레임률 지원
            return true
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

/// 액션 버튼 섹션
struct ActionButtonsView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    @Binding var showResetAlert: Bool
    
    var body: some View {
        VStack(spacing: 12) {
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

/// 해상도 선택 버튼
struct ResolutionButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    init(title: String, subtitle: String, isSelected: Bool, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }
    
    var body: some View {
        Button(action: isEnabled ? action : {}) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isEnabled ? (isSelected ? .white : .primary) : .gray)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(isEnabled ? (isSelected ? .white.opacity(0.8) : .secondary) : .gray.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isEnabled ? 
                    (isSelected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground)) :
                    Color.gray.opacity(0.1)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isEnabled ? (isSelected ? Color.clear : Color.gray.opacity(0.3)) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }
}

/// 프레임률 선택 버튼
struct FrameRateButton: View {
    let title: String
    let frameRate: Int
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(buttonTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(buttonBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(buttonBorderColor, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }
    
    private var buttonTextColor: Color {
        if !isEnabled {
            return .gray
        } else if isSelected {
            return .white
        } else {
            return .primary
        }
    }
    
    private var buttonBackground: Color {
        if !isEnabled {
            return Color.gray.opacity(0.1)
        } else if isSelected {
            return Color.accentColor
        } else {
            return Color(UIColor.secondarySystemGroupedBackground)
        }
    }
    
    private var buttonBorderColor: Color {
        if !isEnabled {
            return Color.gray.opacity(0.2)
        } else if isSelected {
            return Color.clear
        } else {
            return Color.gray.opacity(0.3)
        }
    }
}

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

// MARK: - YouTube Preset Section

/// 유튜브 권장 송출 셋업 프리셋 섹션
struct YouTubePresetSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        SettingsSectionView(title: NSLocalizedString("youtube_preset_title", comment: "YouTube 권장 송출 설정"), icon: "play.rectangle.fill") {
            VStack(spacing: 16) {
                // 설명 텍스트
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(NSLocalizedString("youtube_preset_description", comment: "YouTube Live에 최적화된 송출 설정을 빠르게 적용할 수 있습니다"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    // 커스텀 설정일 때 추가 안내문구
                    if isCustomSettings {
                        HStack {
                            Image(systemName: "gearshape")
                                .foregroundColor(.purple)
                                .font(.caption)
                            Text(NSLocalizedString("custom_settings_notice", comment: "현재 사용자가 직접 설정한 값을 사용 중입니다"))
                                .font(.caption)
                                .foregroundColor(.purple)
                            Spacer()
                        }
                    }
                }
                .padding(.bottom, 4)
                
                // 프리셋 버튼들
                VStack(spacing: 12) {
                    // 480p 프리셋
                    YouTubePresetCard(
                        title: "480p (SD)",
                                                    subtitle: "848×480 • 30fps • 1,000 kbps",
                        description: "저화질 • 안정적인 연결",
                        icon: "play.square",
                        color: .orange,
                        isSelected: isCurrentPreset(.sd480p),
                        action: {
                            applyYouTubePreset(.sd480p)
                        }
                    )
                    
                    // 720p 프리셋
                    YouTubePresetCard(
                        title: "720p (HD)",
                        subtitle: "1280×720 • 30fps • 2,500 kbps",
                        description: "표준화질 • 권장 설정",
                        icon: "play.square.fill",
                        color: .green,
                        isSelected: isCurrentPreset(.hd720p),
                        action: {
                            applyYouTubePreset(.hd720p)
                        }
                    )
                    
                    // 1080p 프리셋 (비활성화 - 향후 지원 예정)
                    YouTubePresetCard(
                        title: "1080p (Full HD)",
                        subtitle: "1920×1080 • 30fps • 4,500 kbps",
                        description: "지원 예정",
                        icon: "play.square.stack",
                        color: .gray,
                        isSelected: false,
                        isEnabled: false,
                        action: {}
                    )
                    
                    // 커스텀 설정 (현재 설정이 어떤 프리셋과도 일치하지 않을 때)
                    if isCustomSettings {
                        YouTubePresetCard(
                            title: NSLocalizedString("custom_settings", comment: "사용자 설정"),
                            subtitle: currentSettingsDescription,
                            description: NSLocalizedString("custom_settings_description", comment: "사용자가 직접 설정한 값"),
                            icon: "gearshape.fill",
                            color: .purple,
                            isSelected: true,
                            action: {
                                // 커스텀 설정은 이미 적용된 상태이므로 아무 작업 없음
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isCurrentPreset(_ preset: YouTubeLivePreset) -> Bool {
        let settings = preset.settings
        return viewModel.settings.videoWidth == settings.width &&
               viewModel.settings.videoHeight == settings.height &&
               viewModel.settings.frameRate == settings.frameRate &&
               viewModel.settings.videoBitrate == settings.videoBitrate
    }
    
    /// 현재 설정이 어떤 프리셋과도 일치하지 않는지 확인
    private var isCustomSettings: Bool {
        return !isCurrentPreset(.sd480p) && 
               !isCurrentPreset(.hd720p) && 
               !isCurrentPreset(.fhd1080p)
    }
    
    /// 현재 커스텀 설정의 설명
    private var currentSettingsDescription: String {
        return "\(viewModel.settings.videoWidth)×\(viewModel.settings.videoHeight) • \(viewModel.settings.frameRate)fps • \(viewModel.settings.videoBitrate) kbps"
    }
    
    private func applyYouTubePreset(_ preset: YouTubeLivePreset) {
        let settings = preset.settings
        
        viewModel.settings.videoWidth = settings.width
        viewModel.settings.videoHeight = settings.height
        viewModel.settings.frameRate = settings.frameRate
        viewModel.settings.videoBitrate = settings.videoBitrate
        viewModel.settings.audioBitrate = settings.audioBitrate
        
        // 유튜브 최적화 기본 설정
        viewModel.settings.videoEncoder = "H.264"
        viewModel.settings.audioEncoder = "AAC"
        viewModel.settings.autoReconnect = true
        viewModel.settings.connectionTimeout = 30
        viewModel.settings.bufferSize = 3
        
        // 설정 저장
        viewModel.saveSettings()
    }
}

/// 유튜브 프리셋 카드
struct YouTubePresetCard: View {
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    init(title: String, subtitle: String, description: String, icon: String, color: Color, isSelected: Bool, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.icon = icon
        self.color = color
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }
    
    var body: some View {
        Button(action: isEnabled ? action : {}) {
            HStack(spacing: 12) {
                // 아이콘
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isEnabled ? (isSelected ? .white : color) : .gray)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(isEnabled ? (isSelected ? color : color.opacity(0.1)) : Color.gray.opacity(0.1))
                    )
                
                // 텍스트 정보
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isEnabled ? (isSelected ? .white : .primary) : .gray)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isEnabled ? (isSelected ? .white.opacity(0.8) : .secondary) : .gray.opacity(0.7))
                    
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(isEnabled ? (isSelected ? .white.opacity(0.7) : color) : .gray.opacity(0.6))
                }
                
                Spacer()
                
                // 선택 표시
                if isSelected && isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                } else if !isEnabled {
                    Image(systemName: "minus.circle")
                        .font(.title3)
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled ? (isSelected ? color : Color(UIColor.secondarySystemGroupedBackground)) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnabled ? (isSelected ? Color.clear : color.opacity(0.3)) : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }
}

/// 하드웨어 최적화 상태 섹션
struct HardwareOptimizationSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        SettingsSectionView(title: "하드웨어 품질 최적화", icon: "cpu") {
            VStack(spacing: 16) {
                // 설명 텍스트
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("스트리밍 설정에 맞춰 카메라와 마이크 하드웨어 품질이 자동으로 최적화됩니다")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(.bottom, 4)
                
                // 최적화 상태 카드들
                VStack(spacing: 12) {
                    // 비디오 하드웨어 최적화
                    HardwareOptimizationCard(
                        title: "비디오 하드웨어",
                        currentSetting: "\(viewModel.settings.videoWidth)×\(viewModel.settings.videoHeight) @ \(viewModel.settings.frameRate)fps",
                        optimizationLevel: getVideoOptimizationLevel(),
                        description: getVideoOptimizationDescription(),
                        icon: "camera.circle.fill",
                        color: getVideoOptimizationColor()
                    )
                    
                    // 오디오 하드웨어 최적화
                    HardwareOptimizationCard(
                        title: "오디오 하드웨어",
                        currentSetting: "\(viewModel.settings.audioBitrate) kbps",
                        optimizationLevel: getAudioOptimizationLevel(),
                        description: getAudioOptimizationDescription(),
                        icon: "mic.circle.fill",
                        color: getAudioOptimizationColor()
                    )
                    
                    // 전체 최적화 상태
                    HardwareOptimizationCard(
                        title: "전체 최적화 상태",
                        currentSetting: getOverallOptimizationStatus(),
                        optimizationLevel: getOverallOptimizationLevel(),
                        description: getOverallOptimizationDescription(),
                        icon: "gearshape.circle.fill",
                        color: getOverallOptimizationColor()
                    )
                }
            }
        }
    }
    
    // MARK: - 비디오 최적화 관련
    
    private func getVideoOptimizationLevel() -> String {
        let pixels = viewModel.settings.videoWidth * viewModel.settings.videoHeight
        let fps = viewModel.settings.frameRate
        
        switch (pixels, fps) {
        case (0..<(1280*720), 0..<30):
            return "저해상도 모드"
        case (0..<(1920*1080), 0..<30):
            return "표준 HD 모드"
        case (0..<(1920*1080), 30...):
            return "고프레임 모드"
        case ((1920*1080)..., _):
            return "고해상도 모드"
        default:
            return "사용자 정의"
        }
    }
    
    private func getVideoOptimizationDescription() -> String {
        let pixels = viewModel.settings.videoWidth * viewModel.settings.videoHeight
        
        if pixels >= 1920*1080 {
            return "카메라 1080p 프리셋 + 연속 자동 포커스"
        } else if pixels >= 1280*720 {
            return "카메라 720p 프리셋 + 자동 포커스"
        } else {
            return "카메라 VGA 프리셋 + 기본 설정"
        }
    }
    
    private func getVideoOptimizationColor() -> Color {
        let pixels = viewModel.settings.videoWidth * viewModel.settings.videoHeight
        
        if pixels >= 1920*1080 {
            return .blue
        } else if pixels >= 1280*720 {
            return .green
        } else {
            return .orange
        }
    }
    
    // MARK: - 오디오 최적화 관련
    
    private func getAudioOptimizationLevel() -> String {
        switch viewModel.settings.audioBitrate {
        case 0..<96:
            return "저품질 모드"
        case 96..<160:
            return "표준 품질 모드"
        default:
            return "고품질 모드"
        }
    }
    
    private func getAudioOptimizationDescription() -> String {
        switch viewModel.settings.audioBitrate {
        case 0..<96:
            return "44.1kHz 샘플레이트 + 20ms 버퍼"
        case 96..<160:
            return "44.1kHz 샘플레이트 + 10ms 버퍼"
        default:
            return "48kHz 샘플레이트 + 5ms 버퍼"
        }
    }
    
    private func getAudioOptimizationColor() -> Color {
        switch viewModel.settings.audioBitrate {
        case 0..<96:
            return .orange
        case 96..<160:
            return .green
        default:
            return .blue
        }
    }
    
    // MARK: - 전체 최적화 관련
    
    private func getOverallOptimizationStatus() -> String {
        let audioLevel = getAudioOptimizationLevel()
        let videoPixels = viewModel.settings.videoWidth * viewModel.settings.videoHeight
        
        let isBalanced = (audioLevel.contains("표준") && videoPixels >= 1280*720 && videoPixels < 1920*1080) ||
                        (audioLevel.contains("고품질") && videoPixels >= 1920*1080)
        
        if isBalanced {
            return "최적 균형 ⭐"
        } else if audioLevel.contains("저품질") && videoPixels >= 1920*1080 {
            return "비디오 편중 ⚠️"
        } else if audioLevel.contains("고품질") && videoPixels < 1280*720 {
            return "오디오 편중 ⚠️"
        } else {
            return "표준 설정 ✅"
        }
    }
    
    private func getOverallOptimizationLevel() -> String {
        let status = getOverallOptimizationStatus()
        
        if status.contains("최적") {
            return "완벽한 균형"
        } else if status.contains("편중") {
            return "부분 최적화"
        } else {
            return "표준 최적화"
        }
    }
    
    private func getOverallOptimizationDescription() -> String {
        let status = getOverallOptimizationStatus()
        
        if status.contains("최적") {
            return "오디오와 비디오 품질이 완벽히 균형잡혀 있습니다"
        } else if status.contains("비디오 편중") {
            return "오디오 품질을 높이면 더 균형잡힌 스트리밍이 됩니다"
        } else if status.contains("오디오 편중") {
            return "비디오 해상도를 높이면 더 균형잡힌 스트리밍이 됩니다"
        } else {
            return "현재 설정으로 안정적인 스트리밍이 가능합니다"
        }
    }
    
    private func getOverallOptimizationColor() -> Color {
        let status = getOverallOptimizationStatus()
        
        if status.contains("최적") {
            return .green
        } else if status.contains("편중") {
            return .orange
        } else {
            return .blue
        }
    }
}

/// 하드웨어 최적화 카드
struct HardwareOptimizationCard: View {
    let title: String
    let currentSetting: String
    let optimizationLevel: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 헤더
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(optimizationLevel)
                        .font(.caption)
                        .foregroundColor(color)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Text(currentSetting)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            
            // 설명
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
} 
