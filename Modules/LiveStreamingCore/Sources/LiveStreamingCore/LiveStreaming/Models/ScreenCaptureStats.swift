import Foundation

/// 화면 캡처 스트리밍 통계
public struct ScreenCaptureStats {
    /// 전송된 총 프레임 수
    public private(set) var frameCount: Int = 0

    /// 성공적으로 전송된 프레임 수
    public var successCount: Int = 0

    /// 전송 실패한 프레임 수
    public var failureCount: Int = 0

    /// 시작 시간
    private let startTime: Date = Date()

    /// 마지막 프레임 시간
    private var lastFrameTime: Date = Date()

    /// FPS 계산을 위한 프레임 타임스탬프 배열 (최근 30개만 유지)
    private var frameTimes: [Date] = []

    /// 현재 FPS
    public var currentFPS: Double {
        guard frameTimes.count > 1 else { return 0.0 }

        let now = Date()
        let validTimes = frameTimes.filter { now.timeIntervalSince($0) <= 1.0 }
        return Double(validTimes.count)
    }

    /// 전체 지속 시간 (초)
    public var duration: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }

    /// 평균 FPS
    public var averageFPS: Double {
        guard duration > 0 else { return 0.0 }
        return Double(frameCount) / duration
    }

    /// 성공률 (%)
    public var successRate: Double {
        guard frameCount > 0 else { return 0.0 }
        return (Double(successCount) / Double(frameCount)) * 100.0
    }

    /// 프레임 카운트 업데이트
    public mutating func updateFrameCount() {
        frameCount += 1
        let now = Date()
        lastFrameTime = now

        // 프레임 시간 추가 (최근 30개만 유지)
        frameTimes.append(now)
        if frameTimes.count > 30 {
            frameTimes.removeFirst()
        }

        // 1초 이상 된 타임스탬프 제거
        frameTimes = frameTimes.filter { now.timeIntervalSince($0) <= 1.0 }
    }

    /// 통계 요약 문자열
    public var summary: String {
        return """
        📊 화면 캡처 통계:
        - 총 프레임: \(frameCount)
        - 성공: \(successCount)
        - 실패: \(failureCount)
        - 성공률: \(String(format: "%.1f", successRate))%
        - 현재 FPS: \(String(format: "%.1f", currentFPS))
        - 평균 FPS: \(String(format: "%.1f", averageFPS))
        - 지속 시간: \(String(format: "%.1f", duration))초
        """
    }

    public init() {}
} 