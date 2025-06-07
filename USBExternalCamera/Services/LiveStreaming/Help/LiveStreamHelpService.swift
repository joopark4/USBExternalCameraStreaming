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
            case .rtmpURL: return "RTMP 서버 URL"
            case .streamKey: return "스트림 키"
            case .videoBitrate: return "비디오 비트레이트"
            case .audioBitrate: return "오디오 비트레이트"
            case .videoResolution: return "비디오 해상도"
            case .frameRate: return "프레임 레이트"
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
                title: "RTMP 서버 URL",
                description: "라이브 스트리밍을 송출할 RTMP 서버의 주소입니다.",
                recommendedValues: [
                    "YouTube: rtmp://a.rtmp.youtube.com/live2/",
                    "Twitch: rtmp://live.twitch.tv/app/"
                ],
                tips: [
                    "가장 가까운 지역의 서버를 선택하면 지연시간이 줄어듭니다",
                    "rtmp:// 프로토콜로 시작해야 합니다"
                ],
                warnings: [
                    "잘못된 URL을 입력하면 연결에 실패합니다"
                ],
                examples: [
                    "rtmp://a.rtmp.youtube.com/live2/"
                ]
            )
        case .streamKey:
            return HelpContent(
                title: "스트림 키",
                description: "각 스트리밍 플랫폼에서 제공하는 고유한 인증 키입니다.",
                recommendedValues: [
                    "플랫폼 대시보드에서 생성된 키 사용"
                ],
                tips: [
                    "스트림 키는 절대 공개하지 마세요"
                ],
                warnings: [
                    "스트림 키가 노출되면 다른 사람이 당신의 채널로 스트리밍할 수 있습니다"
                ],
                examples: [
                    "xxxx-xxxx-xxxx-xxxx-xxxx"
                ]
            )
        default:
            return HelpContent(
                title: topic.title,
                description: "도움말 내용을 준비 중입니다.",
                recommendedValues: [],
                tips: [],
                warnings: [],
                examples: []
            )
        }
    }
}
