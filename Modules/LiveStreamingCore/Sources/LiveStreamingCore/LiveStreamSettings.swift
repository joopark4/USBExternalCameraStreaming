//
//  LiveStreamSettings.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation
import SwiftData

/// 라이브 스트리밍 설정 모델
@Model
public final class LiveStreamSettingsModel: @unchecked Sendable {
    
    // MARK: - Basic Settings
    
    /// 스트림 제목
    public var streamTitle: String = "Live Stream"
    
    /// RTMP 서버 URL
    public var rtmpURL: String = "rtmp://a.rtmp.youtube.com/live2"
    
    /// 스트림 키
    public var streamKey: String = ""
    
    // MARK: - Video Settings
    
    /// 비디오 비트레이트 (kbps)
    public var videoBitrate: Int = 2500
    
    /// 비디오 너비
    public var videoWidth: Int = 1920
    
    /// 비디오 높이
    public var videoHeight: Int = 1080
    
    /// 프레임 레이트
    public var frameRate: Int = 30
    
    /// 키프레임 간격 (초)
    public var keyframeInterval: Int = 2
    
    /// 비디오 인코더
    public var videoEncoder: String = "H.264"
    
    /// 하드웨어 가속 사용 여부 (VideoToolbox)
    public var useHardwareAcceleration: Bool = true
    
    /// H.264 프로파일 레벨
    public var h264ProfileLevel: String = "High"
    
    // MARK: - Audio Settings
    
    /// 오디오 비트레이트 (kbps)
    public var audioBitrate: Int = 128
    
    /// 오디오 인코더
    public var audioEncoder: String = "AAC"
    
    // MARK: - Advanced Settings
    
    /// 자동 재연결 활성화
    public var autoReconnect: Bool = true
    
    /// 스트리밍 활성화 여부
    public var isEnabled: Bool = true
    
    /// 버퍼 크기 (MB)
    public var bufferSize: Int = 3
    
    /// 연결 타임아웃 (초)
    public var connectionTimeout: Int = 30
    
    // MARK: - SwiftData Properties
    
    /// 생성 시간
    public var createdAt: Date = Date()
    
    /// 업데이트 시간
    public var updatedAt: Date = Date()
    
    // MARK: - Initialization
    
    init() {
        // 기본값으로 초기화됨
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
    
    init(
        streamTitle: String = "Live Stream",
        rtmpURL: String = "rtmp://a.rtmp.youtube.com/live2",
        streamKey: String = "",
        videoBitrate: Int = 2500,
        videoWidth: Int = 1920,
        videoHeight: Int = 1080,
        frameRate: Int = 30,
        keyframeInterval: Int = 2,
        videoEncoder: String = "H.264",
        audioBitrate: Int = 128,
        audioEncoder: String = "AAC",
        autoReconnect: Bool = true,
        isEnabled: Bool = true,
        bufferSize: Int = 3,
        connectionTimeout: Int = 30
    ) {
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
        
        self.streamTitle = streamTitle
        self.rtmpURL = rtmpURL
        self.streamKey = streamKey
        self.videoBitrate = videoBitrate
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.frameRate = frameRate
        self.keyframeInterval = keyframeInterval
        self.videoEncoder = videoEncoder
        self.audioBitrate = audioBitrate
        self.audioEncoder = audioEncoder
        self.autoReconnect = autoReconnect
        self.isEnabled = isEnabled
        self.bufferSize = bufferSize
        self.connectionTimeout = connectionTimeout
    }
    
    // MARK: - Computed Properties
    
    /// 비디오 해상도 문자열
    public var resolutionString: String {
        return "\(videoWidth)×\(videoHeight)"
    }
    
    /// 설정 유효성 검사
    public var isValid: Bool {
        return !rtmpURL.isEmpty && 
               !streamKey.isEmpty && 
               rtmpURL.hasPrefix("rtmp://") &&
               videoBitrate > 0 &&
               audioBitrate > 0 &&
               videoWidth > 0 &&
               videoHeight > 0 &&
               frameRate > 0
    }
    
    /// 설정 요약 정보
    public var summary: String {
        return "Video: \(resolutionString)@\(frameRate)fps, \(videoBitrate)kbps | Audio: \(audioBitrate)kbps"
    }
    
    // MARK: - JSON Export/Import Methods
    
    /// JSON으로 내보내기
    public func exportToJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        let exportData = ExportData(
            streamTitle: streamTitle,
            rtmpURL: rtmpURL,
            streamKey: streamKey,
            videoBitrate: videoBitrate,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            frameRate: frameRate,
            keyframeInterval: keyframeInterval,
            videoEncoder: videoEncoder,
            audioBitrate: audioBitrate,
            audioEncoder: audioEncoder,
            autoReconnect: autoReconnect,
            isEnabled: isEnabled,
            bufferSize: bufferSize,
            connectionTimeout: connectionTimeout,
            exportedAt: Date()
        )
        
        do {
            let data = try encoder.encode(exportData)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }
    
    /// JSON에서 가져오기
    public func importFromJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let importData = try decoder.decode(ExportData.self, from: data)
            
            self.streamTitle = importData.streamTitle
            self.rtmpURL = importData.rtmpURL
            self.streamKey = importData.streamKey
            self.videoBitrate = importData.videoBitrate
            self.videoWidth = importData.videoWidth
            self.videoHeight = importData.videoHeight
            self.frameRate = importData.frameRate
            self.keyframeInterval = importData.keyframeInterval
            self.videoEncoder = importData.videoEncoder
            self.audioBitrate = importData.audioBitrate
            self.audioEncoder = importData.audioEncoder
            self.autoReconnect = importData.autoReconnect
            self.isEnabled = importData.isEnabled
            self.bufferSize = importData.bufferSize
            self.connectionTimeout = importData.connectionTimeout
            self.updatedAt = Date()
            
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Validation Methods
    
    /// RTMP URL 유효성 검사
    public func validateRTMPURL() -> ValidationResult {
        guard !rtmpURL.isEmpty else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_rtmp_url_empty", comment: "RTMP URL이 비어있습니다"))
        }
        
        guard rtmpURL.hasPrefix("rtmp://") else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_rtmp_url_invalid_prefix", comment: "RTMP URL은 rtmp://로 시작해야 합니다"))
        }
        
        guard rtmpURL.count > 10 else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_rtmp_url_invalid_format", comment: "올바르지 않은 RTMP URL 형식입니다"))
        }
        
        return ValidationResult(isValid: true, message: NSLocalizedString("validation_rtmp_url_valid", comment: "유효한 RTMP URL입니다"))
    }
    
    /// 스트림 키 유효성 검사
    public func validateStreamKey() -> ValidationResult {
        guard !streamKey.isEmpty else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_stream_key_empty", comment: "스트림 키가 비어있습니다"))
        }
        
        guard streamKey.count >= 8 else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_stream_key_too_short", comment: "스트림 키가 너무 짧습니다 (최소 8자)"))
        }
        
        return ValidationResult(isValid: true, message: NSLocalizedString("validation_stream_key_valid", comment: "유효한 스트림 키입니다"))
    }
    
    /// 비디오 설정 유효성 검사
    public func validateVideoSettings() -> ValidationResult {
        guard videoBitrate >= 500 && videoBitrate <= 50000 else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_video_bitrate_range", comment: "비디오 비트레이트는 500-50000 kbps 범위여야 합니다"))
        }
        
        guard videoWidth >= 640 && videoWidth <= 3840 else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_video_width_range", comment: "비디오 너비는 640-3840 픽셀 범위여야 합니다"))
        }
        
        guard videoHeight >= 480 && videoHeight <= 2160 else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_video_height_range", comment: "비디오 높이는 480-2160 픽셀 범위여야 합니다"))
        }
        
        guard frameRate >= 15 && frameRate <= 120 else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_frame_rate_range", comment: "프레임 레이트는 15-120 fps 범위여야 합니다"))
        }
        
        return ValidationResult(isValid: true, message: NSLocalizedString("validation_video_settings_valid", comment: "유효한 비디오 설정입니다"))
    }
    
    /// 오디오 설정 유효성 검사
    public func validateAudioSettings() -> ValidationResult {
        guard audioBitrate >= 32 && audioBitrate <= 320 else {
            return ValidationResult(isValid: false, message: NSLocalizedString("validation_audio_bitrate_range", comment: "오디오 비트레이트는 32-320 kbps 범위여야 합니다"))
        }
        
        return ValidationResult(isValid: true, message: NSLocalizedString("validation_audio_settings_valid", comment: "유효한 오디오 설정입니다"))
    }
    
    /// 전체 설정 유효성 검사
    public func validateAllSettings() -> [ValidationResult] {
        return [
            validateRTMPURL(),
            validateStreamKey(),
            validateVideoSettings(),
            validateAudioSettings()
        ]
    }
    
    // MARK: - Preset Methods
    
    /// 해상도 프리셋 적용
    public func applyResolutionPreset(_ preset: ResolutionPreset) {
        switch preset {
        case .sd480p:
            videoWidth = 848  // 16의 배수 호환성 개선
            videoHeight = 480
            frameRate = 30
            videoBitrate = 1500
        case .hd720p:
            videoWidth = 1280
            videoHeight = 720
            frameRate = 30
            videoBitrate = 2500
        case .fhd1080p:
            videoWidth = 1920
            videoHeight = 1080
            frameRate = 30
            videoBitrate = 4500
        case .uhd4k:
            videoWidth = 3840
            videoHeight = 2160
            frameRate = 30
            videoBitrate = 15000
        }
    }
    
    /// 품질 프리셋 적용
    public func applyQualityPreset(_ preset: QualityPreset) {
        switch preset {
        case .low:
            videoBitrate = 1000
            audioBitrate = 64
        case .medium:
            videoBitrate = 2500
            audioBitrate = 128
        case .high:
            videoBitrate = 5000
            audioBitrate = 192
        case .ultra:
            videoBitrate = 8000
            audioBitrate = 256
        }
    }
    
    /// 플랫폼별 최적화 설정 적용
    public func applyPlatformOptimization(_ platformName: String) {
        switch platformName.lowercased() {
        case "youtube":
            // YouTube 권장 설정
            videoBitrate = 4500
            audioBitrate = 128
            frameRate = 30
            keyframeInterval = 2
        case "twitch":
            // Twitch 권장 설정
            videoBitrate = 3500
            audioBitrate = 160
            frameRate = 30
            keyframeInterval = 2
        case "facebook":
            // Facebook 권장 설정
            videoBitrate = 4000
            audioBitrate = 128
            frameRate = 30
            keyframeInterval = 2
        default:
            // 사용자 정의 - 변경하지 않음
            break
        }
    }
    
    /// 유튜브 라이브 스트리밍 표준 프리셋 적용
    public func applyYouTubeLivePreset(_ preset: YouTubeLivePreset) {
        let settings = preset.settings
        
        videoWidth = settings.width
        videoHeight = settings.height
        frameRate = settings.frameRate
        videoBitrate = settings.videoBitrate
        audioBitrate = settings.audioBitrate
        keyframeInterval = settings.keyframeInterval
        
        // 유튜브 최적화 기본 설정
        videoEncoder = "H.264"
        audioEncoder = "AAC"
        autoReconnect = true
        connectionTimeout = 30
        bufferSize = 3
    }
    
    /// 현재 설정이 어떤 유튜브 프리셋에 가장 가까운지 검사
    public func detectYouTubePreset() -> YouTubeLivePreset? {
        for preset in YouTubeLivePreset.allCases {
            if preset == .custom { continue }
            
            let presetSettings = preset.settings
            let bitrateRange = preset.bitrateRange
            
            if videoWidth == presetSettings.width &&
               videoHeight == presetSettings.height &&
               frameRate == presetSettings.frameRate &&
               videoBitrate >= bitrateRange.min &&
               videoBitrate <= bitrateRange.max {
                return preset
            }
        }
        return .custom
    }
}

// MARK: - Supporting Types

/// 유효성 검사 결과
public struct ValidationResult {
    public let isValid: Bool
    public let message: String
}

/// 해상도 프리셋
public enum ResolutionPreset: String, CaseIterable {
    case sd480p = "480p"
    case hd720p = "720p"
    case fhd1080p = "1080p"
    case uhd4k = "4K"
    
    public var displayName: String {
        switch self {
        case .sd480p: return "480p (848×480)"
        case .hd720p: return "720p (1280×720)"
        case .fhd1080p: return "1080p (1920×1080)"
        case .uhd4k: return "4K (3840×2160)"
        }
    }
}

/// 품질 프리셋
public enum QualityPreset: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case ultra = "ultra"
    
    public var displayName: String {
        switch self {
        case .low: return NSLocalizedString("quality_preset_low", comment: "낮음")
        case .medium: return NSLocalizedString("quality_preset_medium", comment: "보통")
        case .high: return NSLocalizedString("quality_preset_high", comment: "높음")
        case .ultra: return NSLocalizedString("quality_preset_ultra", comment: "최고")
        }
    }
}

// YouTubeLivePreset enum은 StreamingModels.swift에 정의됨

// StreamingPlatform은 StreamingValidation.swift에 정의됨

// MARK: - Export/Import Data Structure

/// JSON 내보내기/가져오기용 데이터 구조체
private struct ExportData: Codable {
    let streamTitle: String
    let rtmpURL: String
    let streamKey: String
    let videoBitrate: Int
    let videoWidth: Int
    let videoHeight: Int
    let frameRate: Int
    let keyframeInterval: Int
    let videoEncoder: String
    let audioBitrate: Int
    let audioEncoder: String
    let autoReconnect: Bool
    let isEnabled: Bool
    let bufferSize: Int
    let connectionTimeout: Int
    let exportedAt: Date
} 
