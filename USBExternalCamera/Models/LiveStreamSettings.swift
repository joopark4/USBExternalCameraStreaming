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
final class LiveStreamSettingsModel: @unchecked Sendable {
    
    // MARK: - Basic Settings
    
    /// 스트림 제목
    var streamTitle: String = "Live Stream"
    
    /// RTMP 서버 URL
    var rtmpURL: String = ""
    
    /// 스트림 키
    var streamKey: String = ""
    
    // MARK: - Video Settings
    
    /// 비디오 비트레이트 (kbps)
    var videoBitrate: Int = 2500
    
    /// 비디오 너비
    var videoWidth: Int = 1920
    
    /// 비디오 높이
    var videoHeight: Int = 1080
    
    /// 프레임 레이트
    var frameRate: Int = 30
    
    /// 키프레임 간격 (초)
    var keyframeInterval: Int = 2
    
    /// 비디오 인코더
    var videoEncoder: String = "H.264"
    
    // MARK: - Audio Settings
    
    /// 오디오 비트레이트 (kbps)
    var audioBitrate: Int = 128
    
    /// 오디오 인코더
    var audioEncoder: String = "AAC"
    
    // MARK: - Advanced Settings
    
    /// 자동 재연결 활성화
    var autoReconnect: Bool = true
    
    /// 스트리밍 활성화 여부
    var isEnabled: Bool = true
    
    /// 버퍼 크기 (MB)
    var bufferSize: Int = 3
    
    /// 연결 타임아웃 (초)
    var connectionTimeout: Int = 30
    
    // MARK: - SwiftData Properties
    
    /// 생성 시간
    var createdAt: Date = Date()
    
    /// 업데이트 시간
    var updatedAt: Date = Date()
    
    // MARK: - Initialization
    
    init() {
        // 기본값으로 초기화됨
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
    
    init(
        streamTitle: String = "Live Stream",
        rtmpURL: String = "",
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
    var resolutionString: String {
        return "\(videoWidth)×\(videoHeight)"
    }
    
    /// 설정 유효성 검사
    var isValid: Bool {
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
    var summary: String {
        return "Video: \(resolutionString)@\(frameRate)fps, \(videoBitrate)kbps | Audio: \(audioBitrate)kbps"
    }
    
    // MARK: - JSON Export/Import Methods
    
    /// JSON으로 내보내기
    func exportToJSON() -> String {
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
    func importFromJSON(_ jsonString: String) -> Bool {
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
    func validateRTMPURL() -> ValidationResult {
        guard !rtmpURL.isEmpty else {
            return ValidationResult(isValid: false, message: "RTMP URL이 비어있습니다")
        }
        
        guard rtmpURL.hasPrefix("rtmp://") else {
            return ValidationResult(isValid: false, message: "RTMP URL은 rtmp://로 시작해야 합니다")
        }
        
        guard rtmpURL.count > 10 else {
            return ValidationResult(isValid: false, message: "올바르지 않은 RTMP URL 형식입니다")
        }
        
        return ValidationResult(isValid: true, message: "유효한 RTMP URL입니다")
    }
    
    /// 스트림 키 유효성 검사
    func validateStreamKey() -> ValidationResult {
        guard !streamKey.isEmpty else {
            return ValidationResult(isValid: false, message: "스트림 키가 비어있습니다")
        }
        
        guard streamKey.count >= 8 else {
            return ValidationResult(isValid: false, message: "스트림 키가 너무 짧습니다 (최소 8자)")
        }
        
        return ValidationResult(isValid: true, message: "유효한 스트림 키입니다")
    }
    
    /// 비디오 설정 유효성 검사
    func validateVideoSettings() -> ValidationResult {
        guard videoBitrate >= 500 && videoBitrate <= 50000 else {
            return ValidationResult(isValid: false, message: "비디오 비트레이트는 500-50000 kbps 범위여야 합니다")
        }
        
        guard videoWidth >= 640 && videoWidth <= 3840 else {
            return ValidationResult(isValid: false, message: "비디오 너비는 640-3840 픽셀 범위여야 합니다")
        }
        
        guard videoHeight >= 480 && videoHeight <= 2160 else {
            return ValidationResult(isValid: false, message: "비디오 높이는 480-2160 픽셀 범위여야 합니다")
        }
        
        guard frameRate >= 15 && frameRate <= 120 else {
            return ValidationResult(isValid: false, message: "프레임 레이트는 15-120 fps 범위여야 합니다")
        }
        
        return ValidationResult(isValid: true, message: "유효한 비디오 설정입니다")
    }
    
    /// 오디오 설정 유효성 검사
    func validateAudioSettings() -> ValidationResult {
        guard audioBitrate >= 32 && audioBitrate <= 320 else {
            return ValidationResult(isValid: false, message: "오디오 비트레이트는 32-320 kbps 범위여야 합니다")
        }
        
        return ValidationResult(isValid: true, message: "유효한 오디오 설정입니다")
    }
    
    /// 전체 설정 유효성 검사
    func validateAllSettings() -> [ValidationResult] {
        return [
            validateRTMPURL(),
            validateStreamKey(),
            validateVideoSettings(),
            validateAudioSettings()
        ]
    }
    
    // MARK: - Preset Methods
    
    /// 해상도 프리셋 적용
    func applyResolutionPreset(_ preset: ResolutionPreset) {
        switch preset {
        case .sd480p:
            videoWidth = 854
            videoHeight = 480
            frameRate = 30
            videoBitrate = 1000
        case .hd720p:
            videoWidth = 1280
            videoHeight = 720
            frameRate = 30
            videoBitrate = 2500
        case .fhd1080p:
            videoWidth = 1920
            videoHeight = 1080
            frameRate = 30
            videoBitrate = 4000
        case .uhd4k:
            videoWidth = 3840
            videoHeight = 2160
            frameRate = 30
            videoBitrate = 15000
        }
    }
    
    /// 품질 프리셋 적용
    func applyQualityPreset(_ preset: QualityPreset) {
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
    func applyPlatformOptimization(_ platformName: String) {
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
}

// MARK: - Supporting Types

/// 유효성 검사 결과
struct ValidationResult {
    let isValid: Bool
    let message: String
}

/// 해상도 프리셋
enum ResolutionPreset: String, CaseIterable {
    case sd480p = "480p"
    case hd720p = "720p"
    case fhd1080p = "1080p"
    case uhd4k = "4K"
    
    var displayName: String {
        switch self {
        case .sd480p: return "480p (854×480)"
        case .hd720p: return "720p (1280×720)"
        case .fhd1080p: return "1080p (1920×1080)"
        case .uhd4k: return "4K (3840×2160)"
        }
    }
}

/// 품질 프리셋
enum QualityPreset: String, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case ultra = "ultra"
    
    var displayName: String {
        switch self {
        case .low: return "낮음"
        case .medium: return "보통"
        case .high: return "높음"
        case .ultra: return "최고"
        }
    }
}

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