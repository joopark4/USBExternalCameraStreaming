import Foundation
import AVFoundation
import VideoToolbox
import Metal
import CoreImage
import UIKit
import os.log
import Accelerate

extension PerformanceOptimizationManager {
    // MARK: - 정리
    
    func cleanup() async {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        cachedCIContext = nil
        pixelBufferPool = nil
        logger.info("🧹 PerformanceOptimizationManager 정리 완료")
    }
}
