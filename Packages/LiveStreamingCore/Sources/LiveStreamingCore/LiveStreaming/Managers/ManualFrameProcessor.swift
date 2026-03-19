import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import QuartzCore

struct PreparedManualFrame: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer
    let preprocessTimeMs: Double
}

final class ManualFrameProcessor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "LiveStreamingCore.ManualFrameProcessor", qos: .userInitiated)
    private let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .cacheIntermediates: false,
    ])

    func prepareFrame(
        pixelBuffer: CVPixelBuffer,
        settings: LiveStreamSettings,
        presentationTime: CMTime?
    ) async -> PreparedManualFrame? {
        await withCheckedContinuation { continuation in
            queue.async { [context] in
                let startTime = CACurrentMediaTime()

                guard let outputBuffer = Self.makeOutputPixelBuffer(
                    width: settings.videoWidth,
                    height: settings.videoHeight
                ) else {
                    continuation.resume(returning: nil)
                    return
                }

                let targetSize = CGSize(width: settings.videoWidth, height: settings.videoHeight)
                let renderedImage = Self.aspectFillImage(
                    CIImage(cvPixelBuffer: pixelBuffer),
                    targetSize: targetSize
                )

                context.render(
                    renderedImage,
                    to: outputBuffer,
                    bounds: CGRect(origin: .zero, size: targetSize),
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                )

                guard
                    let formatDescription = Self.makeFormatDescription(for: outputBuffer),
                    let sampleBuffer = Self.makeSampleBuffer(
                        imageBuffer: outputBuffer,
                        formatDescription: formatDescription,
                        presentationTime: presentationTime,
                        frameRate: settings.frameRate
                    )
                else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: PreparedManualFrame(
                        sampleBuffer: sampleBuffer,
                        preprocessTimeMs: (CACurrentMediaTime() - startTime) * 1000
                    )
                )
            }
        }
    }

    private static func makeOutputPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferBytesPerRowAlignmentKey as String: 64,
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    private static func aspectFillImage(_ image: CIImage, targetSize: CGSize) -> CIImage {
        let sourceRect = image.extent
        guard sourceRect.width > 0, sourceRect.height > 0 else {
            return image.cropped(to: CGRect(origin: .zero, size: targetSize))
        }

        let scaleX = targetSize.width / sourceRect.width
        let scaleY = targetSize.height / sourceRect.height
        let scale = max(scaleX, scaleY)
        let scaledWidth = sourceRect.width * scale
        let scaledHeight = sourceRect.height * scale
        let offsetX = (targetSize.width - scaledWidth) / 2.0
        let offsetY = (targetSize.height - scaledHeight) / 2.0

        return image
            .transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
                    .translatedBy(x: offsetX / scale, y: offsetY / scale)
            )
            .cropped(to: CGRect(origin: .zero, size: targetSize))
    }

    private static func makeFormatDescription(for imageBuffer: CVImageBuffer) -> CMFormatDescription? {
        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr else { return nil }
        return formatDescription
    }

    private static func makeSampleBuffer(
        imageBuffer: CVImageBuffer,
        formatDescription: CMFormatDescription,
        presentationTime: CMTime?,
        frameRate: Int
    ) -> CMSampleBuffer? {
        let effectiveFrameRate = max(frameRate, 1)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(effectiveFrameRate)),
            presentationTimeStamp: presentationTime ?? CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr else { return nil }
        return sampleBuffer
    }
}
