//
//  StreamingModels.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

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
        case .sd480p: return "YouTube 480p (SD)"
        case .hd720p: return "YouTube 720p (HD)"
        case .fhd1080p: return "YouTube 1080p (Full HD)"
        case .custom: return "사용자 정의"
        }
    }
    
    public var description: String {
        switch self {
        case .sd480p: return "848×480 • 30fps • 1,500 kbps (1,000-2,000)"
        case .hd720p: return "1280×720 • 30fps • 2,500 kbps (2,500-5,000)"
        case .fhd1080p: return "1920×1080 • 30fps • 4,500 kbps (4,500-9,000)"
        case .custom: return "사용자가 직접 설정"
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
    
    /// 유튜브 표준 설정값 반환
    public var settings: (width: Int, height: Int, frameRate: Int, videoBitrate: Int, audioBitrate: Int, keyframeInterval: Int) {
        switch self {
        case .sd480p:
            return (848, 480, 30, 1500, 128, 2) // 16의 배수 호환성 개선
        case .hd720p:
            return (1280, 720, 30, 2500, 128, 2) // 권장 기본값 (LiveStreamSettings 기본값과 일치)
        case .fhd1080p:
            return (1920, 1080, 30, 4500, 128, 2) // 권장 기본값 (유튜브 표준)
        case .custom:
            return (1920, 1080, 30, 4500, 128, 2) // 기본값
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

// MARK: - USBExternalCamera Namespace

public enum USBExternalCamera {
    
    // MARK: - Live Stream Settings
    
    /// 라이브 스트리밍 설정
    public struct LiveStreamSettings: Codable {
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
        
        /// 버퍼 크기 (MB)
        public var bufferSize: Int
        
        /// 연결 타임아웃 (초)
        public var connectionTimeout: Int
        
        /// 기본 초기화
        public init() {
            self.streamTitle = ""
            self.rtmpURL = "rtmp://a.rtmp.youtube.com/live2"  // YouTube Live 기본 RTMP URL
            self.streamKey = ""
            self.videoBitrate = 2500  // YouTube Live 720p 권장값
            self.audioBitrate = 128
            self.videoWidth = 1280
            self.videoHeight = 720
            self.frameRate = 30
            self.autoReconnect = true
            self.isEnabled = true
            self.videoEncoder = "H.264"
            self.audioEncoder = "AAC"
            self.bufferSize = 3
            self.connectionTimeout = 30
        }
        
        /// YouTube Live 안정성을 위한 추천 설정
        public static func youTubeLiveOptimized() -> LiveStreamSettings {
            var settings = LiveStreamSettings()
            settings.videoBitrate = 1500  // 안정적인 1080p
            settings.frameRate = 30
            settings.videoWidth = 1920
            settings.videoHeight = 1080
            settings.audioBitrate = 128
            settings.autoReconnect = true
            return settings
        }
        
        /// 유튜브 라이브 스트리밍 표준 프리셋 적용
        public mutating func applyYouTubeLivePreset(_ preset: YouTubeLivePreset) {
            let settings = preset.settings
            
            videoWidth = settings.width
            videoHeight = settings.height
            frameRate = settings.frameRate
            videoBitrate = settings.videoBitrate
            audioBitrate = settings.audioBitrate
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
        
        /// 해상도별 추천 비트레이트
        public var recommendedVideoBitrate: Int {
            switch (videoWidth, videoHeight) {
            case (1920, 1080): return 4500  // 1080p: 4500-9000 kbps (유튜브 표준)
            case (1280, 720): return 2500   // 720p: 2500-5000 kbps (유튜브 표준)
            case (854, 480), (848, 480): return 1500    // 480p: 1000-2000 kbps (유튜브 표준)
            default: return 2500
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
        case .excellent: return "우수"
        case .good: return "양호"
        case .fair: return "보통"
        case .poor: return "불량"
        case .unknown: return "확인 중"
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