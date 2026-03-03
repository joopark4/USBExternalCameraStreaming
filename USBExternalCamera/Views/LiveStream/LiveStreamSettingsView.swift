//
//  LiveStreamSettingsView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import LiveStreamingCore
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
                    ), in: 500...20000, step: 100)
                    
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
                
                Divider()
                
                // 적응형 품질 조정
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(NSLocalizedString("adaptive_quality_adjustment", comment: "적응형 품질 조정"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Image(systemName: viewModel.adaptiveQualityEnabled ? "exclamationmark.triangle.fill" : "lock.shield.fill")
                                    .font(.caption)
                                    .foregroundColor(viewModel.adaptiveQualityEnabled ? .orange : .green)
                            }
                            Text(viewModel.adaptiveQualityEnabled ? 
                                 NSLocalizedString("adaptive_quality_enabled_desc", comment: "성능 이슈 시 설정을 자동으로 조정합니다") : 
                                 NSLocalizedString("adaptive_quality_disabled_desc", comment: "사용자 설정을 정확히 유지합니다 (권장)"))
                                .font(.caption)
                                .foregroundColor(viewModel.adaptiveQualityEnabled ? .orange : .green)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.adaptiveQualityEnabled)
                    }
                    
                    // 상세 설명
                    VStack(alignment: .leading, spacing: 6) {
                        if !viewModel.adaptiveQualityEnabled {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text(NSLocalizedString("user_settings_exact_desc", comment: "사용자가 설정한 해상도, 프레임률, 비트레이트가 정확히 적용됩니다"))
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "info.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    Text(NSLocalizedString("adaptive_quality_auto_adjust_desc", comment: "성능 문제 시 최대 15% 범위 내에서 자동 조정됩니다"))
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                HStack {
                                    Image(systemName: "minus.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString("resolution_not_changed", comment: "• 해상도는 변경되지 않습니다"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                HStack {
                                    Image(systemName: "minus.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString("framerate_max_decrease", comment: "• 프레임률은 최대 5fps까지만 감소됩니다"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                HStack {
                                    Image(systemName: "minus.circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(NSLocalizedString("bitrate_max_decrease", comment: "• 비트레이트는 최대 15%까지만 감소됩니다"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(viewModel.adaptiveQualityEnabled ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                    .cornerRadius(8)
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
        case .custom: return (1920, 1080) // Default for custom
        }
    }
    
    /// 비트레이트 색상 (권장사항 기준)
    private var bitrateColor: Color {
        let bitrate = viewModel.settings.videoBitrate
        if recommendedBitrateRange.contains(bitrate) {
            return .green
        }
        return bitrate < recommendedBitrateRange.lowerBound ? .orange : .red
    }
    
    /// 비트레이트 경고 및 권장사항 뷰
    @ViewBuilder
    private var bitrateWarningView: some View {
        if viewModel.settings.videoBitrate > recommendedBitrateRange.upperBound {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("bitrate_too_high_warning", comment: "⚠️ 비트레이트가 너무 높습니다"))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    Text(NSLocalizedString("youtube_bitrate_warning", comment: "YouTube Live 권장 비트레이트 범위를 벗어났습니다."))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: NSLocalizedString("youtube_recommended_bitrate_format", comment: "권장 비트레이트 범위"), recommendedBitrateRange.lowerBound, recommendedBitrateRange.upperBound))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        } else if recommendedBitrateRange.contains(viewModel.settings.videoBitrate) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("youtube_recommended_range", comment: "✅ YouTube Live H.264 권장 범위"))
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(String(format: NSLocalizedString("youtube_recommended_bitrate_format", comment: "권장 비트레이트 범위"), recommendedBitrateRange.lowerBound, recommendedBitrateRange.upperBound))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("low_bitrate_warning", comment: "📹 낮은 비트레이트 - 화질이 떨어질 수 있습니다"))
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(String(format: NSLocalizedString("youtube_recommended_bitrate_format", comment: "권장 비트레이트 범위"), recommendedBitrateRange.lowerBound, recommendedBitrateRange.upperBound))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private var recommendedBitrateRange: ClosedRange<Int> {
        let recommended = youtubeH264RecommendedBitrate
        let minBitrate = max(500, Int(Double(recommended) * 0.8))
        let maxBitrate = Int(Double(recommended) * 1.2)
        return minBitrate...maxBitrate
    }

    private var youtubeH264RecommendedBitrate: Int {
        let width = viewModel.settings.videoWidth
        let height = viewModel.settings.videoHeight
        let is60fps = viewModel.settings.frameRate >= 50

        if width >= 3840 && height >= 2160 {
            return is60fps ? 51_000 : 35_000
        } else if width >= 2560 && height >= 1440 {
            return is60fps ? 24_000 : 16_000
        } else if width >= 1920 && height >= 1080 {
            return is60fps ? 12_000 : 10_000
        } else {
            return is60fps ? 6_000 : 4_000
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
            viewModel.settings.videoBitrate = 4000
            // 480p는 60fps 지원하지 않음
            if viewModel.settings.frameRate == 60 {
                viewModel.settings.frameRate = 30
            }
        case .resolution720p:
            viewModel.settings.videoWidth = 1280
            viewModel.settings.videoHeight = 720
            viewModel.settings.videoBitrate = 4000
        case .resolution1080p:
            viewModel.settings.videoWidth = 1920
            viewModel.settings.videoHeight = 1080
            viewModel.settings.videoBitrate = 10_000
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
}
