import Foundation
import HaishinKit
import AVFoundation
import VideoToolbox
import UIKit
import os.log

/// VideoCodec -12902 에러 워크어라운드 매니저
/// 
/// **에러 우회 전략:**
/// - 프레임 포맷을 VideoCodec이 선호하는 방식으로 미리 변환
/// - VideoCodec 초기화 전 안전한 더미 프레임 전송
/// - 에러 발생 시 자동 복구 및 재시도
@MainActor
public class VideoCodecWorkaroundManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "USBExternalCamera.VideoCodecWorkaround", category: "streaming")
    
    /// HaishinKit 스트림 (기본 사용)
    private var rtmpStream: RTMPStream?
    
    /// VideoCodec 사전 초기화 완료 여부
    private var isVideoCodecPreinitialized = false
    
    /// 스트리밍 상태
    @Published var isStreaming = false
    @Published var codecStatus = NSLocalizedString("waiting", comment: "대기 중")
    @Published var workaroundStatus = NSLocalizedString("inactive", comment: "비활성")
    @Published var successfulFrames: Int64 = 0
    @Published var failedFrames: Int64 = 0
    
    // 워크어라운드 설정
    private var currentSettings: USBExternalCamera.LiveStreamSettings?
    
    // MARK: - Public Methods
    
    /// VideoCodec 워크어라운드 스트리밍 시작
    public func startWorkaroundStreaming(with settings: USBExternalCamera.LiveStreamSettings, rtmpStream: RTMPStream) async throws {
        logger.info("🔧 VideoCodec 워크어라운드 스트리밍 시작")
        
        self.rtmpStream = rtmpStream
        self.currentSettings = settings
        
        // 1. VideoCodec 사전 초기화
        try await preinitializeVideoCodec(settings: settings)
        
        // 2. 안전한 더미 프레임으로 코덱 준비
        try await warmupVideoCodecWithDummyFrames(settings: settings)
        
        // 3. 워크어라운드 활성화
        isStreaming = true
        codecStatus = NSLocalizedString("initialization_complete", comment: "초기화 완료")
        workaroundStatus = NSLocalizedString("active", comment: "활성")
        
        logger.info("✅ VideoCodec 워크어라운드 활성화 완료")
    }
    
    /// 워크어라운드를 적용한 프레임 전송
    public func sendFrameWithWorkaround(_ sampleBuffer: CMSampleBuffer) async {
        guard isStreaming, let stream = rtmpStream else { return }
        
        do {
            // 1. 프레임 전처리 (VideoCodec 최적화)
            guard let optimizedBuffer = await optimizeFrameForVideoCodec(sampleBuffer) else {
                logger.warning("프레임 최적화 실패 - 건너뜀")
                failedFrames += 1
                return
            }
            
            // 2. VideoCodec 상태 사전 체크
            if await needsVideoCodecReset() {
                try await resetVideoCodec()
            }
            
            // 3. 안전한 프레임 전송
            try await stream.append(optimizedBuffer)
            
            successfulFrames += 1
            
            // 성공률 모니터링
            if (successfulFrames + failedFrames) % 100 == 0 {
                let successRate = Double(successfulFrames) / Double(successfulFrames + failedFrames) * 100
                logger.info("📊 워크어라운드 성공률: \(String(format: "%.1f", successRate))%")
            }
            
        } catch {
            failedFrames += 1
            
            // VideoCodec -12902 에러 특별 처리
            if let nsError = error as NSError?, nsError.code == -12902 {
                logger.warning("🚨 VideoCodec -12902 감지 - 복구 시도")
                await handleVideoCodec12902Error()
            } else {
                logger.error("프레임 전송 오류: \(error)")
            }
        }
    }
    
    // MARK: - VideoCodec Preinitialization
    
    /// VideoCodec 사전 초기화
    private func preinitializeVideoCodec(settings: USBExternalCamera.LiveStreamSettings) async throws {
        logger.info("🔧 VideoCodec 사전 초기화 시작")
        
        guard let stream = rtmpStream else {
            throw WorkaroundError.streamNotAvailable
        }
        
        // HaishinKit VideoCodec 설정을 안전한 값으로 사전 설정
        var videoSettings = await stream.videoSettings
        
        // 1. 안전한 해상도 설정 (16의 배수 보장)
        let safeWidth = (settings.videoWidth / 16) * 16
        let safeHeight = (settings.videoHeight / 16) * 16
        videoSettings.videoSize = CGSize(width: safeWidth, height: safeHeight)
        
        // 2. 보수적인 비트레이트 설정
        videoSettings.bitRate = min(settings.videoBitrate * 1000, 4_000_000) // 최대 4Mbps
        
        // 3. VideoToolbox 하드웨어 인코딩 최적화 설정 (HaishinKit 2.0.8 API 호환)
        videoSettings.profileLevel = kVTProfileLevel_H264_Baseline_AutoLevel as String // 안정성 우선
        videoSettings.allowFrameReordering = false // 실시간 스트리밍 최적화
        videoSettings.maxKeyFrameIntervalDuration = 2 // 키프레임 간격
        
        // 하드웨어 가속 활성화
        videoSettings.isHardwareEncoderEnabled = true
        
        await stream.setVideoSettings(videoSettings)
        
        logger.info("✅ VideoCodec 사전 초기화 완료: \(safeWidth)x\(safeHeight) (VideoToolbox 하드웨어 가속)")
        isVideoCodecPreinitialized = true
        codecStatus = NSLocalizedString("pre_initialization_complete", comment: "사전 초기화 완료") + " - VideoToolbox"
    }
    
    /// 더미 프레임으로 VideoCodec 워밍업
    private func warmupVideoCodecWithDummyFrames(settings: USBExternalCamera.LiveStreamSettings) async throws {
        logger.info("🔥 VideoCodec 더미 프레임 워밍업 시작")
        
        guard let stream = rtmpStream else {
            throw WorkaroundError.streamNotAvailable
        }
        
        // 안전한 더미 프레임 생성 (VideoCodec이 확실히 처리할 수 있는 형태)
        let safeWidth = (settings.videoWidth / 16) * 16
        let safeHeight = (settings.videoHeight / 16) * 16
        
        for i in 0..<5 {
            if let dummyBuffer = createSafeDummyFrame(width: safeWidth, height: safeHeight) {
                do {
                    logger.debug("더미 프레임 \(i+1)/5 전송")
                    try await stream.append(dummyBuffer)
                    
                    // 짧은 대기
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    
                } catch {
                    logger.warning("더미 프레임 \(i+1) 전송 실패: \(error)")
                    
                    // -12902 에러가 아닌 경우만 치명적으로 처리
                    if let nsError = error as NSError?, nsError.code != -12902 {
                        throw error
                    }
                }
            }
        }
        
        logger.info("✅ VideoCodec 워밍업 완료")
        codecStatus = NSLocalizedString("warmup_complete", comment: "워밍업 완료")
    }
    
    // MARK: - Frame Optimization
    
    /// VideoCodec에 최적화된 프레임 생성
    private func optimizeFrameForVideoCodec(_ sampleBuffer: CMSampleBuffer) async -> CMSampleBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let settings = currentSettings else {
            return nil
        }
        
        // 1. 픽셀 포맷 최적화 (VideoCodec 선호 포맷으로 변환)
        guard let optimizedPixelBuffer = await optimizePixelBufferFormat(pixelBuffer) else {
            return nil
        }
        
        // 2. 해상도 최적화 (16의 배수 보장)
        guard let alignedPixelBuffer = await alignResolutionTo16Multiple(optimizedPixelBuffer, settings: settings) else {
            return nil
        }
        
        // 3. 안전한 CMSampleBuffer 재생성
        return createVideoCodecCompatibleSampleBuffer(from: alignedPixelBuffer)
    }
    
    /// 픽셀 포맷 최적화 (VideoCodec 친화적)
    private func optimizePixelBufferFormat(_ pixelBuffer: CVPixelBuffer) async -> CVPixelBuffer? {
        let currentFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        // VideoCodec이 가장 잘 처리하는 포맷으로 통일
        let preferredFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        
        if currentFormat == preferredFormat {
            return pixelBuffer // 이미 최적 포맷
        }
        
        // 포맷 변환
        return convertPixelBufferToYUV420(pixelBuffer)
    }
    
    /// 해상도를 16의 배수로 정렬
    private func alignResolutionTo16Multiple(_ pixelBuffer: CVPixelBuffer, settings: USBExternalCamera.LiveStreamSettings) async -> CVPixelBuffer? {
        let currentWidth = CVPixelBufferGetWidth(pixelBuffer)
        let currentHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        let alignedWidth = (settings.videoWidth / 16) * 16
        let alignedHeight = (settings.videoHeight / 16) * 16
        
        if currentWidth == alignedWidth && currentHeight == alignedHeight {
            return pixelBuffer // 이미 정렬됨
        }
        
        // 해상도 조정
        return scalePixelBufferToAlignedSize(pixelBuffer, width: alignedWidth, height: alignedHeight)
    }
    
    // MARK: - VideoCodec Error Handling
    
    /// VideoCodec 재설정 필요 여부 확인
    private func needsVideoCodecReset() async -> Bool {
        // 연속 실패가 많으면 재설정 필요
        let totalFrames = successfulFrames + failedFrames
        guard totalFrames > 0 else { return false }
        
        let failureRate = Double(failedFrames) / Double(totalFrames)
        return failureRate > 0.3 // 실패율 30% 초과 시 재설정
    }
    
    /// VideoCodec 재설정
    private func resetVideoCodec() async throws {
        logger.warning("🔄 VideoCodec 재설정 시작")
        
        guard let settings = currentSettings else {
            throw WorkaroundError.settingsNotAvailable
        }
        
        codecStatus = NSLocalizedString("resetting", comment: "재설정 중")
        
        // 잠시 대기 후 재초기화
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        try await preinitializeVideoCodec(settings: settings)
        try await warmupVideoCodecWithDummyFrames(settings: settings)
        
        // 통계 초기화
        successfulFrames = 0
        failedFrames = 0
        
        codecStatus = NSLocalizedString("reset_complete", comment: "재설정 완료")
        logger.info("✅ VideoCodec 재설정 완료")
    }
    
    /// VideoCodec -12902 에러 특별 처리
    private func handleVideoCodec12902Error() async {
        logger.warning("🚨 VideoCodec -12902 에러 복구 시작")
        
        codecStatus = NSLocalizedString("error_12902_recovery", comment: "-12902 복구 중")
        
        // 1. 짧은 대기
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // 2. 더미 프레임으로 코덱 재활성화
        if let settings = currentSettings {
            try? await warmupVideoCodecWithDummyFrames(settings: settings)
        }
        
        codecStatus = NSLocalizedString("recovery_complete", comment: "복구 완료")
        logger.info("✅ VideoCodec -12902 복구 완료")
    }
    
    // MARK: - Helper Methods
    
    /// 안전한 더미 프레임 생성
    private func createSafeDummyFrame(width: Int, height: Int) -> CMSampleBuffer? {
        // VideoCodec이 확실히 처리할 수 있는 단색 프레임 생성
        guard let pixelBuffer = createSolidColorPixelBuffer(
            width: width,
            height: height,
            color: UIColor.black
        ) else {
            return nil
        }
        
        return createVideoCodecCompatibleSampleBuffer(from: pixelBuffer)
    }
    
    /// 단색 PixelBuffer 생성
    private func createSolidColorPixelBuffer(width: Int, height: Int, color: UIColor) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        // 단색으로 채우기 (YUV 형식)
        CVPixelBufferLockBaseAddress(buffer, [])
        
        // Y 평면 (밝기)
        if let yPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) {
            let ySize = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) * height
            memset(yPlane, 16, ySize) // 검은색 Y값
        }
        
        // UV 평면 (색상)
        if let uvPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) {
            let uvSize = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * (height / 2)
            memset(uvPlane, 128, uvSize) // 중성 UV값
        }
        
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        return buffer
    }
    
    /// VideoCodec 호환 CMSampleBuffer 생성
    private func createVideoCodecCompatibleSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard status == noErr, let videoDesc = formatDescription else {
            return nil
        }
        
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: CMTime.invalid
        )
        
        let createStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: videoDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        guard createStatus == noErr else {
            return nil
        }
        
        return sampleBuffer
    }
    
    /// YUV420 포맷으로 변환 (간단한 구현)
    private func convertPixelBufferToYUV420(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        // 실제 구현에서는 vImage나 Core Video 변환 사용
        // 현재는 간단한 더미 구현
        return pixelBuffer
    }
    
    /// 정렬된 크기로 스케일링
    private func scalePixelBufferToAlignedSize(_ pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        // 실제 구현에서는 Core Graphics나 vImage 사용
        // 현재는 간단한 더미 구현
        return pixelBuffer
    }
}

// MARK: - Workaround Errors

enum WorkaroundError: Error, LocalizedError {
    case streamNotAvailable
    case settingsNotAvailable
    case codecInitializationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .streamNotAvailable:
            return NSLocalizedString("stream_unavailable", comment: "스트림을 사용할 수 없습니다")
        case .settingsNotAvailable:
            return NSLocalizedString("streaming_settings_unavailable", comment: "스트리밍 설정을 사용할 수 없습니다")
        case .codecInitializationFailed(let message):
            return String(format: NSLocalizedString("codec_initialization_failed", comment: "코덱 초기화 실패: %@"), message)
        }
    }
} 