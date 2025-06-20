//
//  CameraExtensions.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation
import UIKit

// MARK: - String Extension for Regex

extension String {
  func matches(for regex: String) -> [String] {
    do {
      let regex = try NSRegularExpression(pattern: regex)
      let results = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
      return results.map {
        String(self[Range($0.range, in: self)!])
      }
    } catch {
      return []
    }
  }
}

// MARK: - Extensions

/// CVPixelBuffer를 UIImage로 변환하는 확장
///
/// **용도:**
/// - 실시간 카메라 프레임(CVPixelBuffer)을 UI 합성이 가능한 UIImage로 변환
/// - AVCaptureVideoDataOutput에서 받은 프레임을 화면 캡처 시 사용
///
/// **변환 과정:**
/// 1. CVPixelBuffer → CIImage 변환
/// 2. CIImage → CGImage 변환 (Core Graphics 호환)
/// 3. CGImage → UIImage 변환 (UIKit 호환)
extension CVPixelBuffer {

  /// CVPixelBuffer를 UIImage로 변환
  ///
  /// Core Image 프레임워크를 사용하여 픽셀 버퍼를 이미지로 변환합니다.
  /// 이 과정은 GPU 가속을 활용하여 효율적으로 수행됩니다.
  ///
  /// **성능 고려사항:**
  /// - CIContext는 GPU 리소스를 사용하므로 재사용 권장
  /// - 현재는 매번 새로 생성하지만, 향후 캐싱 최적화 가능
  ///
  /// - Returns: 변환된 UIImage 또는 변환 실패 시 nil
  func toUIImage() -> UIImage? {
    // Step 1: CVPixelBuffer를 CIImage로 변환
    // Core Image가 픽셀 버퍼를 직접 처리할 수 있는 형태로 변환
    let ciImage = CIImage(cvPixelBuffer: self)

    // Step 2: CIContext 생성 (GPU 가속 활용)
    // Note: 현재는 매번 생성하지만, 향후 성능 최적화를 위해 전역 CIContext 캐싱 고려 가능
    let context = CIContext()

    // Step 3: CIImage를 CGImage로 변환
    // extent: 이미지의 전체 영역을 의미 (원본 크기 유지)
    guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
      print("❌ [CVPixelBuffer] CIImage → CGImage 변환 실패")
      return nil
    }

    // Step 4: CGImage를 UIImage로 변환 (UIKit 호환)
    // 최종적으로 UIKit에서 사용 가능한 형태로 변환 완료
    return UIImage(cgImage: cgImage)
  }
}

/// UIImage를 CVPixelBuffer로 변환하는 확장
extension UIImage {
  func toCVPixelBuffer() -> CVPixelBuffer? {
    let attrs =
      [
        kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
        kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any,
        kCVPixelBufferIOSurfacePropertiesKey: [:],
      ] as CFDictionary

    var pixelBuffer: CVPixelBuffer?

    // BGRA 포맷 사용 (HaishinKit과 호환성 향상)
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
      kCVPixelFormatType_32BGRA,
      attrs,
      &pixelBuffer
    )

    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      print("❌ [CVPixelBuffer] 생성 실패: \(status)")
      return nil
    }

    CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
    defer {
      CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
    }

    let pixelData = CVPixelBufferGetBaseAddress(buffer)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

    // BGRA 포맷에 맞는 컨텍스트 생성
    guard
      let context = CGContext(
        data: pixelData,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: rgbColorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else {
      print("❌ [CVPixelBuffer] CGContext 생성 실패")
      return nil
    }

    // 이미지 그리기 (Y축 뒤집기)
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1.0, y: -1.0)

    UIGraphicsPushContext(context)
    draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    UIGraphicsPopContext()

    print("✅ [CVPixelBuffer] 생성 성공: \(Int(size.width))x\(Int(size.height)) BGRA")
    return buffer
  }
}
