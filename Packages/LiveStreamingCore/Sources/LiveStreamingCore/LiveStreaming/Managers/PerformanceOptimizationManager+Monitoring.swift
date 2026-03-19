import Foundation
import AVFoundation
import VideoToolbox
import Metal
import CoreImage
import UIKit
import os.log
import Accelerate

extension PerformanceOptimizationManager {
    // MARK: - 🔧 개선: 고급 진단 및 모니터링
    
    /// VideoToolbox 상태 진단
    public func diagnoseVideoToolboxHealth() -> VideoToolboxDiagnostics {
        var diagnostics = VideoToolboxDiagnostics()
        
        // 1. 하드웨어 가속 지원 여부
        diagnostics.hardwareAccelerationSupported = checkHardwareAccelerationSupport()
        
        // 2. 현재 압축 세션 상태
        diagnostics.compressionSessionActive = (compressionSession != nil)
        
        // 3. 메모리 사용량
        diagnostics.memoryUsage = getCurrentMemoryUsage()
        
        // 4. 압축 성능 통계
        diagnostics.averageCompressionTime = compressionStats.averageCompressionTime
        diagnostics.compressionErrorRate = compressionStats.errorRate
        
        // 5. 지원되는 코덱 목록
        diagnostics.supportedCodecs = getSupportedCodecs()
        
        return diagnostics
    }
    
    /// 실시간 성능 모니터링 강화
    func startAdvancedPerformanceMonitoring() {
        performanceQueue.async { [weak self] in
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                guard let self = self else { return }
                
                Task { @MainActor in
                    // VideoToolbox 특화 메트릭 수집
                    self.collectVideoToolboxMetrics()
                    
                    // 성능 임계값 검사
                    self.checkPerformanceThresholds()
                    
                    // 적응형 품질 조정 트리거
                    if self.adaptiveQualityEnabled {
                        await self.performAdaptiveQualityAdjustment()
                    }
                }
            }
        }
    }
    
    // MARK: - 🔧 개선: 통계 및 유틸리티 메서드들
    
    /// 압축 오류 설명 반환
    func compressionErrorDescription(_ status: OSStatus) -> String {
        switch status {
        case kVTInvalidSessionErr:
            return "세션 무효화"
        case kVTAllocationFailedErr:
            return "메모리 할당 실패"
        case kVTPixelTransferNotSupportedErr:
            return "픽셀 전송 미지원"
        case kVTCouldNotFindVideoEncoderErr:
            return "비디오 인코더를 찾을 수 없음"
        case kVTVideoEncoderMalfunctionErr:
            return "비디오 인코더 오작동"
        case kVTInsufficientSourceColorDataErr:
            return "소스 색상 데이터 부족"
        default:
            return "알 수 없는 오류"
        }
    }
    
    /// 압축 비율 계산
    func calculateCompressionRatio(sampleBuffer: CMSampleBuffer) -> Double {
        let dataSize = CMSampleBufferGetTotalSampleSize(sampleBuffer)
        // 가정: 원본 크기는 해상도 기반으로 계산
        let estimatedOriginalSize = 1280 * 720 * 4 // RGBA 기준
        return Double(estimatedOriginalSize) / Double(max(dataSize, 1))
    }
    
    /// 압축 통계 업데이트
    @MainActor
    func updateCompressionStatistics(dataSize: Int, isKeyFrame: Bool, compressionRatio: Double, infoFlags: VTEncodeInfoFlags) {
        compressionStats.updateStats(
            dataSize: dataSize,
            isKeyFrame: isKeyFrame,
            compressionRatio: compressionRatio,
            processingTime: frameProcessingTime
        )
    }
    
    /// 압축 성공률 업데이트
    @MainActor
    func updateCompressionSuccessRate() {
        let totalFrames = compressionStats.totalFrames
        let errorCount = compressionErrorCount
        
        if totalFrames > 0 {
            compressionSuccessRate = 1.0 - (Double(errorCount) / Double(totalFrames))
        }
    }
    
    /// 하드웨어 가속 지원 확인
    func checkHardwareAccelerationSupport() -> Bool {
        // VideoToolbox 하드웨어 가속 지원 여부 확인
        return MTLCreateSystemDefaultDevice() != nil
    }
    
    /// 현재 메모리 사용량 계산 (단일 메서드로 통합)
    
    /// 지원되는 코덱 목록 반환
    func getSupportedCodecs() -> [String] {
        return ["H.264", "HEVC"] // 실제로는 시스템 쿼리를 통해 확인
    }
    
    /// VideoToolbox 메트릭 수집
    @MainActor
    func collectVideoToolboxMetrics() {
        // 메모리 사용량 업데이트
        currentMemoryUsage = getCurrentMemoryUsage()
        
        // 압축 세션 상태 확인
        if compressionSession != nil {
            // 세션 활성 상태에서의 추가 메트릭 수집
        }
    }
    
    /// 성능 임계값 검사
    @MainActor
    func checkPerformanceThresholds() {
        // CPU 사용량 임계값 검사
        if self.currentCPUUsage > performanceThresholds.cpuCriticalThreshold {
            logger.warning("⚠️ CPU 사용량 임계값 초과: \(self.currentCPUUsage)%")
        }
        
        // 메모리 사용량 임계값 검사
        if self.currentMemoryUsage > performanceThresholds.memoryCriticalThreshold {
            logger.warning("⚠️ 메모리 사용량 임계값 초과: \(self.currentMemoryUsage)MB")
        }
        
        // 프레임 처리 시간 임계값 검사
        if self.frameProcessingTime > performanceThresholds.frameTimeCriticalThreshold {
            logger.warning("⚠️ 프레임 처리 시간 임계값 초과: \(self.frameProcessingTime)초")
        }
    }
    
    /// 적응형 품질 조정 수행
    func performAdaptiveQualityAdjustment() async {
        // 실제 적응형 품질 조정 로직
        // 기존 구현과 연동
    }
    
}
