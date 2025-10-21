import SwiftUI

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
                    Text(NSLocalizedString("whitespace_special_chars_removed", comment: "⚠️ 공백이나 특수문자가 제거되었습니다"))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                if cleanedLength < 16 {
                    Text(NSLocalizedString("stream_key_too_short", comment: "❌ 스트림 키가 너무 짧습니다 (16자 이상 필요)"))
                        .font(.caption)
                        .foregroundColor(.red)
                } else if cleanedLength > 50 {
                    Text(NSLocalizedString("stream_key_too_long", comment: "⚠️ 스트림 키가 너무 깁니다 (50자 이하 권장)"))
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        } else {
                                Text(String.localizedStringWithFormat(NSLocalizedString("valid_stream_key_format", comment: "✅ 유효한 스트림 키입니다 (%d자)"), cleanedLength))
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
}
