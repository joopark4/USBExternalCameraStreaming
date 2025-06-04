//
//  LiveStreamSettings.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import Foundation
import SwiftData

/// 라이브 스트리밍 설정을 위한 모델
/// HaishinKit RTMP를 사용하여 유튜브 라이브 스트리밍을 지원합니다.
@Model
final class LiveStreamSettings {
    /// 라이브 스트림 제목
    var streamTitle: String = ""
    
    /// 유튜브 RTMP 서버 URL
    var rtmpURL: String = "rtmp://a.rtmp.youtube.com/live2/"
    
    /// 유튜브 스트림 키
    var streamKey: String = ""
    
    /// 비디오 비트레이트 (kbps)
    var videoBitrate: Int = 2500
    
    /// 오디오 비트레이트 (kbps)
    var audioBitrate: Int = 128
    
    /// 비디오 해상도 너비
    var videoWidth: Int = 1920
    
    /// 비디오 해상도 높이
    var videoHeight: Int = 1080
    
    /// 프레임률 (fps)
    var frameRate: Int = 30
    
    /// 라이브 스트리밍 활성화 여부
    var isEnabled: Bool = false
    
    /// 자동 재연결 설정
    var autoReconnect: Bool = true
    
    /// 생성 일시
    var createdAt: Date = Date()
    
    /// 수정 일시
    var updatedAt: Date = Date()
    
    init() {}
    
    init(streamTitle: String, streamKey: String) {
        self.streamTitle = streamTitle
        self.streamKey = streamKey
    }
}

/// 라이브 스트리밍 상태
enum LiveStreamStatus: CaseIterable {
    case idle           /// 대기 중
    case connecting     /// 연결 중
    case connected      /// 연결됨
    case streaming      /// 스트리밍 중
    case disconnecting  /// 연결 해제 중
    case error          /// 오류 발생
    
    /// 상태에 대한 한국어 설명
    var description: String {
        switch self {
        case .idle:
            return "대기 중"
        case .connecting:
            return "연결 중"
        case .connected:
            return "연결됨"
        case .streaming:
            return "스트리밍 중"
        case .disconnecting:
            return "연결 해제 중"
        case .error:
            return "오류 발생"
        }
    }
    
    /// 상태 아이콘
    var iconName: String {
        switch self {
        case .idle:
            return "pause.circle"
        case .connecting:
            return "arrow.clockwise.circle"
        case .connected:
            return "checkmark.circle"
        case .streaming:
            return "dot.radiowaves.left.and.right"
        case .disconnecting:
            return "xmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

/// 비디오 해상도 프리셋
enum VideoResolution: String, CaseIterable {
    case hd720 = "1280x720"
    case fullHD = "1920x1080"
    case uhd4k = "3840x2160"
    
    var width: Int {
        switch self {
        case .hd720: return 1280
        case .fullHD: return 1920
        case .uhd4k: return 3840
        }
    }
    
    var height: Int {
        switch self {
        case .hd720: return 720
        case .fullHD: return 1080
        case .uhd4k: return 2160
        }
    }
    
    var displayName: String {
        switch self {
        case .hd720: return "HD 720p"
        case .fullHD: return "Full HD 1080p"
        case .uhd4k: return "4K UHD"
        }
    }
} 