import SwiftUI

extension LiveStreamSettingsView {
    // MARK: - 오디오 최적화 관련

    func getAudioOptimizationLevel() -> String {
        switch viewModel.settings.audioBitrate {
        case 0..<96:
            return NSLocalizedString("low_quality_mode", comment: "저품질 모드")
        case 96..<160:
            return NSLocalizedString("standard_quality_mode", comment: "표준 품질 모드")
        default:
            return NSLocalizedString("high_quality_mode", comment: "고품질 모드")
        }
    }
    
    func getAudioOptimizationDescription() -> String {
        switch viewModel.settings.audioBitrate {
        case 0..<96:
            return "44.1kHz 샘플레이트 + 20ms 버퍼"
        case 96..<160:
            return "44.1kHz 샘플레이트 + 10ms 버퍼"
        default:
            return "48kHz 샘플레이트 + 5ms 버퍼"
        }
    }
    
    func getAudioOptimizationColor() -> Color {
        switch viewModel.settings.audioBitrate {
        case 0..<96:
            return .orange
        case 96..<160:
            return .green
        default:
            return .blue
        }
    }
    
    
}
