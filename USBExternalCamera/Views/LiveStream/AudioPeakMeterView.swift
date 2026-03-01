import SwiftUI

/// 카메라 프리뷰 하단에 표시되는 실시간 마이크 피크 미터
struct AudioPeakMeterView: View {
  let level: Float
  let decibels: Float
  let isMuted: Bool
  let isStreaming: Bool
  let diagnosticMessage: String
  let inputSummary: String

  private var clampedLevel: CGFloat {
    CGFloat(level.clamped(to: 0...1))
  }

  private var displayText: String {
    if isMuted {
      return NSLocalizedString("audio_meter_muted", comment: "음소거")
    }
    if !isStreaming && level < 0.01 {
      return NSLocalizedString("audio_meter_idle", comment: "대기")
    }
    return String(format: "%.0f dB", decibels)
  }

  private var activeTint: LinearGradient {
    LinearGradient(
      colors: [.mint, .green, .yellow, .orange, .red],
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  private var mutedTint: LinearGradient {
    LinearGradient(
      colors: [Color.orange.opacity(0.55), Color.orange.opacity(0.3)],
      startPoint: .leading,
      endPoint: .trailing
    )
  }

  private var containerBackground: Color {
    isMuted ? Color.orange.opacity(0.12) : Color(UIColor.tertiarySystemBackground)
  }

  private var activeInputText: String {
    String(
      format: NSLocalizedString("microphone_input_active", comment: "현재 입력: %@"),
      inputSummary
    )
  }

  var body: some View {
    VStack(spacing: 4) {
      HStack(spacing: 6) {
        Image(systemName: isMuted ? "mic.slash.fill" : "waveform")
          .font(.caption.weight(.bold))
          .foregroundStyle(isMuted ? .orange : .secondary)
          .scaleEffect(isMuted ? 1.06 : 1.0)
          .animation(.easeInOut(duration: 0.18), value: isMuted)

        Text(NSLocalizedString("audio_peak_label", comment: "오디오 피크"))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        Spacer()

        Text(displayText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(isMuted ? .orange : .secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(
            Capsule()
              .fill(isMuted ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.12))
          )
          .animation(.easeInOut(duration: 0.2), value: isMuted)
      }

      Text(activeInputText)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.85)

      GeometryReader { geometry in
        let rawWidth = geometry.size.width * (isMuted ? 0 : clampedLevel)
        let barWidth = max(rawWidth, (!isMuted && clampedLevel > 0.01) ? 3 : 0)

        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.secondary.opacity(0.2))

          Capsule()
            .fill(
              isMuted
                ? AnyShapeStyle(mutedTint)
                : AnyShapeStyle(activeTint)
            )
            .frame(width: barWidth)
            .animation(.easeOut(duration: 0.1), value: clampedLevel)
            .animation(.easeInOut(duration: 0.2), value: isMuted)
        }
      }
      .frame(height: 7)

      if !diagnosticMessage.isEmpty {
        Text(diagnosticMessage)
          .font(.caption2)
          .foregroundStyle(.orange)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(containerBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(isMuted ? Color.orange.opacity(0.35) : Color.clear, lineWidth: 1)
    )
    .animation(.easeInOut(duration: 0.2), value: isMuted)
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
