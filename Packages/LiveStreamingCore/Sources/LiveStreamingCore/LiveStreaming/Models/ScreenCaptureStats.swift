import Foundation

public enum ScreenCaptureDropReason: String, Sendable {
    case renderBackpressure
    case sendBackpressure
}

/// 화면 캡처 스트리밍 통계
public struct ScreenCaptureStats: Sendable {
    /// 전송된 총 프레임 수
    public private(set) var frameCount: Int = 0

    /// 성공적으로 전송된 프레임 수
    public private(set) var successCount: Int = 0

    /// 전송 실패한 프레임 수
    public private(set) var failureCount: Int = 0

    /// 렌더링 병목으로 드랍된 프레임 수
    public private(set) var renderDropCount: Int = 0

    /// 전송 병목으로 드랍된 프레임 수
    public private(set) var sendDropCount: Int = 0

    /// 메인 스레드 hitch 감지 횟수
    public private(set) var mainThreadHitchCount: Int = 0

    /// 최근 캡처 cadence(ms)
    public private(set) var latestCaptureCadenceMs: Double = 0

    /// 최근 카메라 프레임 age(ms)
    public private(set) var latestCameraFrameAgeMs: Double = 0

    /// 최근 합성 시간(ms)
    public private(set) var latestCompositionTimeMs: Double = 0

    /// 평균 합성 시간(ms)
    public private(set) var averageCompositionTimeMs: Double = 0

    /// 최근 전처리 시간(ms)
    public private(set) var latestPreprocessTimeMs: Double = 0

    /// 평균 전처리 시간(ms)
    public private(set) var averagePreprocessTimeMs: Double = 0

    /// 최근 enqueue lag(ms)
    public private(set) var latestEnqueueLagMs: Double = 0

    /// 평균 enqueue lag(ms)
    public private(set) var averageEnqueueLagMs: Double = 0

    /// 시작 시간
    private let startTime: Date = Date()

    /// 마지막 프레임 시간
    private var lastFrameTime: Date = Date()

    /// FPS 계산을 위한 프레임 타임스탬프 배열 (최근 30개만 유지)
    private var frameTimes: [Date] = []

    private var compositionSampleCount: Int = 0
    private var preprocessSampleCount: Int = 0
    private var enqueueLagSampleCount: Int = 0
    private var totalCompositionTimeMs: Double = 0
    private var totalPreprocessTimeMs: Double = 0
    private var totalEnqueueLagMs: Double = 0

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

    /// 성공 카운트 증가
    public mutating func incrementSuccessCount() {
        successCount += 1
    }

    /// 실패 카운트 증가
    public mutating func incrementFailureCount() {
        failureCount += 1
    }

    public mutating func recordDrop(reason: ScreenCaptureDropReason) {
        switch reason {
        case .renderBackpressure:
            renderDropCount += 1
        case .sendBackpressure:
            sendDropCount += 1
        }
    }

    public mutating func recordLoopMetrics(
        captureCadenceMs: Double?,
        cameraFrameAgeMs: Double?,
        compositionTimeMs: Double?,
        mainThreadHitch: Bool
    ) {
        if let captureCadenceMs {
            latestCaptureCadenceMs = captureCadenceMs
        }

        if let cameraFrameAgeMs {
            latestCameraFrameAgeMs = cameraFrameAgeMs
        }

        if let compositionTimeMs {
            latestCompositionTimeMs = compositionTimeMs
            compositionSampleCount += 1
            totalCompositionTimeMs += compositionTimeMs
            averageCompositionTimeMs = totalCompositionTimeMs / Double(compositionSampleCount)
        }

        if mainThreadHitch {
            mainThreadHitchCount += 1
        }
    }

    public mutating func recordPreprocessTime(_ preprocessTimeMs: Double) {
        latestPreprocessTimeMs = preprocessTimeMs
        preprocessSampleCount += 1
        totalPreprocessTimeMs += preprocessTimeMs
        averagePreprocessTimeMs = totalPreprocessTimeMs / Double(preprocessSampleCount)
    }

    public mutating func recordEnqueueLag(_ enqueueLagMs: Double) {
        latestEnqueueLagMs = enqueueLagMs
        enqueueLagSampleCount += 1
        totalEnqueueLagMs += enqueueLagMs
        averageEnqueueLagMs = totalEnqueueLagMs / Double(enqueueLagSampleCount)
    }

    /// 통계 요약 문자열
    public var summary: String {
        return """
        📊 화면 캡처 통계:
        - 총 프레임: \(frameCount)
        - 성공: \(successCount)
        - 실패: \(failureCount)
        - 렌더 드랍: \(renderDropCount)
        - 전송 드랍: \(sendDropCount)
        - 성공률: \(String(format: "%.1f", successRate))%
        - 현재 FPS: \(String(format: "%.1f", currentFPS))
        - 평균 FPS: \(String(format: "%.1f", averageFPS))
        - 최근 cadence: \(String(format: "%.1f", latestCaptureCadenceMs))ms
        - 최근 카메라 age: \(String(format: "%.1f", latestCameraFrameAgeMs))ms
        - 평균 합성 시간: \(String(format: "%.1f", averageCompositionTimeMs))ms
        - 평균 전처리 시간: \(String(format: "%.1f", averagePreprocessTimeMs))ms
        - 평균 enqueue lag: \(String(format: "%.1f", averageEnqueueLagMs))ms
        - 메인 hitch: \(mainThreadHitchCount)회
        - 지속 시간: \(String(format: "%.1f", duration))초
        """
    }

    public init() {}
} 
