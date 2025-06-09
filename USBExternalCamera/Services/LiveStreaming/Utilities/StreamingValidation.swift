//
//  StreamingValidation.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation
import os.log

// MARK: - Streaming Validation

/// 스트리밍 설정 유효성 검사 유틸리티
public final class StreamingValidation {
    
    /// 스트리밍 에러 타입
    public enum ValidationError: LocalizedError {
        case alreadyStreaming
        case invalidSettings(String)
        case connectionFailed(String)
        case streamingFailed(String)
        
        public var errorDescription: String? {
            switch self {
            case .alreadyStreaming:
                return "이미 스트리밍이 진행 중입니다"
            case .invalidSettings(let message):
                return "설정 오류: \(message)"
            case .connectionFailed(let message):
                return String(format: NSLocalizedString("connection_failed_detailed", comment: "연결 실패: %@"), message)
            case .streamingFailed(let message):
                return "스트리밍 실패: \(message)"
            }
        }
    }
    
    // MARK: - Settings Validation
    
    /// 라이브 스트리밍 설정 유효성 검사
    /// - Parameter settings: 검사할 설정
    /// - Throws: 유효성 검사 실패 시 ValidationError
    internal static func validateSettings(_ settings: USBExternalCamera.LiveStreamSettings) throws {
        // RTMP URL 검사
        try validateRTMPURL(settings.rtmpURL)
        
        // 스트림 키 검사
        try validateStreamKey(settings.streamKey, rtmpURL: settings.rtmpURL)
        
        // 비트레이트 검사
        try validateBitrates(videoBitrate: settings.videoBitrate, audioBitrate: settings.audioBitrate)
        
        // 해상도 검사
        try validateResolution(width: settings.videoWidth, height: settings.videoHeight)
        
        // 프레임률 검사
        try validateFrameRate(settings.frameRate)
        
        logDebug("✅ Settings validation passed", category: .streaming)
    }
    
    /// RTMP URL 유효성 검사
    /// - Parameter rtmpURL: 검사할 RTMP URL
    /// - Throws: 유효하지 않은 URL일 경우 ValidationError
    public static func validateRTMPURL(_ rtmpURL: String) throws {
        guard !rtmpURL.isEmpty else {
            throw ValidationError.invalidSettings("RTMP URL이 설정되지 않았습니다")
        }
        
        guard rtmpURL.hasPrefix("rtmp://") || rtmpURL.hasPrefix("rtmps://") else {
            throw ValidationError.invalidSettings("유효하지 않은 RTMP URL 형식입니다")
        }
        
        // URL 파싱 가능 여부 확인
        guard URL(string: rtmpURL) != nil else {
            throw ValidationError.invalidSettings("RTMP URL을 파싱할 수 없습니다")
        }
        
        logDebug("✅ RTMP URL validation passed: \(rtmpURL)", category: .streaming)
    }
    
    /// 스트림 키 유효성 검사
    /// - Parameters:
    ///   - streamKey: 검사할 스트림 키
    ///   - rtmpURL: 연관된 RTMP URL (플랫폼별 검증용)
    /// - Throws: 유효하지 않은 스트림 키일 경우 ValidationError
    public static func validateStreamKey(_ streamKey: String, rtmpURL: String) throws {
        guard !streamKey.isEmpty else {
            throw ValidationError.invalidSettings("스트림 키가 설정되지 않았습니다")
        }
        
        // YouTube 스트림 키 특별 검증
        if rtmpURL.contains("youtube.com") {
            try validateYouTubeStreamKey(streamKey)
        }
        
        // Twitch 스트림 키 특별 검증
        if rtmpURL.contains("twitch.tv") {
            try validateTwitchStreamKey(streamKey)
        }
        
        logDebug("✅ Stream key validation passed", category: .streaming)
    }
    
    /// YouTube 스트림 키 특별 검증
    private static func validateYouTubeStreamKey(_ streamKey: String) throws {
        logInfo("📋 YouTube Live 진단 정보:", category: .streaming)
        logInfo("   🔑 스트림 키: \(String(streamKey.prefix(8)))***", category: .streaming)
        logInfo("", category: .streaming)
        logInfo("📋 YouTube Live 체크리스트:", category: .streaming)
        logInfo("   1. YouTube Studio > 라이브 스트리밍 > '스트림' 탭에서 스트림 키 확인", category: .streaming)
        logInfo("   2. 채널에서 라이브 스트리밍 기능이 활성화되어 있는지 확인", category: .streaming)
        logInfo("   3. 스트림 키가 최신이고 만료되지 않았는지 확인", category: .streaming)
        logInfo("   4. 네트워크가 RTMP 포트(1935)를 차단하지 않는지 확인", category: .streaming)
        logInfo("", category: .streaming)
        
        // 스트림 키 형식 검사 (더 유연하게)
        if streamKey.count < 16 {
            logWarning("⚠️ 스트림 키가 너무 짧습니다 (\(streamKey.count)자)", category: .streaming)
            logWarning("⚠️ YouTube 스트림 키는 일반적으로 20자 이상입니다", category: .streaming)
        }
        
        if !streamKey.contains("-") {
            logWarning("⚠️ 스트림 키 형식이 일반적이지 않습니다", category: .streaming)
            logWarning("⚠️ YouTube 스트림 키는 보통 '-'로 구분된 형식입니다", category: .streaming)
        }
    }
    
    /// Twitch 스트림 키 검증
    private static func validateTwitchStreamKey(_ streamKey: String) throws {
        // Twitch 스트림 키는 보통 live_로 시작
        if !streamKey.hasPrefix("live_") && streamKey.count < 20 {
            logWarning("⚠️ Twitch 스트림 키 형식이 일반적이지 않습니다", category: .streaming)
        }
    }
    
    /// 비트레이트 유효성 검사
    /// - Parameters:
    ///   - videoBitrate: 비디오 비트레이트 (kbps)
    ///   - audioBitrate: 오디오 비트레이트 (kbps)
    /// - Throws: 유효하지 않은 비트레이트일 경우 ValidationError
    public static func validateBitrates(videoBitrate: Int, audioBitrate: Int) throws {
        guard videoBitrate > 0 && audioBitrate > 0 else {
            throw ValidationError.invalidSettings("비트레이트는 0보다 커야 합니다")
        }
        
        // 비디오 비트레이트 범위 검사
        let videoRange = 100...50000 // 100kbps ~ 50Mbps
        guard videoRange.contains(videoBitrate) else {
            throw ValidationError.invalidSettings("비디오 비트레이트는 \(videoRange.lowerBound)-\(videoRange.upperBound) kbps 범위여야 합니다")
        }
        
        // 오디오 비트레이트 범위 검사
        let audioRange = 32...320 // 32kbps ~ 320kbps
        guard audioRange.contains(audioBitrate) else {
            throw ValidationError.invalidSettings("오디오 비트레이트는 \(audioRange.lowerBound)-\(audioRange.upperBound) kbps 범위여야 합니다")
        }
        
        logDebug("✅ Bitrate validation passed: Video \(videoBitrate)kbps, Audio \(audioBitrate)kbps", category: .streaming)
    }
    
    /// 해상도 유효성 검사
    /// - Parameters:
    ///   - width: 비디오 너비
    ///   - height: 비디오 높이
    /// - Throws: 유효하지 않은 해상도일 경우 ValidationError
    public static func validateResolution(width: Int, height: Int) throws {
        guard width > 0 && height > 0 else {
            throw ValidationError.invalidSettings("해상도는 0보다 커야 합니다")
        }
        
        // 최소 해상도 검사
        let minWidth = 320
        let minHeight = 240
        guard width >= minWidth && height >= minHeight else {
            throw ValidationError.invalidSettings("최소 해상도는 \(minWidth)x\(minHeight)입니다")
        }
        
        // 최대 해상도 검사
        let maxWidth = 7680 // 8K
        let maxHeight = 4320
        guard width <= maxWidth && height <= maxHeight else {
            throw ValidationError.invalidSettings("최대 해상도는 \(maxWidth)x\(maxHeight)입니다")
        }
        
        // 일반적인 종횡비 검사 (경고만)
        let aspectRatio = Double(width) / Double(height)
        let commonRatios = [16.0/9.0, 4.0/3.0, 21.0/9.0] // 16:9, 4:3, 21:9
        let tolerance = 0.1
        
        let isCommonRatio = commonRatios.contains { abs(aspectRatio - $0) < tolerance }
        if !isCommonRatio {
            logWarning("⚠️ 일반적이지 않은 종횡비입니다: \(String(format: "%.2f", aspectRatio))", category: .streaming)
            logWarning("⚠️ 권장 비율: 16:9 (1.78), 4:3 (1.33), 21:9 (2.33)", category: .streaming)
        }
        
        logDebug("✅ Resolution validation passed: \(width)x\(height)", category: .streaming)
    }
    
    /// 프레임률 유효성 검사
    /// - Parameter frameRate: 프레임률 (fps)
    /// - Throws: 유효하지 않은 프레임률일 경우 ValidationError
    public static func validateFrameRate(_ frameRate: Int) throws {
        guard frameRate > 0 else {
            throw ValidationError.invalidSettings("프레임률은 0보다 커야 합니다")
        }
        
        // 프레임률 범위 검사
        let frameRateRange = 1...120
        guard frameRateRange.contains(frameRate) else {
            throw ValidationError.invalidSettings("프레임률은 \(frameRateRange.lowerBound)-\(frameRateRange.upperBound) fps 범위여야 합니다")
        }
        
        // 일반적인 프레임률 검사 (경고만)
        let commonFrameRates = [24, 25, 30, 50, 60, 120]
        if !commonFrameRates.contains(frameRate) {
            logWarning("⚠️ 일반적이지 않은 프레임률입니다: \(frameRate)fps", category: .streaming)
            logWarning("⚠️ 권장 프레임률: \(commonFrameRates.map(String.init).joined(separator: ", "))fps", category: .streaming)
        }
        
        logDebug("✅ Frame rate validation passed: \(frameRate)fps", category: .streaming)
    }
    
    // MARK: - Platform Specific Validation
    
    /// 플랫폼별 설정 검증
    /// - Parameters:
    ///   - settings: 스트리밍 설정
    ///   - platform: 플랫폼 타입
    /// - Returns: 플랫폼별 검증 결과 및 권장사항
    internal static func validateForPlatform(_ settings: USBExternalCamera.LiveStreamSettings, platform: StreamingPlatform) -> PlatformValidationResult {
        switch platform {
        case .youtube:
            return validateForYouTube(settings)
        case .twitch:
            return validateForTwitch(settings)
        case .facebook:
            return validateForFacebook(settings)
        case .custom:
            return validateForCustom(settings)
        }
    }
    
    private static func validateForYouTube(_ settings: USBExternalCamera.LiveStreamSettings) -> PlatformValidationResult {
        var warnings: [String] = []
        var recommendations: [String] = []
        
        // YouTube 권장 설정 검사
        let maxBitrate = 51000 // 51 Mbps
        if settings.videoBitrate > maxBitrate {
            warnings.append("YouTube 최대 비트레이트(\(maxBitrate)kbps)를 초과합니다")
            recommendations.append("비트레이트를 \(maxBitrate)kbps 이하로 설정하세요")
        }
        
        // 해상도별 권장 비트레이트
        let (recommendedMin, recommendedMax) = getYouTubeRecommendedBitrate(width: settings.videoWidth, height: settings.videoHeight, frameRate: settings.frameRate)
        
        if settings.videoBitrate < recommendedMin {
            recommendations.append("이 해상도(\(settings.videoWidth)x\(settings.videoHeight))에는 최소 \(recommendedMin)kbps를 권장합니다")
        } else if settings.videoBitrate > recommendedMax {
            recommendations.append("이 해상도(\(settings.videoWidth)x\(settings.videoHeight))에는 최대 \(recommendedMax)kbps를 권장합니다")
        }
        
        return PlatformValidationResult(
            isValid: warnings.isEmpty,
            warnings: warnings,
            recommendations: recommendations,
            platform: .youtube
        )
    }
    
    private static func validateForTwitch(_ settings: USBExternalCamera.LiveStreamSettings) -> PlatformValidationResult {
        var warnings: [String] = []
        var recommendations: [String] = []
        
        // Twitch 제한사항
        let maxBitrate = 6000 // 6 Mbps
        if settings.videoBitrate > maxBitrate {
            warnings.append("Twitch 최대 비트레이트(\(maxBitrate)kbps)를 초과합니다")
            recommendations.append("비트레이트를 \(maxBitrate)kbps 이하로 설정하세요")
        }
        
        // 해상도 제한
        if settings.videoWidth > 1920 || settings.videoHeight > 1080 {
            warnings.append("Twitch는 1080p를 초과하는 해상도를 권장하지 않습니다")
            recommendations.append("1920x1080 이하의 해상도를 사용하세요")
        }
        
        return PlatformValidationResult(
            isValid: warnings.isEmpty,
            warnings: warnings,
            recommendations: recommendations,
            platform: .twitch
        )
    }
    
    private static func validateForFacebook(_ settings: USBExternalCamera.LiveStreamSettings) -> PlatformValidationResult {
        var warnings: [String] = []
        var recommendations: [String] = []
        
        // Facebook Live 제한사항
        let maxBitrate = 4000 // 4 Mbps
        if settings.videoBitrate > maxBitrate {
            warnings.append("Facebook Live 권장 최대 비트레이트(\(maxBitrate)kbps)를 초과합니다")
            recommendations.append("안정적인 스트리밍을 위해 \(maxBitrate)kbps 이하로 설정하세요")
        }
        
        return PlatformValidationResult(
            isValid: warnings.isEmpty,
            warnings: warnings,
            recommendations: recommendations,
            platform: .facebook
        )
    }
    
    private static func validateForCustom(_ settings: USBExternalCamera.LiveStreamSettings) -> PlatformValidationResult {
        return PlatformValidationResult(
            isValid: true,
            warnings: [],
            recommendations: ["커스텀 RTMP 서버의 제한사항을 확인하세요"],
            platform: .custom
        )
    }
    
    // MARK: - Helper Methods
    
    /// YouTube 해상도별 권장 비트레이트 반환
    private static func getYouTubeRecommendedBitrate(width: Int, height: Int, frameRate: Int) -> (min: Int, max: Int) {
        let is60fps = frameRate >= 50
        
        if width >= 3840 && height >= 2160 { // 4K
            return is60fps ? (20000, 51000) : (13000, 34000)
        } else if width >= 2560 && height >= 1440 { // 1440p
            return is60fps ? (9000, 18000) : (6000, 13000)
        } else if width >= 1920 && height >= 1080 { // 1080p
            return is60fps ? (4500, 9000) : (3000, 6000)
        } else if width >= 1280 && height >= 720 { // 720p
            return is60fps ? (2250, 6000) : (1500, 4000)
        } else { // 480p 이하
            return (500, 2000)
        }
    }
}

// MARK: - Supporting Types

/// 스트리밍 플랫폼 타입
internal enum StreamingPlatform {
    case youtube
    case twitch
    case facebook
    case custom
    
    var displayName: String {
        switch self {
        case .youtube: return "YouTube"
        case .twitch: return "Twitch"
        case .facebook: return "Facebook"
        case .custom: return "Custom"
        }
    }
}

/// 플랫폼별 검증 결과
internal struct PlatformValidationResult {
    let isValid: Bool
    let warnings: [String]
    let recommendations: [String]
    let platform: StreamingPlatform
    
    init(isValid: Bool, warnings: [String], recommendations: [String], platform: StreamingPlatform) {
        self.isValid = isValid
        self.warnings = warnings
        self.recommendations = recommendations
        self.platform = platform
    }
} 