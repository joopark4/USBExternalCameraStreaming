import SwiftUI

/// 오디오 설정 섹션 뷰
/// Note: sampleRate와 channels는 현재 UI 표시용으로만 사용됨
/// AAC 인코더가 자동으로 최적 설정을 사용하며, audioBitrate만 실제로 적용됨
struct AudioSettingsSectionView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    // TODO: LiveStreamSettings에 sampleRate/channels 프로퍼티 추가 시 바인딩 연결 필요
    @State private var selectedSampleRate: Int = 48000
    @State private var selectedChannels: Int = 2

    var body: some View {
        SettingsSectionView(title: NSLocalizedString("audio_settings", comment: "오디오 설정"), icon: "waveform") {
            VStack(spacing: 16) {
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
                        set: { viewModel.settings.audioBitrate = Int($0) }
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