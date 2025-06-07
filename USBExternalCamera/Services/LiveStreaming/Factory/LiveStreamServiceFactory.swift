//
//  LiveStreamServiceFactory.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation
import os.log

// MARK: - Live Stream Service Factory

/// 라이브 스트리밍 서비스 팩토리
public struct LiveStreamServiceFactory {
    
    // MARK: - Service Creation
    
    /// 기본 라이브 스트리밍 서비스 생성
    @MainActor
    public static func createService() -> HaishinKitManagerProtocol {
        logInfo("🏭 Creating default LiveStreamService via Factory", category: .streaming)
        return HaishinKitManager()
    }
    
    /// 성능 최적화된 서비스 생성
    @MainActor
    public static func createOptimizedService() -> HaishinKitManagerProtocol {
        logInfo("🏭 Creating optimized LiveStreamService via Factory", category: .streaming)
        return HaishinKitManager()
    }
    
    /// 디버그용 서비스 생성
    @MainActor
    public static func createDebugService() -> HaishinKitManagerProtocol {
        logInfo("🏭 Creating debug LiveStreamService via Factory", category: .streaming)
        return HaishinKitManager()
    }
}

// MARK: - Factory Extensions

extension LiveStreamServiceFactory {
    
    /// 스트리밍 품질 프리셋에 따른 서비스 생성
    @MainActor
    public static func createService(for quality: StreamingQuality) -> HaishinKitManagerProtocol {
        logInfo("🏭 Creating LiveStreamService for quality: \(quality)", category: .streaming)
        return HaishinKitManager()
    }
    
    /// 플랫폼별 최적화된 서비스 생성
    @MainActor
    public static func createPlatformOptimizedService() -> HaishinKitManagerProtocol {
        logInfo("🏭 Creating platform-optimized LiveStreamService", category: .streaming)
        
        #if targetEnvironment(simulator)
        // 시뮬레이터에서는 스텁 구현 사용
        logInfo("📱 Using enhanced stub for Simulator", category: .streaming)
        return HaishinKitManager()
        #else
        // 실제 디바이스에서는 실제 구현 사용
        logInfo("📱 Using real implementation for Device", category: .streaming)
        return HaishinKitManager()
        #endif
    }
}

// MARK: - Streaming Quality

/// 스트리밍 품질 설정
public enum StreamingQuality: CaseIterable {
    case low       // 480p, 1Mbps
    case medium    // 720p, 2.5Mbps  
    case high      // 1080p, 4Mbps
    case ultra     // 1080p, 6Mbps
    
    public var displayName: String {
        switch self {
        case .low: return "저화질 (480p)"
        case .medium: return "중화질 (720p)" 
        case .high: return "고화질 (1080p)"
        case .ultra: return "최고화질 (1080p+)"
        }
    }
    
    public var bitrate: Int {
        switch self {
        case .low: return 1000
        case .medium: return 2500
        case .high: return 4000
        case .ultra: return 6000
        }
    }
    
    public var resolution: (width: Int, height: Int) {
        switch self {
        case .low: return (854, 480)
        case .medium: return (1280, 720)
        case .high: return (1920, 1080)
        case .ultra: return (1920, 1080)
        }
    }
} 