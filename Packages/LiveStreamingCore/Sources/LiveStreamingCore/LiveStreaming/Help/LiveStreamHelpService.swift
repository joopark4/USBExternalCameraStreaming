//
//  LiveStreamHelpService.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation

// MARK: - Live Stream Help Service

/// 라이브 스트리밍 설정 도움말 시스템
public final class LiveStreamHelpService {
    
    /// 도움말 항목 타입
    public enum HelpTopic: String, CaseIterable {
        case rtmpURL = "rtmp_url"
        case streamKey = "stream_key"
        case videoBitrate = "video_bitrate"
        case audioBitrate = "audio_bitrate"
        case videoResolution = "video_resolution"
        case frameRate = "frame_rate"
        
        public var title: String {
            switch self {
            case .rtmpURL: return NSLocalizedString("help_rtmp_server_url", comment: "RTMP 서버 URL")
            case .streamKey: return NSLocalizedString("help_stream_key", comment: "스트림 키")
            case .videoBitrate: return NSLocalizedString("help_video_bitrate", comment: "비디오 비트레이트")
            case .audioBitrate: return NSLocalizedString("help_audio_bitrate", comment: "오디오 비트레이트")
            case .videoResolution: return NSLocalizedString("help_video_resolution", comment: "비디오 해상도")
            case .frameRate: return NSLocalizedString("help_frame_rate", comment: "프레임 레이트")
            }
        }
    }
    
    /// 도움말 내용 구조체
    public struct HelpContent {
        public let title: String
        public let description: String
        public let recommendedValues: [String]
        public let tips: [String]
        public let warnings: [String]
        public let examples: [String]
    }
    
    /// 모든 도움말 주제 목록 반환
    public static func getAllHelpTopics() -> [HelpTopic] {
        return HelpTopic.allCases
    }
    
    /// 도움말 내용 제공
    public static func getHelpContent(for topic: HelpTopic) -> HelpContent {
        switch topic {
        case .rtmpURL:
            return HelpContent(
                title: NSLocalizedString("help_rtmp_url_title", comment: ""),
                description: NSLocalizedString("help_rtmp_url_desc", comment: ""),
                recommendedValues: [
                    NSLocalizedString("help_rtmp_recommended_youtube", comment: ""),
                    NSLocalizedString("help_rtmp_recommended_twitch", comment: "")
                ],
                tips: [
                    NSLocalizedString("help_rtmp_tip_server_location", comment: ""),
                    NSLocalizedString("help_rtmp_tip_protocol", comment: "")
                ],
                warnings: [
                    NSLocalizedString("help_rtmp_warning_invalid_url", comment: "")
                ],
                examples: [
                    NSLocalizedString("help_rtmp_example_youtube", comment: "")
                ]
            )
        case .streamKey:
            return HelpContent(
                title: NSLocalizedString("help_stream_key_title", comment: ""),
                description: NSLocalizedString("help_stream_key_desc", comment: ""),
                recommendedValues: [
                    NSLocalizedString("help_stream_key_recommended_dashboard", comment: "")
                ],
                tips: [
                    NSLocalizedString("help_stream_key_tip_security", comment: "")
                ],
                warnings: [
                    NSLocalizedString("help_stream_key_warning_exposure", comment: "")
                ],
                examples: [
                    NSLocalizedString("help_stream_key_example_format1", comment: "")
                ]
            )
        default:
            return HelpContent(
                title: topic.title,
                description: NSLocalizedString("help_content_in_progress", comment: ""),
                recommendedValues: [],
                tips: [],
                warnings: [],
                examples: []
            )
        }
    }
}
