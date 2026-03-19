//
//  StreamingConstants.swift
//  LiveStreamingCore
//
//  Created by Claude on 2025.
//

import Foundation

// MARK: - Notification Names

/// 화면 캡처 스트리밍 관련 알림 이름
/// 타입 안전성을 위해 문자열 대신 상수 사용
public extension Notification.Name {
    /// 화면 캡처 시작 알림
    static let startScreenCapture = Notification.Name("com.usbexternalcamera.startScreenCapture")
    /// 화면 캡처 중지 알림
    static let stopScreenCapture = Notification.Name("com.usbexternalcamera.stopScreenCapture")
    /// 스트리밍 상태 변경 알림
    static let streamingStatusChanged = Notification.Name("com.usbexternalcamera.streamingStatusChanged")
}

/// 스트리밍 관련 상수 정의
public struct StreamingConstants {

    // MARK: - Timeouts (nanoseconds)
    public struct Timeout {
        /// RTMP 연결 타임아웃 (8초)
        public static let rtmpConnection: UInt64 = 8_000_000_000

        /// Publish 타임아웃 (6초)
        public static let publish: UInt64 = 6_000_000_000

        /// 짧은 지연 (0.1초)
        public static let shortDelay: UInt64 = 100_000_000

        /// 중간 지연 (0.2초)
        public static let mediumDelay: UInt64 = 200_000_000

        /// 상태 전환 지연 (0.5초)
        public static let statusTransition: UInt64 = 500_000_000
    }

    // MARK: - Reconnection
    public struct Reconnect {
        /// 최대 연결 실패 횟수
        public static let maxConnectionFailures = 5

        /// 최대 재연결 시도 횟수
        public static let maxAttempts = 2

        /// 초기 재연결 지연 (초)
        public static let initialDelay = 8.0

        /// 최대 재연결 지연 (초)
        public static let maxDelay = 25.0

        /// 재연결 지연 증가 배수
        public static let delayMultiplier = 1.5
    }

    // MARK: - Video Settings
    public struct Video {
        /// 최소 비트레이트 (kbps)
        public static let minBitrate = 500

        /// 최대 비트레이트 (kbps)
        public static let maxBitrate = 50000

        /// 기본 비트레이트 (kbps)
        public static let defaultBitrate = 2500

        /// 키프레임 간격 배수 (프레임레이트 * 이 값)
        public static let keyframeIntervalMultiplier = 2

        /// 기본 프레임레이트
        public static let defaultFrameRate = 30
    }

    // MARK: - Audio Settings
    public struct Audio {
        /// 기본 오디오 비트레이트 (kbps)
        public static let defaultBitrate = 128

        /// 기본 채널 수
        public static let defaultChannels = 2
    }

    // MARK: - Performance
    public struct Performance {
        /// 성능 모니터링 간격 (초)
        public static let monitoringInterval = 2.0

        /// 진단 타이머 간격 (초)
        public static let diagnosticsInterval = 2.0

        /// 최대 압축 재시도 횟수
        public static let maxCompressionRetries = 3

        /// 압축 재시도 지연 (나노초)
        public static func compressionRetryDelay(attempt: Int) -> UInt64 {
            return UInt64(attempt * 500_000_000) // attempt * 0.5초
        }
    }

    // MARK: - Frame Processing
    public struct Frame {
        /// 예상 프레임 크기 (bytes)
        public static let estimatedSizeBytes: Int64 = 50000 // 50KB

        /// 화면 캡처 FPS
        public static let screenCaptureFPS = 30.0

        /// 픽셀 버퍼 바이트 정렬
        public static let bytesPerRowAlignment = 16
    }

    // MARK: - Validation
    public struct Validation {
        /// 최소 스트림 키 길이
        public static let minimumStreamKeyLength = 8

        /// RTMP URL 프리픽스
        public static let rtmpPrefix = "rtmp"
    }

    // MARK: - UI
    public struct UI {
        /// 키보드 체크 타이머 간격 (초)
        public static let keyboardCheckInterval = 3.0

        /// FPS 표시 갱신 간격 (초)
        public static let fpsUpdateInterval = 1.0
    }
}