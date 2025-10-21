import SwiftUI

// MARK: - 비디오 최적화 관련
    
    private func getVideoOptimizationLevel() -> String {
        let pixels = viewModel.settings.videoWidth * viewModel.settings.videoHeight
        let fps = viewModel.settings.frameRate
        
        switch (pixels, fps) {
        case (0..<(1280*720), 0..<30):
            return NSLocalizedString("low_resolution_mode", comment: "저해상도 모드")
        case (0..<(1920*1080), 0..<30):
            return NSLocalizedString("standard_hd_mode", comment: "표준 HD 모드")
        case (0..<(1920*1080), 30...):
            return NSLocalizedString("high_framerate_mode", comment: "고프레임 모드")
        case ((1920*1080)..., _):
            return NSLocalizedString("high_resolution_mode", comment: "고해상도 모드")
        default:
            return NSLocalizedString("custom_mode", comment: "사용자 정의")
        }
    }
    
    private func getVideoOptimizationDescription() -> String {
        let pixels = viewModel.settings.videoWidth * viewModel.settings.videoHeight
        
        if pixels >= 1920*1080 {
            return NSLocalizedString("camera_1080p_preset", comment: "카메라 1080p 프리셋 + 연속 자동 포커스")
        } else if pixels >= 1280*720 {
            return NSLocalizedString("camera_720p_preset", comment: "카메라 720p 프리셋 + 자동 포커스")
        } else {
            return NSLocalizedString("camera_vga_preset", comment: "카메라 VGA 프리셋 + 기본 설정")
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
    
    
