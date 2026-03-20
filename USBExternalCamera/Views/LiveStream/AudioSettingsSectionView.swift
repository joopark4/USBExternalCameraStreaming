import SwiftUI

/// 오디오 설정 섹션 뷰
/// - audioBitrate만 실제 스트리밍에 적용됨
/// - sampleRate/channels는 UI 표시용 (AAC 인코더가 자동으로 48kHz/스테레오 사용)
struct AudioSettingsSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel

    /// UI 표시용 샘플레이트 (실제 인코딩에는 미적용 - AAC 인코더가 48kHz 자동 사용)
    @State private var selectedSampleRate: Int = 48000
    /// UI 표시용 채널 수 (실제 인코딩에는 미적용 - AAC 인코더가 스테레오 자동 사용)
    @State private var selectedChannels: Int = 2

    var body: some View {
        SettingsSectionView(title: NSLocalizedString("audio_settings", comment: "오디오 설정"), icon: "waveform") {
            VStack(spacing: 16) {
                // 마이크 입력 소스
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("microphone_input_source", comment: "마이크 입력 소스"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(viewModel.selectedMicrophoneInputDisplayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Picker(
                        NSLocalizedString("microphone_input_source", comment: "마이크 입력 소스"),
                        selection: Binding(
                            get: { viewModel.selectedMicrophoneInputID },
                            set: { viewModel.selectMicrophoneInput($0) }
                        )
                    ) {
                        ForEach(viewModel.availableMicrophoneInputs) { input in
                            Text(input.name).tag(input.id)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString("microphone_input_active", comment: "현재 입력: %@"),
                                viewModel.activeMicrophoneInputName
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    if !viewModel.hasExternalMicrophoneInput {
                        Text(NSLocalizedString("microphone_input_select_hint", comment: "블루투스/유선 마이크 연결 시 여기서 선택할 수 있습니다."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 샘플레이트
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("sample_rate", comment: "샘플레이트"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        SampleRateButton(
                            title: "44.1 kHz",
                            sampleRate: 44100,
                            isSelected: selectedSampleRate == 44100,
                            action: {
                                selectedSampleRate = 44100
                            }
                        )

                        SampleRateButton(
                            title: "48 kHz",
                            sampleRate: 48000,
                            isSelected: selectedSampleRate == 48000,
                            action: {
                                selectedSampleRate = 48000
                            }
                        )
                    }
                }

                // 오디오 비트레이트
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("audio_bitrate", comment: "오디오 비트레이트"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(viewModel.settings.audioBitrate) kbps")
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    }

                    Slider(value: Binding(
                        get: { Double(viewModel.settings.audioBitrate) },
                        set: { newValue in
                            viewModel.updateSettings { settings in
                                settings.audioBitrate = Int(newValue)
                            }
                        }
                    ), in: 64...320, step: 32)

                    // 권장 비트레이트 가이드
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(NSLocalizedString("recommended_audio_bitrate", comment: "YouTube는 128-256 kbps를 권장합니다"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 오디오 채널
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("audio_channels", comment: "오디오 채널"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Button(action: {
                            selectedChannels = 1
                        }) {
                            HStack {
                                Image(systemName: "speaker.wave.1")
                                Text(NSLocalizedString("mono", comment: "모노"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedChannels == 1 ? Color.blue : Color(.systemGray5))
                            .foregroundColor(selectedChannels == 1 ? .white : .primary)
                            .cornerRadius(8)
                        }

                        Button(action: {
                            selectedChannels = 2
                        }) {
                            HStack {
                                Image(systemName: "speaker.wave.2")
                                Text(NSLocalizedString("stereo", comment: "스테레오"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedChannels == 2 ? Color.blue : Color(.systemGray5))
                            .foregroundColor(selectedChannels == 2 ? .white : .primary)
                            .cornerRadius(8)
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                }
            }
        }
        .onAppear {
            viewModel.refreshAvailableMicrophoneInputs()
        }
    }
}

/// 샘플레이트 선택 버튼
struct SampleRateButton: View {
    let title: String
    let sampleRate: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(8)
        }
    }
}
