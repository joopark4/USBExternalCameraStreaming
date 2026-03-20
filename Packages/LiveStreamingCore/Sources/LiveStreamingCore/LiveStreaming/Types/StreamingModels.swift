//
//  StreamingModels.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import CoreGraphics
import Foundation

// MARK: - YouTube Live Preset Enum

/// 유튜브 라이브 스트리밍 표준 프리셋
public enum YouTubeLivePreset: String, CaseIterable, Identifiable {
    case sd480p = "youtube_480p"
    case hd720p = "youtube_720p"
    case fhd1080p = "youtube_1080p"
    case custom = "custom"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .sd480p: return NSLocalizedString("youtube_preset_480p", comment: "YouTube 480p (SD)")
        case .hd720p: return NSLocalizedString("youtube_preset_720p", comment: "YouTube 720p (HD)")
        case .fhd1080p: return NSLocalizedString("youtube_preset_1080p", comment: "YouTube 1080p (Full HD)")
        case .custom: return NSLocalizedString("custom_user_defined", comment: "사용자 정의")
        }
    }
    
    public var description: String {
        switch self {
        case .sd480p: return "848×480 • 30fps • 1,500 kbps (1,000-2,000)"
        case .hd720p: return "1280×720 • 30fps • 2,500 kbps (2,500-5,000)"
        case .fhd1080p: return "1920×1080 • 30fps • 4,500 kbps (4,500-9,000)"
        case .custom: return NSLocalizedString("user_custom_settings", comment: "사용자가 직접 설정")
        }
    }
    
    public var icon: String {
        switch self {
        case .sd480p: return "video.circle"
        case .hd720p: return "video.circle.fill"
        case .fhd1080p: return "4k.tv"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var resolutionClass: StreamResolutionClass {
        switch self {
        case .sd480p: return .p480
        case .hd720p: return .p720
        case .fhd1080p: return .p1080
        case .custom: return .custom
        }
    }
    
    /// 유튜브 표준 설정값 반환
    public var settings: (width: Int, height: Int, frameRate: Int, videoBitrate: Int, audioBitrate: Int, keyframeInterval: Int) {
        settings(for: .landscape)
    }

    public func settings(for orientation: StreamOrientation) -> (width: Int, height: Int, frameRate: Int, videoBitrate: Int, audioBitrate: Int, keyframeInterval: Int) {
        let size = StreamResolutionDescriptor.presetSize(for: resolutionClass, orientation: orientation)
        switch self {
        case .sd480p:
            return (size?.width ?? 848, size?.height ?? 480, 30, 1500, 128, 2)
        case .hd720p:
            return (size?.width ?? 1280, size?.height ?? 720, 30, 2500, 128, 2)
        case .fhd1080p:
            return (size?.width ?? 1920, size?.height ?? 1080, 30, 4500, 128, 2)
        case .custom:
            return (1920, 1080, 30, 4500, 128, 2)
        }
    }
    
    /// 유튜브 표준 비트레이트 범위
    public var bitrateRange: (min: Int, max: Int) {
        switch self {
        case .sd480p: return (1000, 2000)
        case .hd720p: return (2500, 5000)
        case .fhd1080p: return (4500, 9000)
        case .custom: return (500, 15000)
        }
    }
}

// MARK: - LiveStreamingCore Namespace

public enum LiveStreamingCoreNamespace {
    
    // MARK: - Live Stream Settings
    
    /// 라이브 스트리밍 설정
    public struct LiveStreamSettings: Codable, Sendable {
        enum CodingKeys: String, CodingKey {
            case streamTitle
            case rtmpURL
            case streamKey
            case videoBitrate
            case audioBitrate
            case videoWidth
            case videoHeight
            case streamOrientation
            case frameRate
            case autoReconnect
            case isEnabled
            case videoEncoder
            case audioEncoder
            case useHardwareAcceleration
            case h264ProfileLevel
            case bufferSize
            case connectionTimeout
        }

        /// 스트림 제목
        public var streamTitle: String
        
        /// RTMP URL
        public var rtmpURL: String
        
        /// 스트림 키
        public var streamKey: String
        
        /// 비디오 비트레이트 (kbps)
        public var videoBitrate: Int
        
        /// 오디오 비트레이트 (kbps)
        public var audioBitrate: Int
        
        /// 비디오 너비
        public var videoWidth: Int
        
        /// 비디오 높이
        public var videoHeight: Int

        /// 송출 방향
        public var streamOrientation: StreamOrientation
        
        /// 프레임 레이트
        public var frameRate: Int
        
        /// 자동 재연결
        public var autoReconnect: Bool
        
        /// 스트리밍 활성화
        public var isEnabled: Bool
        
        /// 비디오 인코더
        public var videoEncoder: String
        
        /// 오디오 인코더
        public var audioEncoder: String
        
        /// 하드웨어 가속 사용 여부 (VideoToolbox)
        public var useHardwareAcceleration: Bool
        
        /// H.264 프로파일 레벨
        public var h264ProfileLevel: String
        
        /// 버퍼 크기 (MB)
        public var bufferSize: Int
        
        /// 연결 타임아웃 (초)
        public var connectionTimeout: Int
        
        /// 기본 초기화
        public init() {
            self.streamTitle = ""
            self.rtmpURL = "rtmp://a.rtmp.youtube.com/live2"  // YouTube Live 기본 RTMP URL
            self.streamKey = ""
            self.videoBitrate = 4500  // YouTube Live 1080p 권장값
            self.audioBitrate = 128
            self.videoWidth = 1920
            self.videoHeight = 1080
            self.streamOrientation = .landscape
            self.frameRate = 30
            self.autoReconnect = true
            self.isEnabled = true
            self.videoEncoder = "H.264"
            self.audioEncoder = "AAC"
            self.useHardwareAcceleration = true
            self.h264ProfileLevel = "High"
            self.bufferSize = 3
            self.connectionTimeout = 30
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.streamTitle = try container.decodeIfPresent(String.self, forKey: .streamTitle) ?? ""
            self.rtmpURL = try container.decodeIfPresent(String.self, forKey: .rtmpURL) ?? "rtmp://a.rtmp.youtube.com/live2"
            self.streamKey = try container.decodeIfPresent(String.self, forKey: .streamKey) ?? ""
            self.videoBitrate = try container.decodeIfPresent(Int.self, forKey: .videoBitrate) ?? 4500
            self.audioBitrate = try container.decodeIfPresent(Int.self, forKey: .audioBitrate) ?? 128
            self.videoWidth = try container.decodeIfPresent(Int.self, forKey: .videoWidth) ?? 1920
            self.videoHeight = try container.decodeIfPresent(Int.self, forKey: .videoHeight) ?? 1080
            self.streamOrientation = try container.decodeIfPresent(StreamOrientation.self, forKey: .streamOrientation)
                ?? (self.videoHeight > self.videoWidth ? .portrait : .landscape)
            self.frameRate = try container.decodeIfPresent(Int.self, forKey: .frameRate) ?? 30
            self.autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
            self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
            self.videoEncoder = try container.decodeIfPresent(String.self, forKey: .videoEncoder) ?? "H.264"
            self.audioEncoder = try container.decodeIfPresent(String.self, forKey: .audioEncoder) ?? "AAC"
            self.useHardwareAcceleration = try container.decodeIfPresent(Bool.self, forKey: .useHardwareAcceleration) ?? true
            self.h264ProfileLevel = try container.decodeIfPresent(String.self, forKey: .h264ProfileLevel) ?? "High"
            self.bufferSize = try container.decodeIfPresent(Int.self, forKey: .bufferSize) ?? 3
            self.connectionTimeout = try container.decodeIfPresent(Int.self, forKey: .connectionTimeout) ?? 30
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(streamTitle, forKey: .streamTitle)
            try container.encode(rtmpURL, forKey: .rtmpURL)
            try container.encode(streamKey, forKey: .streamKey)
            try container.encode(videoBitrate, forKey: .videoBitrate)
            try container.encode(audioBitrate, forKey: .audioBitrate)
            try container.encode(videoWidth, forKey: .videoWidth)
            try container.encode(videoHeight, forKey: .videoHeight)
            try container.encode(streamOrientation, forKey: .streamOrientation)
            try container.encode(frameRate, forKey: .frameRate)
            try container.encode(autoReconnect, forKey: .autoReconnect)
            try container.encode(isEnabled, forKey: .isEnabled)
            try container.encode(videoEncoder, forKey: .videoEncoder)
            try container.encode(audioEncoder, forKey: .audioEncoder)
            try container.encode(useHardwareAcceleration, forKey: .useHardwareAcceleration)
            try container.encode(h264ProfileLevel, forKey: .h264ProfileLevel)
            try container.encode(bufferSize, forKey: .bufferSize)
            try container.encode(connectionTimeout, forKey: .connectionTimeout)
        }
        
        /// YouTube Live 안정성을 위한 추천 설정
        public static func youTubeLiveOptimized() -> LiveStreamSettings {
            var settings = LiveStreamSettings()
            settings.videoBitrate = 4500
            settings.frameRate = 30
            settings.videoWidth = 1920
            settings.videoHeight = 1080
            settings.audioBitrate = 128
            settings.autoReconnect = true
            return settings
        }

        public var resolutionDescriptor: StreamResolutionDescriptor {
            let dimensions = normalizedVideoDimensions
            return StreamResolutionDescriptor(width: dimensions.width, height: dimensions.height)
        }

        public var normalizedResolutionClass: StreamResolutionClass {
            resolutionDescriptor.resolutionClass
        }

        public var streamLayoutProfile: StreamLayoutProfile {
            streamOrientation.layoutProfile
        }

        public var normalizedVideoDimensions: (width: Int, height: Int) {
            guard videoWidth > 0, videoHeight > 0 else {
                return (videoWidth, videoHeight)
            }

            let isPortraitDimensions = videoHeight > videoWidth
            guard isPortraitDimensions != streamOrientation.isPortrait else {
                return (videoWidth, videoHeight)
            }

            return (videoHeight, videoWidth)
        }

        public var streamAspectRatio: CGFloat {
            let dimensions = normalizedVideoDimensions
            guard dimensions.width > 0, dimensions.height > 0 else {
                return streamLayoutProfile.aspectRatio
            }
            return CGFloat(dimensions.width) / CGFloat(dimensions.height)
        }

        public mutating func normalizeVideoDimensionsForOrientation() {
            let dimensions = normalizedVideoDimensions
            videoWidth = dimensions.width
            videoHeight = dimensions.height
        }

        public mutating func setStreamOrientation(_ orientation: StreamOrientation) {
            guard streamOrientation != orientation else { return }
            streamOrientation = orientation
            normalizeVideoDimensionsForOrientation()
        }

        public mutating func applyResolutionClass(_ resolutionClass: StreamResolutionClass) {
            guard let size = StreamResolutionDescriptor.presetSize(
                for: resolutionClass,
                orientation: streamOrientation
            ) else {
                return
            }
            videoWidth = size.width
            videoHeight = size.height
            normalizeVideoDimensionsForOrientation()
        }

        public func matchesResolutionClass(_ resolutionClass: StreamResolutionClass) -> Bool {
            normalizedResolutionClass == resolutionClass
        }
        
        /// 유튜브 라이브 스트리밍 표준 프리셋 적용
        public mutating func applyYouTubeLivePreset(_ preset: YouTubeLivePreset) {
            let settings = preset.settings(for: streamOrientation)
            
            videoWidth = settings.width
            videoHeight = settings.height
            frameRate = settings.frameRate
            videoBitrate = settings.videoBitrate
            audioBitrate = settings.audioBitrate
            normalizeVideoDimensionsForOrientation()
            // keyframeInterval은 LiveStreamSettings에 없으므로 생략
            
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
                
                let bitrateRange = preset.bitrateRange
                
                if normalizedResolutionClass == preset.resolutionClass &&
                   frameRate == preset.settings(for: streamOrientation).frameRate &&
                   videoBitrate >= bitrateRange.min &&
                   videoBitrate <= bitrateRange.max {
                    return preset
                }
            }
            return .custom
        }
        
        /// 해상도별 추천 비트레이트
        public var recommendedVideoBitrate: Int {
            switch normalizedResolutionClass {
            case .p1080:
                return 4500
            case .p720:
                return 2500
            case .p480:
                return 1500
            case .p4k:
                return 15000
            case .custom:
                return 2500
            }
        }
        
        /// 설정 유효성 검사 (비트레이트 한도 포함)
        public var isValidForYouTube: Bool {
            let maxBitrate = recommendedVideoBitrate * 2  // 권장값의 2배까지 허용
            return !rtmpURL.isEmpty && 
                   !streamKey.isEmpty && 
                   rtmpURL.hasPrefix("rtmp://") &&
                   videoBitrate > 0 &&
                   videoBitrate <= maxBitrate &&  // 비트레이트 상한선 체크
                   audioBitrate > 0 &&
                   videoWidth > 0 &&
                   videoHeight > 0 &&
                   frameRate > 0
        }
    }
}

// MARK: - Global Types (Outside Namespace)

/// 스트리밍 정보
public struct StreamingInfo {
    /// 실제 비디오 비트레이트 (kbps)
    public let actualVideoBitrate: Double
    
    /// 실제 오디오 비트레이트 (kbps)
    public let actualAudioBitrate: Double
    
    /// 네트워크 품질
    public let networkQuality: NetworkQuality
    
    /// 초기화
    public init(actualVideoBitrate: Double, actualAudioBitrate: Double, networkQuality: NetworkQuality) {
        self.actualVideoBitrate = actualVideoBitrate
        self.actualAudioBitrate = actualAudioBitrate
        self.networkQuality = networkQuality
    }
}

/// 네트워크 품질 열거형
public enum NetworkTransmissionQuality {
    case excellent, good, fair, poor, unknown
    
    public var description: String {
        switch self {
        case .excellent: return NSLocalizedString("excellent", comment: "우수")
        case .good: return NSLocalizedString("good", comment: "양호")
        case .fair: return NSLocalizedString("fair", comment: "보통")
        case .poor: return NSLocalizedString("poor", comment: "불량")
        case .unknown: return NSLocalizedString("checking", comment: "확인 중")
        }
    }
}

/// 데이터 전송 통계
public struct DataTransmissionStats {
    /// 비디오 바이트/초
    public var videoBytesPerSecond: Double
    
    /// 네트워크 지연 시간 (ms)
    public var networkLatency: Double
    
    /// 전송된 비디오 프레임 수
    public var videoFramesTransmitted: Int
    
    /// 전송된 오디오 프레임 수
    public var audioFramesTransmitted: Int
    
    /// 총 전송된 바이트 수
    public var totalBytesTransmitted: Int64
    
    /// 현재 비디오 비트레이트 (kbps)
    public var currentVideoBitrate: Double
    
    /// 현재 오디오 비트레이트 (kbps)
    public var currentAudioBitrate: Double
    
    /// 평균 프레임 레이트
    public var averageFrameRate: Double
    
    /// 드롭된 프레임 수
    public var droppedFrames: Int
    
    /// 연결 품질
    public var connectionQuality: NetworkTransmissionQuality
    
    /// 마지막 전송 시간
    public var lastTransmissionTime: Date
    
    /// 기본 초기화
    public init() {
        self.videoBytesPerSecond = 0.0
        self.networkLatency = 0.0
        self.videoFramesTransmitted = 0
        self.audioFramesTransmitted = 0
        self.totalBytesTransmitted = 0
        self.currentVideoBitrate = 0.0
        self.currentAudioBitrate = 0.0
        self.averageFrameRate = 0.0
        self.droppedFrames = 0
        self.connectionQuality = .unknown
        self.lastTransmissionTime = Date()
    }
    
    /// 기존 호환성을 위한 초기화
    public init(videoBytesPerSecond: Double, networkLatency: Double) {
        self.videoBytesPerSecond = videoBytesPerSecond
        self.networkLatency = networkLatency
        self.videoFramesTransmitted = 0
        self.audioFramesTransmitted = 0
        self.totalBytesTransmitted = 0
        self.currentVideoBitrate = 0.0
        self.currentAudioBitrate = 0.0
        self.averageFrameRate = 0.0
        self.droppedFrames = 0
        self.connectionQuality = .unknown
        self.lastTransmissionTime = Date()
    }
}

/// 연결 테스트 결과
public struct ConnectionTestResult {
    /// 성공 여부
    public let isSuccessful: Bool
    
    /// 지연 시간 (ms)
    public let latency: Int
    
    /// 메시지
    public let message: String
    
    /// 네트워크 품질
    public let networkQuality: NetworkQuality
    
    /// 초기화
    public init(isSuccessful: Bool, latency: Int, message: String, networkQuality: NetworkQuality) {
        self.isSuccessful = isSuccessful
        self.latency = latency
        self.message = message
        self.networkQuality = networkQuality
    }
}

/// 스트리밍 추천 설정
public struct StreamingRecommendations {
    /// 추천 비디오 비트레이트 (kbps)
    public let recommendedVideoBitrate: Int
    
    /// 추천 오디오 비트레이트 (kbps)
    public let recommendedAudioBitrate: Int
    
    /// 추천 해상도
    public let recommendedResolution: (width: Int, height: Int)
    
    /// 네트워크 품질
    public let networkQuality: NetworkQuality
    
    /// 개선 제안
    public let suggestions: [String]
    
    /// 초기화
    public init(recommendedVideoBitrate: Int, recommendedAudioBitrate: Int, recommendedResolution: (width: Int, height: Int), networkQuality: NetworkQuality, suggestions: [String]) {
        self.recommendedVideoBitrate = recommendedVideoBitrate
        self.recommendedAudioBitrate = recommendedAudioBitrate
        self.recommendedResolution = recommendedResolution
        self.networkQuality = networkQuality
        self.suggestions = suggestions
    }
} 
