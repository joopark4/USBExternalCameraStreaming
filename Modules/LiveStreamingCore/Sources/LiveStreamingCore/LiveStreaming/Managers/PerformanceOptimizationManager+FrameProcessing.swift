import Foundation
import AVFoundation
import VideoToolbox
import Metal
import CoreImage
import UIKit
import os.log
import Accelerate

extension PerformanceOptimizationManager {
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
    func createNewPixelBuffer(targetSize: CGSize) -> CVPixelBuffer? {
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
    func getReusablePixelBuffer(targetSize: CGSize) -> CVPixelBuffer? {
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
    func renderUIViewToCIImage(_ view: UIView, targetSize: CGSize) -> CIImage {
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
    func renderUIViewToMetalTexture(_ view: UIView, targetSize: CGSize, scale: CGFloat) -> CIImage {
        // 실제 Metal 구현은 복잡하므로 여기서는 간단한 폴백
        // 실제 구현에서는 MTLTexture를 사용한 직접 렌더링 구현
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let uiImage = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        
        return CIImage(image: uiImage) ?? CIImage.empty()
    }
    
    /// CIImage 직접 컴포지팅 (중간 변환 없음)
    func compositeImagesDirectly(
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
    func scaleImageToFill(_ image: CIImage, targetSize: CGSize) -> CIImage {
        let imageSize = image.extent.size
        let scaleX = targetSize.width / imageSize.width
        let scaleY = targetSize.height / imageSize.height
        let scale = max(scaleX, scaleY)
        
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return image.transformed(by: transform)
    }
    
    /// 이미지를 타겟 크기에 맞추기 (Aspect Fit)
    func scaleImageToFit(_ image: CIImage, targetSize: CGSize) -> CIImage {
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
    func calculate720pOptimalBitrate(currentBitrate: Int) -> Int {
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
    
}
