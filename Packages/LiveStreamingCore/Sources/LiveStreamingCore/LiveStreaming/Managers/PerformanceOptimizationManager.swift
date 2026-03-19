import Foundation
import AVFoundation
import VideoToolbox
import Metal
import CoreImage
import UIKit
import os.log
import Accelerate
/// 스트리밍 성능 최적화 매니저
/// VideoToolbox 하드웨어 가속, GPU 메모리 최적화, 적응형 품질 조정 등을 담당
/// 🔧 개선: 성능 모니터링은 백그라운드에서, UI 업데이트만 메인 스레드에서 처리
public class PerformanceOptimizationManager: ObservableObject {
    // MARK: - Properties
    let logger = Logger(subsystem: "USBExternalCamera.Performance", category: "optimization")
    /// 강화된 압축 출력 콜백
    let compressionOutputCallback: VTCompressionOutputCallback = { (
        outputCallbackRefCon: UnsafeMutableRawPointer?,
        sourceFrameRefCon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?
    ) in

        guard let managerPointer = outputCallbackRefCon else { return }
        let manager = Unmanaged<PerformanceOptimizationManager>.fromOpaque(managerPointer)
          .takeUnretainedValue()

        guard status == noErr else {
            manager.handleCompressionError(status: status, infoFlags: infoFlags)
            return
        }

        guard let sampleBuffer = sampleBuffer else {
            manager.logger.error("❌ 압축 콜백: SampleBuffer가 nil")
            return
        }

        manager.collectCompressionStatistics(sampleBuffer: sampleBuffer, infoFlags: infoFlags)
        manager.forwardCompressedFrame(sampleBuffer: sampleBuffer)
    }
    /// VideoToolbox 압축 세션
    var compressionSession: VTCompressionSession?
    /// Metal 디바이스 (GPU 가속용)
    var metalDevice: MTLDevice?
    /// CIContext 캐시 (GPU 가속)
    var cachedCIContext: CIContext?
    /// 픽셀 버퍼 풀
    var pixelBufferPool: CVPixelBufferPool?
    /// 성능 메트릭스 (메인 스레드에서 UI 업데이트)
    @MainActor @Published var currentCPUUsage: Double = 0.0
    @MainActor @Published var currentMemoryUsage: Double = 0.0
    @MainActor @Published var currentGPUUsage: Double = 0.0
    @MainActor @Published var frameProcessingTime: TimeInterval = 0.0
    /// 적응형 품질 조정 활성화 여부
    @MainActor @Published var adaptiveQualityEnabled: Bool = true
    /// 백그라운드 큐 (성능 모니터링용)
    let performanceQueue = DispatchQueue(label: "PerformanceMonitoring", qos: .utility)
    /// 성능 임계값
    let performanceThresholds = PerformanceThresholds()
    // MARK: - 🔧 개선: VideoToolbox 통계 및 진단 추가
    /// 압축 통계
    @MainActor @Published var compressionErrorCount: Int = 0
    @MainActor @Published var lastCompressionErrorTime: Date?
    @MainActor @Published var averageCompressionTime: TimeInterval = 0.0
    @MainActor @Published var compressionSuccessRate: Double = 1.0
    /// 지원되는 픽셀 포맷 목록
    var supportedPixelFormats: [OSType] = [
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_32BGRA
    ]
    /// 압축 통계 추적
    var compressionStats = VideoToolboxCompressionStats()
    // MARK: - Initialization
    public init() {
        setupMetalDevice()
        setupCIContext()
        startPerformanceMonitoring()
        startAdvancedPerformanceMonitoring()
    }
    deinit {
        Task { @MainActor in
            await cleanup()
        }
    }
    // MARK: - 🔧 개선: 강화된 VideoToolbox 하드웨어 가속
    /// 강화된 VideoToolbox 하드웨어 압축 설정 (복구 로직 포함)
    @available(iOS 17.4, *)
    public func setupHardwareCompressionWithRecovery(settings: LiveStreamSettings) async throws {
        logger.info("🔧 VideoToolbox 하드웨어 압축 설정 시작 (복구 로직 포함)")
        var lastError: Error?
        let maxRetries = 3
        // 1단계: 하드웨어 우선 시도
        for attempt in 1...maxRetries {
            do {
                try await attemptHardwareCompression(settings: settings, attempt: attempt)
                logger.info("✅ VideoToolbox 하드웨어 압축 설정 성공 (시도: \(attempt))")
                return
            } catch let error as PerformanceOptimizationError {
                lastError = error
                logger.warning("⚠️ 하드웨어 압축 시도 \(attempt) 실패: \(error)")
                if attempt < maxRetries {
                    // 재시도 전 복구 작업
                    await performRecoveryActions(for: error, attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(attempt * 500_000_000)) // 0.5초 * 시도횟수
                }
            }
        }
        // 2단계: 소프트웨어 폴백 시도
        logger.warning("⚠️ 하드웨어 압축 실패 - 소프트웨어 폴백 시도")
        do {
            try await attemptSoftwareCompression(settings: settings)
            logger.info("✅ VideoToolbox 소프트웨어 압축 설정 성공")
        } catch {
            logger.error("❌ VideoToolbox 소프트웨어 압축도 실패: \(error)")
            throw PerformanceOptimizationError.compressionSetupFailed(lastError ?? error)
        }
    }
    /// 하드웨어 압축 시도
    func attemptHardwareCompression(settings: LiveStreamSettings, attempt: Int) async throws {
        // 시도별 다른 전략 적용
        let encoderSpec = getEncoderSpecification(for: attempt)
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(settings.videoWidth),
            height: Int32(settings.videoHeight),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpec,
            imageBufferAttributes: getImageBufferAttributes(for: attempt),
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let compressionSession = session else {
            throw PerformanceOptimizationError.hardwareCompressionSetupFailed(status)
        }
        self.compressionSession = compressionSession
        try configureCompressionSessionWithFallback(compressionSession, settings: settings, attempt: attempt)
    }
    /// 소프트웨어 압축 시도 (폴백)
    func attemptSoftwareCompression(settings: LiveStreamSettings) async throws {
        var encoderSpec: [CFString: Any] = [:]
        // iOS 17.4 이상에서만 하드웨어 가속 비활성화 옵션 사용
        if #available(iOS 17.4, *) {
            encoderSpec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = false
        }
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(settings.videoWidth),
            height: Int32(settings.videoHeight),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpec as CFDictionary,
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
        try configureCompressionSession(compressionSession, settings: settings)
    }
    /// 시도별 인코더 사양 반환
    func getEncoderSpecification(for attempt: Int) -> CFDictionary {
        var encoderSpec: [CFString: Any] = [:]
        // iOS 17.4 이상에서만 하드웨어 가속 관련 옵션 사용
        if #available(iOS 17.4, *) {
            switch attempt {
            case 1:
                // 첫 번째 시도: 엄격한 하드웨어 요구
                encoderSpec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = true
                encoderSpec[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = true
            case 2:
                // 두 번째 시도: 하드웨어 선호, 폴백 허용
                encoderSpec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = true
                encoderSpec[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = false
            default:
                // 세 번째 시도: 기본 설정
                break
            }
        }
        return encoderSpec as CFDictionary
    }
    /// 시도별 이미지 버퍼 속성 반환
    func getImageBufferAttributes(for attempt: Int) -> CFDictionary? {
        switch attempt {
        case 1:
            // 첫 번째 시도: 최적화된 속성
            return [
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferBytesPerRowAlignmentKey: 64,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ] as CFDictionary
        default:
            // 기본 시도: 기본 속성
            return nil
        }
    }
    /// 폴백 지원 압축 세션 설정
    func configureCompressionSessionWithFallback(_ session: VTCompressionSession, settings: LiveStreamSettings, attempt: Int) throws {
        // 기본 설정 시도
        do {
            try configureCompressionSession(session, settings: settings)
        } catch {
            // 설정 실패 시 더 관대한 설정으로 재시도
            logger.warning("⚠️ 기본 압축 설정 실패 - 관대한 설정으로 재시도")
            try configureCompressionSessionWithRelaxedSettings(session, settings: settings)
        }
    }
    /// 관대한 설정으로 압축 세션 구성
    func configureCompressionSessionWithRelaxedSettings(_ session: VTCompressionSession, settings: LiveStreamSettings) throws {
        // 필수 설정만 적용
        var status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: settings.videoBitrate * 1000))
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("AverageBitRate", status) }
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("RealTime", status) }
        // 프로파일 레벨을 Main으로 낮춤
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        if status != noErr {
            logger.warning("⚠️ Main 프로파일 설정 실패 - Baseline으로 폴백")
            status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        }
        logger.info("✅ 관대한 압축 설정 완료")
    }
}
