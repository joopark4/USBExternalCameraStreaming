//
//  NetworkMonitoringManager.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import Foundation
import Network
import os.log
import Combine

// MARK: - Network Monitoring Manager Implementation

/// 네트워크 모니터링 매니저
public final class NetworkMonitoringManager: NetworkMonitoringManagerProtocol {
    
    // MARK: - Properties
    
    /// 네트워크 모니터
    private let monitor = NWPathMonitor()
    
    /// 모니터링 큐
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    /// 현재 네트워크 품질
    @Published public private(set) var currentNetworkQuality: NetworkQuality = .unknown
    
    /// 현재 네트워크 경로
    private var currentPath: NWPath?
    
    /// 모니터링 활성 상태
    private var isMonitoring = false
    
    // MARK: - Initialization
    
    public init() {
        logInfo("🌐 NetworkMonitoringManager initialized", category: .streaming)
        setupNetworkMonitor()
    }
    
    deinit {
        logInfo("NetworkMonitoringManager deinitializing...", category: .streaming)
        if isMonitoring {
            monitor.cancel()
        }
    }
    
    // MARK: - Protocol Implementation
    
    /// 네트워크 모니터링 시작
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        logInfo("📡 Starting network monitoring...", category: .streaming)
        monitor.start(queue: queue)
        isMonitoring = true
    }
    
    /// 네트워크 모니터링 중지
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        logInfo("🛑 Stopping network monitoring...", category: .streaming)
        monitor.cancel()
        isMonitoring = false
    }
    
    /// 네트워크 품질 평가
    public func assessNetworkQuality() async {
        guard let path = currentPath else {
            await MainActor.run {
                currentNetworkQuality = .unknown
            }
            return
        }
        
        let quality = evaluateNetworkQuality(from: path)
        await MainActor.run {
            updateNetworkQuality(quality)
        }
    }
    
    // MARK: - Private Methods
    
    /// 네트워크 모니터 설정
    private func setupNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleNetworkPathUpdate(path)
        }
    }
    
    /// 네트워크 경로 업데이트 처리
    private func handleNetworkPathUpdate(_ path: NWPath) {
        currentPath = path
        let quality = evaluateNetworkQuality(from: path)
        
        DispatchQueue.main.async { [weak self] in
            self?.updateNetworkQuality(quality)
        }
    }
    
    /// 네트워크 품질 업데이트
    private func updateNetworkQuality(_ quality: NetworkQuality) {
        guard currentNetworkQuality != quality else { return }
        
        currentNetworkQuality = quality
        logInfo("🌐 Network quality updated: \(quality.displayName)", category: .streaming)
    }
    
    /// 네트워크 경로에서 품질 평가
    private func evaluateNetworkQuality(from path: NWPath) -> NetworkQuality {
        guard path.status == .satisfied else {
            return .poor
        }
        
        // 연결 타입별 품질 평가
        if path.usesInterfaceType(.wifi) {
            return .excellent
        } else if path.usesInterfaceType(.cellular) {
            return .good
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .excellent
        } else {
            return .fair
        }
    }
    
    // MARK: - Public Utility Methods
    
    /// 현재 네트워크 상태 정보 반환
    public func getCurrentNetworkInfo() -> NetworkInfo {
        guard let path = currentPath else {
            return NetworkInfo(
                isConnected: false,
                connectionType: .unknown,
                quality: .unknown
            )
        }
        
        let connectionType: NetworkConnectionType
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }
        
        return NetworkInfo(
            isConnected: path.status == .satisfied,
            connectionType: connectionType,
            quality: currentNetworkQuality
        )
    }
    
    /// 네트워크 지연 시간 측정
    public func measureNetworkLatency() async -> Double {
        // 실제 구현에서는 ping 테스트나 HTTP 요청을 통해 측정
        // 현재는 기본값 반환
        return 50.0 // 50ms
    }
    
    /// 대역폭 테스트
    public func testBandwidth() async -> BandwidthTestResult {
        // 실제 구현에서는 대역폭 테스트 수행
        // 현재는 기본값 반환
        return BandwidthTestResult(
            downloadSpeed: 50.0, // 50 Mbps
            uploadSpeed: 10.0,   // 10 Mbps
            quality: currentNetworkQuality
        )
    }
}

// MARK: - Supporting Types

/// 네트워크 정보
public struct NetworkInfo {
    public let isConnected: Bool
    public let connectionType: NetworkConnectionType
    public let quality: NetworkQuality
}

/// 네트워크 연결 타입
public enum NetworkConnectionType {
    case wifi
    case cellular
    case ethernet
    case unknown
    
    public var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "셀룰러"
        case .ethernet: return "이더넷"
        case .unknown: return "알 수 없음"
        }
    }
}

/// 대역폭 테스트 결과
public struct BandwidthTestResult {
    public let downloadSpeed: Double // Mbps
    public let uploadSpeed: Double   // Mbps
    public let quality: NetworkQuality
} 