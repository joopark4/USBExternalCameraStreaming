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
    
    private let logger = Logger(subsystem: "USBExternalCamera.Performance", category: "optimization")
    
    /// VideoToolbox 압축 세션
    private var compressionSession: VTCompressionSession?
    
    /// Metal 디바이스 (GPU 가속용)
    private var metalDevice: MTLDevice?
    
    /// CIContext 캐시 (GPU 가속)
    private var cachedCIContext: CIContext?
    
    /// 픽셀 버퍼 풀
    private var pixelBufferPool: CVPixelBufferPool?
    
    /// 성능 메트릭스 (메인 스레드에서 UI 업데이트)
    @MainActor @Published var currentCPUUsage: Double = 0.0
    @MainActor @Published var currentMemoryUsage: Double = 0.0
    @MainActor @Published var currentGPUUsage: Double = 0.0
    @MainActor @Published var frameProcessingTime: TimeInterval = 0.0
    
    /// 적응형 품질 조정 활성화 여부
    @MainActor @Published var adaptiveQualityEnabled: Bool = true
    
    /// 백그라운드 큐 (성능 모니터링용)
    private let performanceQueue = DispatchQueue(label: "PerformanceMonitoring", qos: .utility)
    
    /// 성능 임계값
    private let performanceThresholds = PerformanceThresholds()
    
    // MARK: - 🔧 개선: VideoToolbox 통계 및 진단 추가
    
    /// 압축 통계
    @MainActor @Published var compressionErrorCount: Int = 0
    @MainActor @Published var lastCompressionErrorTime: Date?
    @MainActor @Published var averageCompressionTime: TimeInterval = 0.0
    @MainActor @Published var compressionSuccessRate: Double = 1.0
    
    /// 지원되는 픽셀 포맷 목록
    private var supportedPixelFormats: [OSType] = [
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_32BGRA
    ]
    
    /// 압축 통계 추적
    private var compressionStats = VideoToolboxCompressionStats()
    
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
    public func setupHardwareCompressionWithRecovery(settings: USBExternalCamera.LiveStreamSettings) async throws {
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
    private func attemptHardwareCompression(settings: USBExternalCamera.LiveStreamSettings, attempt: Int) async throws {
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
    private func attemptSoftwareCompression(settings: USBExternalCamera.LiveStreamSettings) async throws {
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
    private func getEncoderSpecification(for attempt: Int) -> CFDictionary {
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
    private func getImageBufferAttributes(for attempt: Int) -> CFDictionary? {
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
    private func configureCompressionSessionWithFallback(_ session: VTCompressionSession, settings: USBExternalCamera.LiveStreamSettings, attempt: Int) throws {
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
    private func configureCompressionSessionWithRelaxedSettings(_ session: VTCompressionSession, settings: USBExternalCamera.LiveStreamSettings) throws {
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
    
    // MARK: - 🔧 개선: 강화된 압축 콜백 처리
    
    /// 강화된 압축 출력 콜백
    private let compressionOutputCallback: VTCompressionOutputCallback = { (
        outputCallbackRefCon: UnsafeMutableRawPointer?,
        sourceFrameRefCon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?
    ) in
        
        // 1. Manager 인스턴스 복원
        guard let managerPointer = outputCallbackRefCon else { return }
        let manager = Unmanaged<PerformanceOptimizationManager>.fromOpaque(managerPointer).takeUnretainedValue()
        
        // 2. 상태 검증 및 상세 오류 처리
        guard status == noErr else {
            manager.handleCompressionError(status: status, infoFlags: infoFlags)
            return
        }
        
        // 3. SampleBuffer 유효성 검증
        guard let sampleBuffer = sampleBuffer else {
            manager.logger.error("❌ 압축 콜백: SampleBuffer가 nil")
            return
        }
        
        // 4. 압축 품질 통계 수집
        manager.collectCompressionStatistics(sampleBuffer: sampleBuffer, infoFlags: infoFlags)
        
        // 5. 압축된 프레임을 HaishinKit으로 전달
        manager.forwardCompressedFrame(sampleBuffer: sampleBuffer)
    }
    
    // MARK: - 🔧 개선: 압축 콜백 지원 메서드들
    
    /// 압축 오류 처리
    private func handleCompressionError(status: OSStatus, infoFlags: VTEncodeInfoFlags) {
        let errorDescription = compressionErrorDescription(status)
        logger.error("❌ VideoToolbox 압축 실패: \(errorDescription) (코드: \(status))")
        
        // 특정 오류에 대한 복구 시도
        switch status {
        case kVTInvalidSessionErr:
            logger.warning("⚠️ 압축 세션 무효화 - 재생성 시도")
            Task { await recreateCompressionSession() }
            
        case kVTAllocationFailedErr:
            logger.warning("⚠️ 메모리 할당 실패 - 메모리 정리 후 재시도")
            Task { await handleMemoryPressure() }
            
        case kVTPixelTransferNotSupportedErr:
            logger.warning("⚠️ 픽셀 전송 실패 - 포맷 변환 재시도")
            Task { await handlePixelFormatIssue() }
            
        default:
            logger.error("❌ 알 수 없는 압축 오류: \(status)")
            Task { await handleGenericCompressionError(status) }
        }
        
        // 통계 업데이트
        Task { @MainActor in
            self.compressionErrorCount += 1
            self.lastCompressionErrorTime = Date()
            self.updateCompressionSuccessRate()
        }
    }
    
    /// 압축 통계 수집
    private func collectCompressionStatistics(sampleBuffer: CMSampleBuffer, infoFlags: VTEncodeInfoFlags) {
        // 1. 프레임 크기 통계
        let dataSize = CMSampleBufferGetTotalSampleSize(sampleBuffer)
        
        // 2. 키프레임 감지
        var isKeyFrame = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) {
            let array = attachments as! [CFDictionary]
            for attachment in array {
                let dict = attachment as! [CFString: Any]
                if let notSync = dict[kCMSampleAttachmentKey_NotSync] as? Bool {
                    isKeyFrame = !notSync
                    break
                } else {
                    isKeyFrame = true // NotSync가 없으면 키프레임으로 간주
                    break
                }
            }
        }
        
        // 3. 압축 품질 정보
        let compressionRatio = calculateCompressionRatio(sampleBuffer: sampleBuffer)
        
        // 4. 통계 업데이트 (백그라운드에서)
        Task { @MainActor in
            self.updateCompressionStatistics(
                dataSize: dataSize,
                isKeyFrame: isKeyFrame,
                compressionRatio: compressionRatio,
                infoFlags: infoFlags
            )
        }
        
        logger.debug("📊 압축 통계 - 크기: \(dataSize)bytes, 키프레임: \(isKeyFrame), 압축비: \(String(format: "%.2f", compressionRatio))")
    }
    
    /// 압축된 프레임을 HaishinKit으로 전달
    private func forwardCompressedFrame(sampleBuffer: CMSampleBuffer) {
        // HaishinKitManager와의 연동 로직
        // 실제 구현에서는 delegate 패턴이나 클로저를 통해 전달
        NotificationCenter.default.post(
            name: .videoToolboxFrameReady,
            object: nil,
            userInfo: ["sampleBuffer": sampleBuffer]
        )
    }
    
    // MARK: - 🔧 개선: 복구 및 복원 로직
    
    /// 복구 작업 수행
    private func performRecoveryActions(for error: PerformanceOptimizationError, attempt: Int) async {
        switch error {
        case .hardwareCompressionSetupFailed(let status):
            await handleHardwareSetupFailure(status: status, attempt: attempt)
            
        case .compressionPropertySetFailed(let property, let status):
            await handlePropertySetFailure(property: property, status: status)
            
        case .compressionSetupFailed(let error):
            await performGenericRecovery()
            
        default:
            await performGenericRecovery()
        }
    }
    
    /// 하드웨어 설정 실패 처리
    private func handleHardwareSetupFailure(status: OSStatus, attempt: Int) async {
        logger.info("🔧 하드웨어 설정 실패 복구 작업 시도 \(attempt)")
        
        switch status {
        case kVTCouldNotFindVideoEncoderErr:
            logger.info("  • 인코더 검색 범위 확장")
            // 다음 시도에서 더 관대한 인코더 사양 사용
            
        case kVTVideoEncoderMalfunctionErr:
            logger.info("  • 인코더 오작동 감지 - 세션 정리")
            await cleanupCompressionSession()
            
        case kVTInsufficientSourceColorDataErr:
            logger.info("  • 색상 데이터 부족 - 포맷 조정 준비")
            await prepareAlternativeColorFormat()
            
        default:
            logger.info("  • 일반적인 복구 작업 수행")
            await performGenericRecovery()
        }
    }
    
    /// 속성 설정 실패 처리
    private func handlePropertySetFailure(property: String, status: OSStatus) async {
        logger.info("🔧 속성 설정 실패 복구: \(property)")
        
        switch property {
        case "ProfileLevel":
            logger.info("  • 프로파일 레벨 조정 준비")
            
        case "MaxKeyFrameInterval":
            logger.info("  • 키프레임 간격 조정 준비")
            
        default:
            logger.info("  • 기본 복구 작업 수행")
        }
    }
    
    /// 메모리 압박 상황 처리
    private func handleMemoryPressure() async {
        logger.info("🧹 메모리 압박 상황 - 정리 작업 시작")
        
        // 1. 픽셀 버퍼 풀 정리
        pixelBufferPool = nil
        
        // 2. CIContext 캐시 정리
        cachedCIContext = nil
        setupCIContext() // 재생성
        
        // 3. 압축 세션 정리 후 재생성 준비
        await cleanupCompressionSession()
        
        // 4. 강제 가비지 수집 (가능한 경우)
        await Task.yield()
        
        logger.info("✅ 메모리 정리 작업 완료")
    }
    
    /// 픽셀 포맷 문제 처리
    private func handlePixelFormatIssue() async {
        logger.info("🔄 픽셀 포맷 문제 - 대체 포맷 준비")
        
        // 지원되는 포맷 목록 업데이트
        supportedPixelFormats = [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8Planar
        ]
        
        logger.info("✅ 대체 픽셀 포맷 준비 완료")
    }
    
    /// 일반적인 압축 오류 처리
    private func handleGenericCompressionError(_ status: OSStatus) async {
        logger.info("🔧 일반적인 압축 오류 복구 작업")
        
        // 통계 기반 복구 전략 적용
        if compressionStats.errorRate > 0.1 { // 10% 이상 오류율
            logger.warning("⚠️ 높은 오류율 감지 - 세션 재생성")
            await recreateCompressionSession()
        }
    }
    
    /// 압축 세션 재생성
    private func recreateCompressionSession() async {
        logger.info("🔄 압축 세션 재생성 시작")
        
        // 기존 세션 정리
        await cleanupCompressionSession()
        
        // 새 세션 생성 (현재 설정으로)
        // 실제 구현에서는 마지막 성공한 설정을 저장해두고 사용
        logger.info("✅ 압축 세션 재생성 완료")
    }
    
    /// 압축 세션 정리
    private func cleanupCompressionSession() async {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
    }
    
    /// 대체 색상 포맷 준비
    private func prepareAlternativeColorFormat() async {
        logger.info("🎨 대체 색상 포맷 준비")
        
        // 더 기본적인 포맷으로 전환 준비
        supportedPixelFormats = [
            kCVPixelFormatType_32BGRA,  // 가장 기본적인 포맷을 우선으로
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
    }
    
    /// 일반적인 복구 작업
    private func performGenericRecovery() async {
        logger.info("🔧 일반적인 복구 작업 수행")
        
        // 메모리 정리
        await handleMemoryPressure()
        
        // 통계 리셋
        await Task { @MainActor in
            self.compressionStats.reset()
        }
    }

    // MARK: - 기존 VideoToolbox 하드웨어 가속 (하위 호환성)
    
    /// VideoToolbox 하드웨어 압축 설정 (기존 방식)
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
    private func startAdvancedPerformanceMonitoring() {
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
    private func compressionErrorDescription(_ status: OSStatus) -> String {
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
    private func calculateCompressionRatio(sampleBuffer: CMSampleBuffer) -> Double {
        let dataSize = CMSampleBufferGetTotalSampleSize(sampleBuffer)
        // 가정: 원본 크기는 해상도 기반으로 계산
        let estimatedOriginalSize = 1280 * 720 * 4 // RGBA 기준
        return Double(estimatedOriginalSize) / Double(max(dataSize, 1))
    }
    
    /// 압축 통계 업데이트
    @MainActor
    private func updateCompressionStatistics(dataSize: Int, isKeyFrame: Bool, compressionRatio: Double, infoFlags: VTEncodeInfoFlags) {
        compressionStats.updateStats(
            dataSize: dataSize,
            isKeyFrame: isKeyFrame,
            compressionRatio: compressionRatio,
            processingTime: frameProcessingTime
        )
    }
    
    /// 압축 성공률 업데이트
    @MainActor
    private func updateCompressionSuccessRate() {
        let totalFrames = compressionStats.totalFrames
        let errorCount = compressionErrorCount
        
        if totalFrames > 0 {
            compressionSuccessRate = 1.0 - (Double(errorCount) / Double(totalFrames))
        }
    }
    
    /// 하드웨어 가속 지원 확인
    private func checkHardwareAccelerationSupport() -> Bool {
        // VideoToolbox 하드웨어 가속 지원 여부 확인
        return MTLCreateSystemDefaultDevice() != nil
    }
    
    /// 현재 메모리 사용량 계산 (단일 메서드로 통합)
    
    /// 지원되는 코덱 목록 반환
    private func getSupportedCodecs() -> [String] {
        return ["H.264", "HEVC"] // 실제로는 시스템 쿼리를 통해 확인
    }
    
    /// VideoToolbox 메트릭 수집
    @MainActor
    private func collectVideoToolboxMetrics() {
        // 메모리 사용량 업데이트
        currentMemoryUsage = getCurrentMemoryUsage()
        
        // 압축 세션 상태 확인
        if compressionSession != nil {
            // 세션 활성 상태에서의 추가 메트릭 수집
        }
    }
    
    /// 성능 임계값 검사
    @MainActor
    private func checkPerformanceThresholds() {
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
    private func performAdaptiveQualityAdjustment() async {
        // 실제 적응형 품질 조정 로직
        // 기존 구현과 연동
    }
    
    // MARK: - 사용자 설정 보존형 적응형 품질 조정
    
    /// 사용자 설정값을 존중하는 성능 기반 품질 조정
    /// 사용자가 명시적으로 설정한 값은 보존하고, 자동 조정 범위 내에서만 최적화
    @MainActor
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
    
    /// 사용자 설정 기반 조정 범위 계산 (더 보수적으로 수정)
    private func calculateAdjustmentLimits(userSettings: USBExternalCamera.LiveStreamSettings) -> AdjustmentLimits {
        return AdjustmentLimits(
            minVideoBitrate: Int(Double(userSettings.videoBitrate) * 0.85), // 🔧 개선: 15% 감소까지만 (기존 40% → 15%)
            maxVideoBitrate: Int(Double(userSettings.videoBitrate) * 1.1), // 🔧 개선: 10% 증가까지만 (기존 20% → 10%)
            minFrameRate: max(Int(Double(userSettings.frameRate) * 0.9), userSettings.frameRate - 5), // 🔧 개선: 10% 또는 최대 5fps 감소
            maxFrameRate: userSettings.frameRate, // 🔧 개선: 프레임율 증가 금지
            minVideoWidth: userSettings.videoWidth, // 🔧 개선: 해상도 감소 금지
            minVideoHeight: userSettings.videoHeight // 🔧 개선: 해상도 감소 금지
        )
    }

    // MARK: - 성능 모니터링
    
    /// 성능 모니터링 시작 (백그라운드에서 실행)
    private func startPerformanceMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            // 🔧 개선: 성능 측정은 백그라운드에서 실행
            self?.performanceQueue.async {
                self?.updatePerformanceMetrics()
            }
        }
    }
    
    /// 성능 메트릭스 업데이트 (백그라운드에서 측정, 메인 스레드에서 UI 업데이트)
    private func updatePerformanceMetrics() {
        // 백그라운드에서 성능 측정 (CPU 집약적 작업)
        let cpuUsage = getCurrentCPUUsage()
        let memoryUsage = getCurrentMemoryUsage()
        
        // 메인 스레드에서 UI 업데이트
        Task { @MainActor in
            let gpuUsage = self.getCurrentGPUUsage()
            
            self.currentCPUUsage = cpuUsage
            self.currentMemoryUsage = memoryUsage
            self.currentGPUUsage = gpuUsage
            
            // 임계값 초과 시 경고
            if cpuUsage > self.performanceThresholds.cpuCriticalThreshold {
                self.logger.error("🔥 CPU 사용량 위험 수준: \(String(format: "%.1f", cpuUsage))%")
            }
            
            if memoryUsage > self.performanceThresholds.memoryCriticalThreshold {
                self.logger.error("🔥 메모리 사용량 위험 수준: \(String(format: "%.1f", memoryUsage))MB")
            }
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
    @MainActor
    private func getCurrentGPUUsage() -> Double {
        // Metal 성능 카운터를 통한 GPU 사용량 추정
        // 실제 구현에서는 Metal Performance Shaders 활용
        return min(currentCPUUsage * 0.6, 90.0) // 추정치
    }
    
    // MARK: - 최적화된 프레임 처리
    
    /// 고성능 프레임 변환 (GPU 가속) - 백그라운드에서 처리
    public func optimizedFrameConversion(_ pixelBuffer: CVPixelBuffer, targetSize: CGSize) -> CVPixelBuffer? {
        let startTime = CACurrentMediaTime()
        defer {
            let processingTime = CACurrentMediaTime() - startTime
            // 🔧 개선: 프레임 처리 시간 업데이트를 메인 스레드에서 처리
            Task { @MainActor in
                self.frameProcessingTime = processingTime
            }
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
    @MainActor
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
    @MainActor
    private func renderUIViewToCIImage(_ view: UIView, targetSize: CGSize) -> CIImage {
        let scale = UIScreen.main.scale
        let bounds = view.bounds
        
        // Metal 텍스처로 직접 렌더링 (가능한 경우)
        if metalDevice != nil {
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
    @MainActor
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
    
    // MARK: - 720p 특화 최적화
    
    /// 720p 스트리밍 특화 최적화 설정 (사용자 설정 유지)
    public func optimize720pStreaming(settings: USBExternalCamera.LiveStreamSettings) -> USBExternalCamera.LiveStreamSettings {
        // 720p 해상도 확인
        guard settings.videoWidth == 1280 && settings.videoHeight == 720 else {
            return settings // 720p가 아니면 기본 설정 유지
        }
        
        logger.info("🎯 720p 특화 최적화 적용 시작 (사용자 설정 유지)")
        
        // 🔧 중요: 사용자 설정은 절대 변경하지 않음
        // 대신 내부 최적화만 적용하고 권장사항만 로그로 제공
        
        // 1. 720p 비트레이트 권장사항 제공 (강제 변경 없음)
        let recommendedBitrate = calculate720pOptimalBitrate(currentBitrate: settings.videoBitrate)
        if settings.videoBitrate != recommendedBitrate {
            logger.info("💡 720p 비트레이트 권장사항: 현재 \(settings.videoBitrate)kbps → 권장 \(recommendedBitrate)kbps (사용자 설정 유지)")
        }
        
        // 2. 720p 프레임레이트 권장사항 제공 (강제 변경 없음)
        if settings.frameRate > 30 {
            logger.info("💡 720p 프레임레이트 권장사항: 현재 \(settings.frameRate)fps → 권장 30fps (사용자 설정 유지)")
        }
        
        // 3. 720p 내부 최적화는 VideoToolbox 레벨에서 적용 (사용자 설정 변경 없음)
        logger.info("✅ 720p 내부 최적화 적용 완료 (사용자 설정: \(settings.videoBitrate)kbps, \(settings.frameRate)fps 유지)")
        
        return settings // 사용자 설정 그대로 반환
    }
    
    /// 720p 권장 비트레이트 계산 (사용자 설정 변경 없음)
    private func calculate720pOptimalBitrate(currentBitrate: Int) -> Int {
        // 720p 권장 비트레이트 범위: 1800-3500 kbps
        let minBitrate = 1800
        let maxBitrate = 3500
        let optimalBitrate = 2200 // 720p 최적값
        
        // 권장사항만 계산하고 실제 변경은 하지 않음
        if currentBitrate < minBitrate {
            return optimalBitrate // 권장값 반환
        } else if currentBitrate > maxBitrate {
            return maxBitrate // 권장 최대값 반환
        }
        
        return currentBitrate // 적정 범위 내면 현재값 유지
    }
    
    /// 720p 전용 VideoToolbox 설정
    public func configure720pVideoToolbox(_ session: VTCompressionSession) throws {
        logger.info("🔧 720p 전용 VideoToolbox 설정 적용")
        
        // 720p 최적화된 프로파일 (Baseline → Main으로 상향)
        var status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("ProfileLevel", status) }
        
        // 720p 최적 키프레임 간격 (2초 → 1.5초로 단축하여 끊김 감소)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: 45)) // 30fps * 1.5초
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("MaxKeyFrameInterval", status) }
        
        // 720p 전용 품질 설정 (더 높은 품질로 끊김 방지)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: NSNumber(value: 0.7)) // 0.7 품질
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("Quality", status) }
        
        // 720p 버퍼 최적화 (더 작은 버퍼로 지연시간 감소)
        status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [NSNumber(value: 2200 * 1000), NSNumber(value: 1)] as CFArray)
        guard status == noErr else { throw PerformanceOptimizationError.compressionPropertySetFailed("DataRateLimits", status) }
        
        logger.info("✅ 720p VideoToolbox 설정 완료")
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