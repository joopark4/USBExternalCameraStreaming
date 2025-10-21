import SwiftUI

extension LiveStreamSettingsView {
  // MARK: - 전체 최적화 관련

  private func getOverallOptimizationStatus() -> String {
        let audioLevel = getAudioOptimizationLevel()
        let videoPixels = viewModel.settings.videoWidth * viewModel.settings.videoHeight
        
        let isBalanced = (audioLevel.contains(NSLocalizedString("standard_quality_mode", comment: "표준 품질 모드")) && videoPixels >= 1280*720 && videoPixels < 1920*1080) ||
                        (audioLevel.contains(NSLocalizedString("high_quality_mode", comment: "고품질 모드")) && videoPixels >= 1920*1080)
        
        if isBalanced {
            return NSLocalizedString("optimal_balance", comment: "최적 균형 ⭐")
        } else if audioLevel.contains(NSLocalizedString("low_quality_mode", comment: "저품질 모드")) && videoPixels >= 1920*1080 {
            return NSLocalizedString("video_biased", comment: "비디오 편중 ⚠️")
        } else if audioLevel.contains(NSLocalizedString("high_quality_mode", comment: "고품질 모드")) && videoPixels < 1280*720 {
            return NSLocalizedString("audio_biased", comment: "오디오 편중 ⚠️")
        } else {
            return NSLocalizedString("standard_settings", comment: "표준 설정 ✅")
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
