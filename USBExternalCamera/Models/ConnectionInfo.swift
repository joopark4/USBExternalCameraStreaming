//
//  ConnectionInfo.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 6/5/25.
//

import Foundation

/// 연결 정보 모델
@Observable
final class ConnectionInfo {
    
    // MARK: - Connection Details
    
    /// 서버 주소
    var serverAddress: String
    
    /// 포트 번호
    var port: Int
    
    /// 연결 상태
    var status: ConnectionStatus
    
    /// 연결된 시간
    var connectedAt: Date?
    
    /// 마지막 활동 시간
    var lastActivityAt: Date?
    
    // MARK: - Network Information
    
    /// IP 주소
    var ipAddress: String?
    
    /// 네트워크 타입 (Wi-Fi, Cellular 등)
    var networkType: String?
    
    /// 신호 강도 (0-100)
    var signalStrength: Int = 0
    
    // MARK: - Performance Metrics
    
    /// 연결 지연시간 (ms)
    var connectionLatency: Double = 0.0
    
    /// 대역폭 (kbps)
    var bandwidth: Double = 0.0
    
    /// 안정성 점수 (0-100)
    var stabilityScore: Int = 100
    
    // MARK: - Error Information
    
    /// 마지막 에러 메시지
    var lastError: String?
    
    /// 에러 발생 시간
    var lastErrorAt: Date?
    
    /// 총 에러 발생 횟수
    var totalErrorCount: Int = 0
    
    // MARK: - Computed Properties
    
    /// 연결 지속 시간
    var connectionDuration: TimeInterval {
        guard let connectedAt = connectedAt else { return 0 }
        return Date().timeIntervalSince(connectedAt)
    }
    
    /// 연결 지속 시간 문자열
    var connectionDurationString: String {
        let duration = connectionDuration
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d시간 %d분 %d초", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d분 %d초", minutes, seconds)
        } else {
            return String(format: "%d초", seconds)
        }
    }
    
    /// 서버 주소 표시용
    var displayServerAddress: String {
        return "\(serverAddress):\(port)"
    }
    
    /// 연결 품질
    var connectionQuality: ConnectionQuality {
        if stabilityScore >= 90 && connectionLatency < 50 {
            return .excellent
        } else if stabilityScore >= 70 && connectionLatency < 100 {
            return .good
        } else if stabilityScore >= 50 && connectionLatency < 200 {
            return .fair
        } else {
            return .poor
        }
    }
    
    // MARK: - Initialization
    
    init(
        serverAddress: String,
        port: Int,
        status: ConnectionStatus,
        connectedAt: Date? = nil
    ) {
        self.serverAddress = serverAddress
        self.port = port
        self.status = status
        self.connectedAt = connectedAt
        
        if status == .connected && connectedAt == nil {
            self.connectedAt = Date()
        }
    }
    
    // MARK: - Update Methods
    
    /// 연결 상태 업데이트
    func updateStatus(_ newStatus: ConnectionStatus) {
        let previousStatus = status
        status = newStatus
        
        switch newStatus {
        case .connected:
            if previousStatus != .connected {
                connectedAt = Date()
            }
            lastActivityAt = Date()
            
        case .connecting, .reconnecting:
            lastActivityAt = Date()
            
        case .disconnected, .failed:
            // 연결 해제 시에도 정보는 유지
            lastActivityAt = Date()
        }
    }
    
    /// 네트워크 정보 업데이트
    func updateNetworkInfo(
        ipAddress: String? = nil,
        networkType: String? = nil,
        signalStrength: Int? = nil
    ) {
        if let ipAddress = ipAddress {
            self.ipAddress = ipAddress
        }
        if let networkType = networkType {
            self.networkType = networkType
        }
        if let signalStrength = signalStrength {
            self.signalStrength = max(0, min(100, signalStrength))
        }
        
        lastActivityAt = Date()
    }
    
    /// 성능 지표 업데이트
    func updatePerformanceMetrics(
        latency: Double? = nil,
        bandwidth: Double? = nil
    ) {
        if let latency = latency {
            connectionLatency = latency
        }
        if let bandwidth = bandwidth {
            self.bandwidth = bandwidth
        }
        
        // 안정성 점수 계산
        calculateStabilityScore()
        lastActivityAt = Date()
    }
    
    /// 에러 정보 기록
    func recordError(_ error: String) {
        lastError = error
        lastErrorAt = Date()
        totalErrorCount += 1
        
        // 에러 발생 시 안정성 점수 감소
        stabilityScore = max(0, stabilityScore - 5)
    }
    
    /// 안정성 점수 계산
    private func calculateStabilityScore() {
        var score = 100
        
        // 지연시간 기준 점수 감소
        if connectionLatency > 200 {
            score -= 30
        } else if connectionLatency > 100 {
            score -= 15
        } else if connectionLatency > 50 {
            score -= 5
        }
        
        // 에러 발생 횟수 기준 점수 감소
        let errorPenalty = min(50, totalErrorCount * 5)
        score -= errorPenalty
        
        // 신호 강도 기준 점수 조정
        if signalStrength < 30 {
            score -= 20
        } else if signalStrength < 60 {
            score -= 10
        }
        
        stabilityScore = max(0, min(100, score))
    }
    
    /// 연결 정보 초기화
    func reset() {
        status = .disconnected
        connectedAt = nil
        lastActivityAt = nil
        ipAddress = nil
        networkType = nil
        signalStrength = 0
        connectionLatency = 0.0
        bandwidth = 0.0
        stabilityScore = 100
        lastError = nil
        lastErrorAt = nil
        totalErrorCount = 0
    }
}

// MARK: - Supporting Types

/// 연결 상태
enum ConnectionStatus: String, CaseIterable {
    case disconnected = "disconnected"
    case connecting = "connecting"
    case connected = "connected"
    case reconnecting = "reconnecting"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .disconnected: return "연결 해제"
        case .connecting: return "연결 중"
        case .connected: return "연결됨"
        case .reconnecting: return "재연결 중"
        case .failed: return "연결 실패"
        }
    }
    
    var emoji: String {
        switch self {
        case .disconnected: return "⚪"
        case .connecting: return "🟡"
        case .connected: return "🟢"
        case .reconnecting: return "🔄"
        case .failed: return "🔴"
        }
    }
    
    var isConnected: Bool {
        return self == .connected
    }
    
    var isConnecting: Bool {
        return self == .connecting || self == .reconnecting
    }
}

/// 연결 품질
enum ConnectionQuality: String, CaseIterable {
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