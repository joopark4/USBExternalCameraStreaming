import Foundation
import AVFoundation
import VideoToolbox
import Metal
import CoreImage
import UIKit
import os.log
import Accelerate

extension PerformanceOptimizationManager {
    // MARK: - 사용자 설정 보존형 적응형 품질 조정
    
    /// 사용자 설정값을 존중하는 성능 기반 품질 조정
    /// 사용자가 명시적으로 설정한 값은 보존하고, 자동 조정 범위 내에서만 최적화
    @MainActor
    public func adaptQualityRespectingUserSettings(
        currentSettings: LiveStreamSettings,
        userDefinedSettings: LiveStreamSettings
    ) -> LiveStreamSettings {
        guard adaptiveQualityEnabled else { return currentSettings }
        
        var optimizedSettings = currentSettings
        let performanceIssue = assessPerformanceIssue()
        
        guard performanceIssue != .none else { return currentSettings }
        
        logger.info("🎯 성능 이슈 감지: \(performanceIssue.description) - 제한적 자동 조정 시작")
        
        // 사용자 설정값 기반 조정 범위 계산
        let adjustmentLimits = calculateAdjustmentLimits(userSettings: userDefinedSettings)
        
        switch performanceIssue {
        case .cpuOverload:
            // 🔧 개선: CPU 과부하 시 매우 제한적 품질 낮춤 (최소한의 조정만)
            let minBitrate = max(adjustmentLimits.minVideoBitrate, userDefinedSettings.videoBitrate - 200) // 최대 200kbps 감소
            let minFrameRate = max(adjustmentLimits.minFrameRate, userDefinedSettings.frameRate - 2) // 최대 2fps 감소
            
            optimizedSettings.videoBitrate = max(optimizedSettings.videoBitrate - 200, minBitrate)
            optimizedSettings.frameRate = max(optimizedSettings.frameRate - 2, minFrameRate)
            
            logger.info("🔽 CPU 과부하 최소 조정: 비트레이트 \(optimizedSettings.videoBitrate)kbps (사용자 설정: \(userDefinedSettings.videoBitrate)), FPS \(optimizedSettings.frameRate) (사용자 설정: \(userDefinedSettings.frameRate))")
            
        case .memoryOverload:
            // 🔧 개선: 메모리 과부하 시 해상도 변경 금지, 비트레이트만 소폭 조정
            let minBitrate = max(adjustmentLimits.minVideoBitrate, userDefinedSettings.videoBitrate - 300)
            optimizedSettings.videoBitrate = max(optimizedSettings.videoBitrate - 300, minBitrate)
            logger.info("🔽 메모리 과부하 최소 조정: 해상도 유지, 비트레이트만 \(optimizedSettings.videoBitrate)kbps로 소폭 조정")
            
        case .thermalThrottling:
            // 🔧 개선: 열 문제도 더 보수적으로 조정
            let minBitrate = max(adjustmentLimits.minVideoBitrate, userDefinedSettings.videoBitrate - 500)
            let minFrameRate = max(adjustmentLimits.minFrameRate, userDefinedSettings.frameRate - 5)
            
            optimizedSettings.videoBitrate = max(optimizedSettings.videoBitrate - 500, minBitrate)
            optimizedSettings.frameRate = max(optimizedSettings.frameRate - 5, minFrameRate)
            // 해상도는 변경하지 않음
            
            logger.warning("🌡️ 열 문제 보수적 조정: 해상도 유지, 비트레이트 \(optimizedSettings.videoBitrate)kbps, FPS \(optimizedSettings.frameRate)")
            
        case .none:
            break
        }
        
        return optimizedSettings
    }
    
    /// 성능 이슈 평가
    @MainActor
    func assessPerformanceIssue() -> PerformanceIssue {
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            return .thermalThrottling
        }
        
        if currentCPUUsage > performanceThresholds.cpuCriticalThreshold {
            return .cpuOverload
        }
        
        if currentMemoryUsage > performanceThresholds.memoryCriticalThreshold {
            return .memoryOverload
        }
        
        return .none
    }
    
    /// 사용자 설정 기반 조정 범위 계산 (더 보수적으로 수정)
    func calculateAdjustmentLimits(userSettings: LiveStreamSettings) -> AdjustmentLimits {
        return AdjustmentLimits(
            minVideoBitrate: Int(Double(userSettings.videoBitrate) * 0.85), // 🔧 개선: 15% 감소까지만 (기존 40% → 15%)
            maxVideoBitrate: Int(Double(userSettings.videoBitrate) * 1.1), // 🔧 개선: 10% 증가까지만 (기존 20% → 10%)
            minFrameRate: max(Int(Double(userSettings.frameRate) * 0.9), userSettings.frameRate - 5), // 🔧 개선: 10% 또는 최대 5fps 감소
            maxFrameRate: userSettings.frameRate, // 🔧 개선: 프레임율 증가 금지
            minVideoWidth: userSettings.videoWidth, // 🔧 개선: 해상도 감소 금지
            minVideoHeight: userSettings.videoHeight // 🔧 개선: 해상도 감소 금지
        )
    }

}
