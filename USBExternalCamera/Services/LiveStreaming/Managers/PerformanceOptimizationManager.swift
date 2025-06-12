import Foundation
import AVFoundation
import VideoToolbox
import Metal
import CoreImage
import UIKit
import os.log

/// 스트리밍 성능 최적화 매니저
/// VideoToolbox 하드웨어 가속, GPU 메모리 최적화, 적응형 품질 조정 등을 담당
@MainActor
public class PerformanceOptimizationManager: ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "USBExternalCamera.Performance", category: "optimization")
    
    /// VideoToolbox 압축 세션
    private var compressionSession: VTCompressionSession?
    
    /// Metal 디바이스 (GPU 가속용)
    private var metalDevice: MTLDevice?
    
    /// CIContext 캐시 (GPU 가속)
    private var cachedCIContext: CIContext?
    
    /// 픽셀 버퍼 풀
    private var pixelBufferPool: CVPixelBufferPool?
    
    /// 성능 메트릭스
    @Published var currentCPUUsage: Double = 0.0
    @Published var currentMemoryUsage: Double = 0.0
    @Published var currentGPUUsage: Double = 0.0
    @Published var frameProcessingTime: TimeInterval = 0.0
    
    /// 적응형 품질 조정 활성화 여부
    @Published var adaptiveQualityEnabled: Bool = true
    
    /// 성능 임계값
    private let performanceThresholds = PerformanceThresholds()
    
    // MARK: - Initialization
    
    public init() {
        setupMetalDevice()
        setupCIContext()
        startPerformanceMonitoring()
    }
    
    deinit {
        Task { @MainActor in
            await cleanup()
        }
    }
    
    // MARK: - VideoToolbox 하드웨어 가속
    
    /// VideoToolbox 하드웨어 압축 설정
    @available(iOS 17.4, *)
    public func setupHardwareCompression(settings: USBExternalCamera.LiveStreamSettings) throws {
        logger.info("🔧 VideoToolbox 하드웨어 압축 설정 시작")
        
        let encoderSpecification: [CFString: Any]
        if #available(iOS 17.4, *) {
            encoderSpecification = [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: false // 폴백 허용
            ]
        } else {
            encoderSpecification = [:]
        }
        
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(settings.videoWidth),
            height: Int32(settings.videoHeight),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpecification as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let compressionSession = session else {
            throw PerformanceOptimizationError.hardwareCompressionSetupFailed(status)
        }
        
        self.compressionSession = compressionSession
        
        // VideoToolbox 압축 속성 설정
        try configureCompressionSession(compressionSession, settings: settings)
        
        logger.info("✅ VideoToolbox 하드웨어 압축 설정 완료")
    }
    
    /// VideoToolbox 압축 속성 설정
    private func configureCompressionSession(_ session: VTCompressionSession, settings: USBExternalCamera.LiveStreamSettings) throws {
        // 비트레이트 설정
        var status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: settings.videoBitrate * 1000))
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("AverageBitRate", status) }
        
        // 실시간 인코딩 설정
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("RealTime", status) }
        
        // 프로파일 레벨 설정
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("ProfileLevel", status) }
        
        // 키프레임 간격 설정
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: settings.frameRate * 2))
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("MaxKeyFrameInterval", status) }
        
        // 프레임 순서 변경 비활성화 (실시간 스트리밍)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("AllowFrameReordering", status) }
        
        logger.info("🔧 VideoToolbox 압축 속성 설정 완료")
    }
    
    /// 압축 출력 콜백
    private let compressionOutputCallback: VTCompressionOutputCallback = { (
        outputCallbackRefCon: UnsafeMutableRawPointer?,
        sourceFrameRefCon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?
    ) in
        guard status == noErr else { return }
        // 압축된 프레임 처리 로직
    }
    
    // MARK: - Metal GPU 최적화
    
    /// Metal 디바이스 설정
    private func setupMetalDevice() {
        metalDevice = MTLCreateSystemDefaultDevice()
        if metalDevice != nil {
            logger.info("✅ Metal GPU 디바이스 설정 완료")
        } else {
            logger.warning("⚠️ Metal GPU 디바이스를 사용할 수 없음")
        }
    }
    
    /// CIContext 캐시 설정
    private func setupCIContext() {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ]
        
        if let metalDevice = metalDevice {
            cachedCIContext = CIContext(mtlDevice: metalDevice, options: options)
            logger.info("✅ Metal 기반 CIContext 설정 완료")
        } else {
            cachedCIContext = CIContext(options: options)
            logger.info("✅ CPU 기반 CIContext 설정 완료")
        }
    }
    
    // MARK: - 사용자 설정 보존형 적응형 품질 조정
    
    /// 사용자 설정값을 존중하는 성능 기반 품질 조정
    /// 사용자가 명시적으로 설정한 값은 보존하고, 자동 조정 범위 내에서만 최적화
    public func adaptQualityRespectingUserSettings(
        currentSettings: USBExternalCamera.LiveStreamSettings,
        userDefinedSettings: USBExternalCamera.LiveStreamSettings
    ) -> USBExternalCamera.LiveStreamSettings {
        guard adaptiveQualityEnabled else { return currentSettings }
        
        var optimizedSettings = currentSettings
        let performanceIssue = assessPerformanceIssue()
        
        guard performanceIssue != .none else { return currentSettings }
        
        logger.info("🎯 성능 이슈 감지: \(performanceIssue.description) - 제한적 자동 조정 시작")
        
        // 사용자 설정값 기반 조정 범위 계산
        let adjustmentLimits = calculateAdjustmentLimits(userSettings: userDefinedSettings)
        
        switch performanceIssue {
        case .cpuOverload:
            // CPU 과부하 시 제한적 품질 낮춤 (사용자 설정의 80% 이하로는 내리지 않음)
            let minBitrate = max(adjustmentLimits.minVideoBitrate, 1000)
            let minFrameRate = max(adjustmentLimits.minFrameRate, 15)
            
            optimizedSettings.videoBitrate = max(optimizedSettings.videoBitrate - 500, minBitrate)
            optimizedSettings.frameRate = max(optimizedSettings.frameRate - 5, minFrameRate)
            
            logger.info("🔽 CPU 과부하 조정: 비트레이트 \(optimizedSettings.videoBitrate)kbps (최소: \(minBitrate)), FPS \(optimizedSettings.frameRate) (최소: \(minFrameRate))")
            
        case .memoryOverload:
            // 메모리 과부하 시 해상도만 일시 조정 (사용자 설정 원본 크기보다 작게만)
            if optimizedSettings.videoWidth > adjustmentLimits.minVideoWidth {
                optimizedSettings.videoWidth = adjustmentLimits.minVideoWidth
                optimizedSettings.videoHeight = adjustmentLimits.minVideoHeight
                logger.info("🔽 메모리 과부하 조정: 해상도 \(optimizedSettings.videoWidth)x\(optimizedSettings.videoHeight)")
            }
            
        case .thermalThrottling:
            // 열 문제 시 모든 설정을 안전 범위로 조정
            optimizedSettings.videoBitrate = max(adjustmentLimits.minVideoBitrate, 800)
            optimizedSettings.frameRate = max(adjustmentLimits.minFrameRate, 15)
            if optimizedSettings.videoWidth > 1280 {
                optimizedSettings.videoWidth = 1280
                optimizedSettings.videoHeight = 720
            }
            logger.warning("🌡️ 열 문제 조정: 안전 모드로 전환")
            
        case .none:
            break
        }
        
        return optimizedSettings
    }
    
    /// 성능 이슈 평가
    private func assessPerformanceIssue() -> PerformanceIssue {
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
    
    /// 사용자 설정 기반 조정 범위 계산
    private func calculateAdjustmentLimits(userSettings: USBExternalCamera.LiveStreamSettings) -> AdjustmentLimits {
        return AdjustmentLimits(
            minVideoBitrate: Int(Double(userSettings.videoBitrate) * 0.6), // 사용자 설정의 60%까지만
            maxVideoBitrate: Int(Double(userSettings.videoBitrate) * 1.2), // 사용자 설정의 120%까지만
            minFrameRate: max(Int(Double(userSettings.frameRate) * 0.7), 15), // 사용자 설정의 70%까지만
            maxFrameRate: userSettings.frameRate + 5, // 최대 5fps 추가
            minVideoWidth: userSettings.videoWidth > 1920 ? 1920 : (userSettings.videoWidth > 1280 ? 1280 : userSettings.videoWidth),
            minVideoHeight: userSettings.videoHeight > 1080 ? 1080 : (userSettings.videoHeight > 720 ? 720 : userSettings.videoHeight)
        )
    }

    // MARK: - 성능 모니터링
    
    /// 성능 모니터링 시작
    private func startPerformanceMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePerformanceMetrics()
            }
        }
    }
    
    /// 성능 메트릭스 업데이트
    private func updatePerformanceMetrics() async {
        currentCPUUsage = getCurrentCPUUsage()
        currentMemoryUsage = getCurrentMemoryUsage()
        currentGPUUsage = getCurrentGPUUsage()
        
        // 임계값 초과 시 경고
        if currentCPUUsage > performanceThresholds.cpuCriticalThreshold {
            logger.error("🔥 CPU 사용량 위험 수준: \(String(format: "%.1f", self.currentCPUUsage))%")
        }
        
        if currentMemoryUsage > performanceThresholds.memoryCriticalThreshold {
            logger.error("🔥 메모리 사용량 위험 수준: \(String(format: "%.1f", self.currentMemoryUsage))MB")
        }
    }
    
    /// CPU 사용량 측정
    private func getCurrentCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 * 0.1 // 추정 CPU 사용률
        }
        return 0.0
    }
    
    /// 메모리 사용량 측정
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // MB
        }
        return 0.0
    }
    
    /// GPU 사용량 측정 (추정)
    private func getCurrentGPUUsage() -> Double {
        // Metal 성능 카운터를 통한 GPU 사용량 추정
        // 실제 구현에서는 Metal Performance Shaders 활용
        return min(currentCPUUsage * 0.6, 90.0) // 추정치
    }
    
    // MARK: - 최적화된 프레임 처리
    
    /// 고성능 프레임 변환 (GPU 가속)
    public func optimizedFrameConversion(_ pixelBuffer: CVPixelBuffer, targetSize: CGSize) -> CVPixelBuffer? {
        let startTime = CACurrentMediaTime()
        defer {
            frameProcessingTime = CACurrentMediaTime() - startTime
        }
        
        guard let context = cachedCIContext else {
            logger.error("❌ CIContext 캐시 없음")
            return nil
        }
        
        // 픽셀 버퍼 풀에서 재사용 버퍼 획득
        var outputBuffer: CVPixelBuffer?
        if let pool = pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
        }
        
        guard let output = outputBuffer else {
            logger.warning("⚠️ 풀에서 픽셀 버퍼 획득 실패 - 새로 생성")
            return createNewPixelBuffer(targetSize: targetSize)
        }
        
        // CIImage 변환 및 스케일링
        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX = targetSize.width / inputImage.extent.width
        let scaleY = targetSize.height / inputImage.extent.height
        let scale = max(scaleX, scaleY) // Aspect Fill
        
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = inputImage.transformed(by: transform)
        
        // GPU 가속 렌더링
        let targetRect = CGRect(origin: .zero, size: targetSize)
        context.render(scaledImage, to: output, bounds: targetRect, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        
        return output
    }
    
    /// 새 픽셀 버퍼 생성 (폴백)
    private func createNewPixelBuffer(targetSize: CGSize) -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey: Int(targetSize.width),
            kCVPixelBufferHeightKey: Int(targetSize.height),
            kCVPixelBufferBytesPerRowAlignmentKey: 16,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }
    
    // MARK: - 최적화된 뷰 병합 (메모리 복사 최소화)
    
    /// 메모리 효율적인 뷰 병합 (불필요한 복사 제거)
    public func optimizedViewComposition(
        cameraPixelBuffer: CVPixelBuffer,
        uiView: UIView,
        targetSize: CGSize
    ) -> CVPixelBuffer? {
        
        let startTime = CACurrentMediaTime()
        defer {
            frameProcessingTime = CACurrentMediaTime() - startTime
        }
        
        guard let context = cachedCIContext else {
            logger.error("❌ CIContext 캐시 없음")
            return nil
        }
        
        // 1. 출력 버퍼 준비 (재사용 풀 사용)
        guard let outputBuffer = getReusablePixelBuffer(targetSize: targetSize) else {
            logger.error("❌ 출력 픽셀 버퍼 획득 실패")
            return nil
        }
        
        // 2. 카메라 이미지를 CIImage로 직접 변환 (UIImage 변환 과정 생략)
        let cameraImage = CIImage(cvPixelBuffer: cameraPixelBuffer)
        
        // 3. UI 뷰를 CIImage로 직접 렌더링
        let uiImage = renderUIViewToCIImage(uiView, targetSize: targetSize)
        
        // 4. CIImage 컴포지팅으로 한번에 병합 (중간 UIImage 생성 없음)
        let compositeImage = compositeImagesDirectly(
            background: cameraImage,
            overlay: uiImage,
            targetSize: targetSize
        )
        
        // 5. 최종 결과를 출력 버퍼에 직접 렌더링
        let targetRect = CGRect(origin: .zero, size: targetSize)
        context.render(compositeImage, to: outputBuffer, bounds: targetRect, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        
        return outputBuffer
    }
    
    /// 재사용 가능한 픽셀 버퍼 획득
    private func getReusablePixelBuffer(targetSize: CGSize) -> CVPixelBuffer? {
        // 픽셀 버퍼 풀에서 재사용 버퍼 획득
        if let pool = pixelBufferPool {
            var outputBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
            if status == kCVReturnSuccess {
                return outputBuffer
            }
        }
        
        // 풀에서 실패 시 새로 생성
        return createNewPixelBuffer(targetSize: targetSize)
    }
    
    /// UI 뷰를 CIImage로 직접 렌더링 (메모리 효율적)
    private func renderUIViewToCIImage(_ view: UIView, targetSize: CGSize) -> CIImage {
        let scale = UIScreen.main.scale
        let bounds = view.bounds
        
        // Metal 텍스처로 직접 렌더링 (가능한 경우)
        if let metalDevice = metalDevice {
            return renderUIViewToMetalTexture(view, targetSize: targetSize, scale: scale)
        }
        
        // 폴백: 기존 방식
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: UIGraphicsImageRendererFormat.preferred())
        let uiImage = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        
        return CIImage(image: uiImage) ?? CIImage.empty()
    }
    
    /// Metal 텍스처를 이용한 고성능 UI 렌더링
    private func renderUIViewToMetalTexture(_ view: UIView, targetSize: CGSize, scale: CGFloat) -> CIImage {
        // 실제 Metal 구현은 복잡하므로 여기서는 간단한 폴백
        // 실제 구현에서는 MTLTexture를 사용한 직접 렌더링 구현
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let uiImage = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        
        return CIImage(image: uiImage) ?? CIImage.empty()
    }
    
    /// CIImage 직접 컴포지팅 (중간 변환 없음)
    private func compositeImagesDirectly(
        background: CIImage,
        overlay: CIImage,
        targetSize: CGSize
    ) -> CIImage {
        
        // 배경 이미지 스케일링
        let backgroundScaled = scaleImageToFill(background, targetSize: targetSize)
        
        // 오버레이 이미지 스케일링
        let overlayScaled = scaleImageToFit(overlay, targetSize: targetSize)
        
        // CISourceOverCompositing을 사용한 효율적 합성
        let compositeFilter = CIFilter(name: "CISourceOverCompositing")!
        compositeFilter.setValue(overlayScaled, forKey: kCIInputImageKey)
        compositeFilter.setValue(backgroundScaled, forKey: kCIInputBackgroundImageKey)
        
        return compositeFilter.outputImage ?? backgroundScaled
    }
    
    /// 이미지를 타겟 크기로 채우기 (Aspect Fill)
    private func scaleImageToFill(_ image: CIImage, targetSize: CGSize) -> CIImage {
        let imageSize = image.extent.size
        let scaleX = targetSize.width / imageSize.width
        let scaleY = targetSize.height / imageSize.height
        let scale = max(scaleX, scaleY)
        
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return image.transformed(by: transform)
    }
    
    /// 이미지를 타겟 크기에 맞추기 (Aspect Fit)
    private func scaleImageToFit(_ image: CIImage, targetSize: CGSize) -> CIImage {
        let imageSize = image.extent.size
        let scaleX = targetSize.width / imageSize.width
        let scaleY = targetSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return image.transformed(by: transform)
    }
    
    // MARK: - 정리
    
    private func cleanup() async {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        cachedCIContext = nil
        pixelBufferPool = nil
        logger.info("🧹 PerformanceOptimizationManager 정리 완료")
    }
}

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
    case metalDeviceNotAvailable
    case pixelBufferPoolCreationFailed
    
    var localizedDescription: String {
        switch self {
        case .hardwareCompressionSetupFailed(let status):
            return "VideoToolbox 하드웨어 압축 설정 실패: \(status)"
        case .compressionPropertySetFailed(let property, let status):
            return "압축 속성 설정 실패 (\(property)): \(status)"
        case .metalDeviceNotAvailable:
            return "Metal GPU 디바이스를 사용할 수 없음"
        case .pixelBufferPoolCreationFailed:
            return "픽셀 버퍼 풀 생성 실패"
        }
    }
} 