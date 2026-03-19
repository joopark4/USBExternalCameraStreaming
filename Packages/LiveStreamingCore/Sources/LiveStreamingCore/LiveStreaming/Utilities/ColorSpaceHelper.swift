//
//  ColorSpaceHelper.swift
//  LiveStreamingCore
//
//  Created by Claude on 2025.
//

import CoreImage
import Foundation

/// ColorSpace 관련 안전한 헬퍼 유틸리티
public enum ColorSpaceHelper {

    /// 안전한 sRGB ColorSpace 반환
    /// - Returns: sRGB CGColorSpace, 실패 시 device RGB 반환
    public static func sRGBColorSpace() -> CGColorSpace {
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            return colorSpace
        } else {
            // Fallback to device RGB if sRGB is not available (매우 드문 경우)
            logWarning("ColorSpaceHelper: sRGB color space not available, using device RGB", category: .streaming)
            return CGColorSpaceCreateDeviceRGB()
        }
    }

    /// 안전한 Display P3 ColorSpace 반환
    /// - Returns: Display P3 CGColorSpace, 실패 시 sRGB 반환
    public static func displayP3ColorSpace() -> CGColorSpace {
        if let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) {
            return colorSpace
        } else {
            logWarning("ColorSpaceHelper: Display P3 color space not available, using sRGB", category: .streaming)
            return sRGBColorSpace()
        }
    }

    /// CIContext 생성용 옵션 제공 (안전한 ColorSpace 포함)
    /// - Parameters:
    ///   - useGPU: GPU 사용 여부 (기본값: true)
    ///   - cacheIntermediates: 중간 결과 캐싱 여부 (기본값: false)
    /// - Returns: CIContext 생성 옵션 딕셔너리
    public static func ciContextOptions(
        useGPU: Bool = true,
        cacheIntermediates: Bool = false
    ) -> [CIContextOption: Any] {
        return [
            .workingColorSpace: sRGBColorSpace(),
            .outputColorSpace: sRGBColorSpace(),
            .useSoftwareRenderer: !useGPU,
            .priorityRequestLow: false,
            .cacheIntermediates: cacheIntermediates
        ]
    }
}