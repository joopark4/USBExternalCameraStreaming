import SwiftUI
import LiveStreamingCore

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
        SettingsSectionView(title: NSLocalizedString("hardware_quality_optimization", comment: "하드웨어 품질 최적화"), icon: "cpu") {
            VStack(spacing: 16) {
                // 설명 텍스트
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(NSLocalizedString("hardware_auto_optimization_desc", comment: "스트리밍 설정에 맞춰 카메라와 마이크 하드웨어 품질이 자동으로 최적화됩니다"))
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
                        title: NSLocalizedString("video_hardware", comment: "비디오 하드웨어"),
                        currentSetting: "\(viewModel.settings.videoWidth)×\(viewModel.settings.videoHeight) @ \(viewModel.settings.frameRate)fps",
                        optimizationLevel: getVideoOptimizationLevel(),
                        description: getVideoOptimizationDescription(),
                        icon: "camera.circle.fill",
                        color: getVideoOptimizationColor()
                    )
                    
                    // 오디오 하드웨어 최적화
                    HardwareOptimizationCard(
                        title: NSLocalizedString("audio_hardware", comment: "오디오 하드웨어"),
                        currentSetting: "\(viewModel.settings.audioBitrate) kbps",
                        optimizationLevel: getAudioOptimizationLevel(),
                        description: getAudioOptimizationDescription(),
                        icon: "mic.circle.fill",
                        color: getAudioOptimizationColor()
                    )
                    
                    // 전체 최적화 상태
                    HardwareOptimizationCard(
                        title: NSLocalizedString("overall_optimization_status", comment: "전체 최적화 상태"),
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
}
