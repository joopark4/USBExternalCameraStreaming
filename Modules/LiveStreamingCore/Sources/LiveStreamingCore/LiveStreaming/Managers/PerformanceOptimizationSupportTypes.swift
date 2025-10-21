import Foundation
import AVFoundation
import VideoToolbox
import Metal
import CoreImage
import UIKit
import os.log
import Accelerate


// MARK: - Supporting Types

/// 성능 이슈 유형
enum PerformanceIssue: CaseIterable {
    case none
    case cpuOverload
    case memoryOverload
    case thermalThrottling
    
    var description: String {
        switch self {
        case .none: return "정상"
        case .cpuOverload: return "CPU 과부하"
        case .memoryOverload: return "메모리 과부하"
        case .thermalThrottling: return "열 관리"
        }
    }
}

/// 사용자 설정 기반 조정 범위
struct AdjustmentLimits {
    let minVideoBitrate: Int
    let maxVideoBitrate: Int
    let minFrameRate: Int
    let maxFrameRate: Int
    let minVideoWidth: Int
    let minVideoHeight: Int
}

/// 성능 임계값
struct PerformanceThresholds {
    let cpuWarningThreshold: Double = 70.0
    let cpuCriticalThreshold: Double = 85.0
    let memoryWarningThreshold: Double = 500.0 // MB
    let memoryCriticalThreshold: Double = 700.0 // MB
    let frameTimeWarningThreshold: TimeInterval = 0.033 // 30fps
    let frameTimeCriticalThreshold: TimeInterval = 0.050 // 20fps
}

/// 성능 최적화 에러
enum PerformanceOptimizationError: Error {
    case hardwareCompressionSetupFailed(OSStatus)
    case compressionPropertySetFailed(String, OSStatus)
    case compressionSetupFailed(Error)
    case memoryAllocationFailed
    case pixelFormatNotSupported
    case metalDeviceNotAvailable
    case pixelBufferPoolCreationFailed
    
    var localizedDescription: String {
        switch self {
        case .hardwareCompressionSetupFailed(let status):
            return "VideoToolbox 하드웨어 압축 설정 실패: \(status)"
        case .compressionPropertySetFailed(let property, let status):
            return "압축 속성 설정 실패 (\(property)): \(status)"
        case .compressionSetupFailed(let error):
            return "압축 설정 실패: \(error.localizedDescription)"
        case .memoryAllocationFailed:
            return "메모리 할당 실패"
        case .pixelFormatNotSupported:
            return "지원되지 않는 픽셀 포맷"
        case .metalDeviceNotAvailable:
            return "Metal GPU 디바이스를 사용할 수 없음"
        case .pixelBufferPoolCreationFailed:
            return "픽셀 버퍼 풀 생성 실패"
        }
    }
}

// MARK: - 🔧 개선: VideoToolbox 관련 새로운 타입 정의들

/// VideoToolbox 진단 정보
public struct VideoToolboxDiagnostics {
    var hardwareAccelerationSupported: Bool = false
    var compressionSessionActive: Bool = false
    var memoryUsage: Double = 0.0
    var averageCompressionTime: TimeInterval = 0.0
    var compressionErrorRate: Double = 0.0
    var supportedCodecs: [String] = []
    
    public var description: String {
        return """
        🔧 VideoToolbox 진단 보고서
        • 하드웨어 가속: \(hardwareAccelerationSupported ? "✅ 지원" : "❌ 미지원")
        • 압축 세션: \(compressionSessionActive ? "✅ 활성" : "❌ 비활성")
        • 메모리 사용량: \(String(format: "%.1f", memoryUsage))MB
        • 평균 압축 시간: \(String(format: "%.3f", averageCompressionTime))초
        • 압축 오류율: \(String(format: "%.2f", compressionErrorRate * 100))%
        • 지원 코덱: \(supportedCodecs.joined(separator: ", "))
        """
    }
}

/// VideoToolbox 압축 통계
public class VideoToolboxCompressionStats {
    private var compressionTimes: [TimeInterval] = []
    private var dataSizes: [Int] = []
    private var keyFrameCount: Int = 0
    private var errorCount: Int = 0
    
    public var totalFrames: Int {
        return compressionTimes.count
    }
    
    public var averageCompressionTime: TimeInterval {
        guard !compressionTimes.isEmpty else { return 0.0 }
        return compressionTimes.reduce(0, +) / Double(compressionTimes.count)
    }
    
    public var averageDataSize: Double {
        guard !dataSizes.isEmpty else { return 0.0 }
        return Double(dataSizes.reduce(0, +)) / Double(dataSizes.count)
    }
    
    public var keyFrameRatio: Double {
        guard totalFrames > 0 else { return 0.0 }
        return Double(keyFrameCount) / Double(totalFrames)
    }
    
    public var errorRate: Double {
        guard totalFrames > 0 else { return 0.0 }
        return Double(errorCount) / Double(totalFrames)
    }
    
    /// 통계 업데이트
    public func updateStats(dataSize: Int, isKeyFrame: Bool, compressionRatio: Double, processingTime: TimeInterval) {
        compressionTimes.append(processingTime)
        dataSizes.append(dataSize)
        
        if isKeyFrame {
            keyFrameCount += 1
        }
        
        // 메모리 효율성을 위해 최근 1000개 프레임만 유지
        if compressionTimes.count > 1000 {
            compressionTimes.removeFirst()
            dataSizes.removeFirst()
        }
    }
    
    /// 오류 카운트 증가
    public func incrementErrorCount() {
        errorCount += 1
    }
    
    /// 통계 리셋
    public func reset() {
        compressionTimes.removeAll()
        dataSizes.removeAll()
        keyFrameCount = 0
        errorCount = 0
    }
}

// MARK: - 🔧 개선: Notification 확장

extension Notification.Name {
    static let videoToolboxFrameReady = Notification.Name("VideoToolboxFrameReady")
    static let videoToolboxError = Notification.Name("VideoToolboxError")
    static let videoToolboxMemoryWarning = Notification.Name("VideoToolboxMemoryWarning")
    static let videoToolboxSessionRecreated = Notification.Name("VideoToolboxSessionRecreated")
    static let videoToolboxPerformanceAlert = Notification.Name("VideoToolboxPerformanceAlert")
}

// MARK: - 🔧 개선: VideoToolbox 성능 메트릭 확장

/// VideoToolbox 성능 메트릭
public struct VideoToolboxPerformanceMetrics {
    let timestamp: Date
    let cpuUsage: Double
    let memoryUsage: Double
    let compressionTime: TimeInterval
    let frameRate: Double
    let errorRate: Double
    
    public init(cpuUsage: Double, memoryUsage: Double, compressionTime: TimeInterval, frameRate: Double, errorRate: Double) {
        self.timestamp = Date()
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.compressionTime = compressionTime
        self.frameRate = frameRate
        self.errorRate = errorRate
    }
    
    /// 성능 상태 평가
    public var performanceStatus: PerformanceStatus {
        if errorRate > 0.1 || compressionTime > 0.05 {
            return .poor
        } else if cpuUsage > 70 || memoryUsage > 500 {
            return .warning
        } else {
            return .good
        }
    }
}

/// 성능 상태
public enum PerformanceStatus {
    case good
    case warning
    case poor
    
    public var description: String {
        switch self {
        case .good: return "✅ 양호"
        case .warning: return "⚠️ 주의"
        case .poor: return "❌ 불량"
        }
    }
    
    public var color: String {
        switch self {
        case .good: return "green"
        case .warning: return "orange" 
        case .poor: return "red"
        }
    }
}

// MARK: - 🔧 개선: VideoToolbox 설정 프리셋

/// VideoToolbox 설정 프리셋
public enum VideoToolboxPreset {
    case lowLatency      // 저지연 우선
    case highQuality     // 고품질 우선
    case balanced        // 균형
    case powerEfficient  // 전력 효율
    
    public var description: String {
        switch self {
        case .lowLatency: return "저지연 모드"
        case .highQuality: return "고품질 모드"
        case .balanced: return "균형 모드"
        case .powerEfficient: return "전력 효율 모드"
        }
    }
    
    /// 프리셋에 따른 VTCompressionSession 설정값
    public var compressionProperties: [CFString: Any] {
        switch self {
        case .lowLatency:
            return [
                kVTCompressionPropertyKey_RealTime: kCFBooleanTrue as Any,
                kVTCompressionPropertyKey_AllowFrameReordering: kCFBooleanFalse as Any,
                kVTCompressionPropertyKey_Quality: 0.5 as Any,
                kVTCompressionPropertyKey_MaxKeyFrameInterval: 15 as Any
            ]
            
        case .highQuality:
            return [
                kVTCompressionPropertyKey_RealTime: kCFBooleanTrue as Any,
                kVTCompressionPropertyKey_AllowFrameReordering: kCFBooleanTrue as Any,
                kVTCompressionPropertyKey_Quality: 0.9 as Any,
                kVTCompressionPropertyKey_MaxKeyFrameInterval: 60 as Any
            ]
            
        case .balanced:
            return [
                kVTCompressionPropertyKey_RealTime: kCFBooleanTrue as Any,
                kVTCompressionPropertyKey_AllowFrameReordering: kCFBooleanFalse as Any,
                kVTCompressionPropertyKey_Quality: 0.7 as Any,
                kVTCompressionPropertyKey_MaxKeyFrameInterval: 30 as Any
            ]
            
        case .powerEfficient:
            return [
                kVTCompressionPropertyKey_RealTime: kCFBooleanTrue as Any,
                kVTCompressionPropertyKey_AllowFrameReordering: kCFBooleanFalse as Any,
                kVTCompressionPropertyKey_Quality: 0.6 as Any,
                kVTCompressionPropertyKey_MaxKeyFrameInterval: 45 as Any
            ]
        }
    }
}

// MARK: - 🔧 개선: VideoToolbox 헬퍼 익스텐션

extension PerformanceOptimizationManager {
    
    /// 프리셋을 사용한 간편 설정
    @available(iOS 17.4, *)
    public func setupHardwareCompressionWithPreset(
        settings: USBExternalCamera.LiveStreamSettings,
        preset: VideoToolboxPreset
    ) async throws {
        logger.info("🎯 VideoToolbox 프리셋 설정: \(preset.description)")
        
        // 기본 하드웨어 압축 설정
        try await setupHardwareCompressionWithRecovery(settings: settings)
        
        // 프리셋 속성 적용
        if let session = compressionSession {
            try applyPresetProperties(session, preset: preset)
        }
        
        logger.info("✅ VideoToolbox 프리셋 설정 완료: \(preset.description)")
    }
    
    /// 프리셋 속성 적용
    private func applyPresetProperties(_ session: VTCompressionSession, preset: VideoToolboxPreset) throws {
        let properties = preset.compressionProperties
        
        for (key, value) in properties {
            let status = VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
            if status != noErr {
                logger.warning("⚠️ 프리셋 속성 설정 실패: \(key)")
                // 중요하지 않은 설정은 실패해도 계속 진행
            }
        }
    }
    
    /// 실시간 성능 리포트 생성
    @MainActor
    public func generatePerformanceReport() -> VideoToolboxPerformanceMetrics {
        return VideoToolboxPerformanceMetrics(
            cpuUsage: currentCPUUsage,
            memoryUsage: currentMemoryUsage,
            compressionTime: frameProcessingTime,
            frameRate: 30.0, // 실제 측정값으로 대체 필요
            errorRate: 1.0 - compressionSuccessRate
        )
    }
    
    /// 성능 알림 발송
    @MainActor
    private func sendPerformanceAlert(_ metrics: VideoToolboxPerformanceMetrics) {
        NotificationCenter.default.post(
            name: .videoToolboxPerformanceAlert,
            object: nil,
            userInfo: [
                "metrics": metrics,
                "status": metrics.performanceStatus,
                "timestamp": metrics.timestamp
            ]
        )
    }
} 
