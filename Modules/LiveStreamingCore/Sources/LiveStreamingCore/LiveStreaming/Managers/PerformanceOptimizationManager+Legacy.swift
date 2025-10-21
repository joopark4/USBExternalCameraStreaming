import Foundation
import AVFoundation
import VideoToolbox
import Metal
import CoreImage
import UIKit
import os.log
import Accelerate

extension PerformanceOptimizationManager {
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
    func configureCompressionSession(_ session: VTCompressionSession, settings: USBExternalCamera.LiveStreamSettings) throws {
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
    
}
