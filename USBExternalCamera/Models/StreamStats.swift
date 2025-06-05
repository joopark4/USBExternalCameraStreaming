//
//  StreamStats.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import Foundation

/// 스트리밍 통계 정보 모델
@Observable
final class StreamStats {
    
    // MARK: - Basic Statistics
    
    /// 스트리밍 시작 시간
    var startTime: Date?
    
    /// 현재 비디오 비트레이트 (kbps)
    var videoBitrate: Double = 0.0
    
    /// 현재 오디오 비트레이트 (kbps)
    var audioBitrate: Double = 0.0
    
    /// 현재 프레임 레이트 (fps)
    var frameRate: Double = 0.0
    
    /// 드롭된 프레임 수
    var droppedFrames: Int = 0
    
    /// 업로드 속도 (kbps)
    var uploadSpeed: Double = 0.0
    
    // MARK: - Network Statistics
    
    /// 네트워크 지연시간 (ms)
    var latency: Double = 0.0
    
    /// 패킷 손실률 (%)
    var packetLoss: Double = 0.0
    
    /// 재연결 횟수
    var reconnectCount: Int = 0
    
    /// 총 전송된 데이터 (MB)
    var totalDataSent: Double = 0.0
    
    /// 총 프레임 수
    var totalFrames: Int = 0
    
    /// 버퍼 상태 (%)
    var bufferHealth: Double = 100.0
    
    // MARK: - Quality Metrics
    
    /// 인코딩 품질 점수 (0-100)
    var encodingQuality: Int = 100
    
    /// 네트워크 안정성 점수 (0-100)
    var networkStability: Int = 100
    
    /// 전체 품질 점수 (0-100)
    var overallQuality: Int = 100
    
    // MARK: - Computed Properties
    
    /// 스트리밍 지속 시간 (초)
    var duration: TimeInterval {
        guard let startTime = startTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    /// 스트리밍 지속 시간 문자열
    var durationString: String {
        let duration = self.duration
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    /// 평균 비트레이트
    var averageBitrate: Double {
        return videoBitrate + audioBitrate
    }
    
    /// 데이터 사용량 문자열
    var dataSentString: String {
        if totalDataSent < 1024 {
            return String(format: "%.1f MB", totalDataSent)
        } else {
            return String(format: "%.2f GB", totalDataSent / 1024)
        }
    }
    
    /// 품질 상태
    var qualityStatus: QualityStatus {
        if overallQuality >= 90 {
            return .excellent
        } else if overallQuality >= 70 {
            return .good
        } else if overallQuality >= 50 {
            return .fair
        } else {
            return .poor
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // 기본값으로 초기화됨
    }
    
    // MARK: - Update Methods
    
    /// 통계 정보 업데이트
    func updateStats(
        videoBitrate: Double? = nil,
        audioBitrate: Double? = nil,
        frameRate: Double? = nil,
        droppedFrames: Int? = nil,
        uploadSpeed: Double? = nil,
        latency: Double? = nil,
        packetLoss: Double? = nil
    ) {
        if let videoBitrate = videoBitrate {
            self.videoBitrate = videoBitrate
        }
        if let audioBitrate = audioBitrate {
            self.audioBitrate = audioBitrate
        }
        if let frameRate = frameRate {
            self.frameRate = frameRate
        }
        if let droppedFrames = droppedFrames {
            self.droppedFrames = droppedFrames
        }
        if let uploadSpeed = uploadSpeed {
            self.uploadSpeed = uploadSpeed
        }
        if let latency = latency {
            self.latency = latency
        }
        if let packetLoss = packetLoss {
            self.packetLoss = packetLoss
        }
        
        updateQualityMetrics()
    }
    
    /// 품질 지표 업데이트
    private func updateQualityMetrics() {
        // 인코딩 품질 계산 (드롭된 프레임 기준)
        let frameDropRate = frameRate > 0 ? Double(droppedFrames) / (frameRate * duration) : 0
        encodingQuality = max(0, min(100, Int((1.0 - frameDropRate) * 100)))
        
        // 네트워크 안정성 계산 (지연시간과 패킷 손실 기준)
        let latencyScore = max(0, min(100, Int((1.0 - latency / 1000.0) * 100)))
        let packetLossScore = max(0, min(100, Int((1.0 - packetLoss / 100.0) * 100)))
        networkStability = (latencyScore + packetLossScore) / 2
        
        // 전체 품질 점수
        overallQuality = (encodingQuality + networkStability) / 2
    }
    
    /// 재연결 카운트 증가
    func incrementReconnectCount() {
        reconnectCount += 1
    }
    
    /// 전송 데이터 업데이트
    func updateDataSent(_ bytes: Int64) {
        totalDataSent = Double(bytes) / (1024 * 1024) // MB로 변환
    }
    
    /// 스트리밍 시작
    func startStreaming() {
        startTime = Date()
        // 통계 초기화
        droppedFrames = 0
        totalFrames = 0
        totalDataSent = 0.0
        reconnectCount = 0
        bufferHealth = 100.0
        encodingQuality = 100
        networkStability = 100
        overallQuality = 100
    }
    
    /// 스트리밍 중지
    func stopStreaming() {
        // startTime은 유지하여 총 스트리밍 시간을 기록
        // 다른 실시간 통계들은 0으로 재설정
        videoBitrate = 0.0
        audioBitrate = 0.0
        frameRate = 0.0
        uploadSpeed = 0.0
        latency = 0.0
        packetLoss = 0.0
        bufferHealth = 0.0
    }
    
    /// 통계 초기화
    func reset() {
        startTime = nil
        videoBitrate = 0.0
        audioBitrate = 0.0
        frameRate = 0.0
        droppedFrames = 0
        totalFrames = 0
        uploadSpeed = 0.0
        latency = 0.0
        packetLoss = 0.0
        reconnectCount = 0
        totalDataSent = 0.0
        bufferHealth = 100.0
        encodingQuality = 100
        networkStability = 100
        overallQuality = 100
    }
}

// MARK: - Supporting Types

/// 품질 상태
enum QualityStatus: String, CaseIterable {
    case excellent = "excellent"
    case good = "good"
    case fair = "fair"
    case poor = "poor"
    
    var displayName: String {
        switch self {
        case .excellent: return "우수"
        case .good: return "양호"
        case .fair: return "보통"
        case .poor: return "불량"
        }
    }
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange"
        case .poor: return "red"
        }
    }
    
    var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🔵"
        case .fair: return "🟡"
        case .poor: return "��"
        }
    }
} 