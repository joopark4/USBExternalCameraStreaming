import Foundation
import AVFoundation
import VideoToolbox
import Metal
import CoreImage
import UIKit
import os.log
import Accelerate

extension PerformanceOptimizationManager {
    // MARK: - Metal GPU 최적화
    
    /// Metal 디바이스 설정
    func setupMetalDevice() {
        metalDevice = MTLCreateSystemDefaultDevice()
        if metalDevice != nil {
            logger.info("✅ Metal GPU 디바이스 설정 완료")
        } else {
            logger.warning("⚠️ Metal GPU 디바이스를 사용할 수 없음")
        }
    }
    
    /// CIContext 캐시 설정
    func setupCIContext() {
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

}
