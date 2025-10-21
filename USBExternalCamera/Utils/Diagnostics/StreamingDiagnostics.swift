import Foundation
import Network
import SystemConfiguration
import AVFoundation
import SwiftUI
import os.log
import LiveStreamingCore

/// 스트리밍 진단 및 모니터링 시스템 (YouTube, Twitch, FastPix 패턴 적용)
class StreamingDiagnostics: ObservableObject {
    
    static let shared = StreamingDiagnostics()
    
    // MARK: - 네트워크 모니터링
    @Published var networkStatus: DiagnosticNetworkStatus = .unknown
    @Published var bandwidthEstimate: Double = 0.0 // Mbps
    @Published var latency: TimeInterval = 0.0
    @Published var packetLoss: Double = 0.0
    
    // MARK: - 스트리밍 메트릭스
    @Published var bufferHealth: Double = 0.0 // 0.0 ~ 1.0
    @Published var droppedFrames: Int = 0
    @Published var averageBitrate: Double = 0.0
    @Published var streamingErrors: [StreamingError] = []
    
    // MARK: - 시스템 상태
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    
    private var networkMonitor: NWPathMonitor?
    private var diagnosticsTimer: Timer?
    private let diagnosticsQueue = DispatchQueue(label: "StreamingDiagnostics", qos: .utility)
    
    // MARK: - 초기화
    private init() {
        setupNetworkMonitoring()
        startPeriodicDiagnostics()
        setupThermalStateMonitoring()
    }
    
    deinit {
        stopDiagnostics()
    }
    
    // MARK: - 네트워크 모니터링 설정
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.updateNetworkStatus(path)
            }
        }
        networkMonitor?.start(queue: diagnosticsQueue)
    }
    
    private func updateNetworkStatus(_ path: NWPath) {
        switch path.status {
        case .satisfied:
            if path.usesInterfaceType(.wifi) {
                networkStatus = .wifi
            } else if path.usesInterfaceType(.cellular) {
                networkStatus = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                networkStatus = .ethernet
            } else {
                networkStatus = .other
            }
            
            // 대역폭 추정 (실제 측정은 더 복잡함)
            estimateBandwidth(for: path)
            
        case .unsatisfied:
            networkStatus = .disconnected
            bandwidthEstimate = 0.0
            
        case .requiresConnection:
            networkStatus = .requiresConnection
            
        @unknown default:
            networkStatus = .unknown
        }
        
        logNetworkChange()
    }
    
    // MARK: - 대역폭 추정 (간단한 버전)
    private func estimateBandwidth(for path: NWPath) {
        // 실제 앱에서는 더 정교한 측정이 필요
        switch networkStatus {
        case .wifi:
            bandwidthEstimate = Double.random(in: 10.0...100.0) // 10-100 Mbps
        case .cellular:
            bandwidthEstimate = Double.random(in: 1.0...50.0)   // 1-50 Mbps
        case .ethernet:
            bandwidthEstimate = Double.random(in: 50.0...1000.0) // 50-1000 Mbps
        default:
            bandwidthEstimate = 0.0
        }
    }
    
    // MARK: - 주기적 진단 시작
    private func startPeriodicDiagnostics() {
        diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.performDiagnostics()
        }
    }
    
    private func performDiagnostics() {
        Task {
            await updateSystemMetrics()
            await checkStreamingHealth()
            await cleanupOldErrors()
        }
    }
    
    // MARK: - 시스템 메트릭스 업데이트 (백그라운드에서 측정, 메인 스레드에서 UI 업데이트)
    private func updateSystemMetrics() async {
        // 🔧 개선: 시스템 메트릭 측정을 백그라운드에서 처리
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                // 백그라운드에서 시스템 메트릭 측정
                let cpuUsage = self.getCurrentCPUUsage()
                let memoryUsage = self.getCurrentMemoryUsage()
                let thermalState = ProcessInfo.processInfo.thermalState
                
                // 메인 스레드에서 UI 업데이트
                await MainActor.run {
                    self.cpuUsage = cpuUsage
                    self.memoryUsage = memoryUsage
                    self.thermalState = thermalState
                    
                    // 임계값 확인 및 경고
                    self.checkSystemThresholds()
                }
            }
        }
    }
    
    private func getCurrentCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // MB
        }
        return 0.0
    }
    
    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         UnsafeMutablePointer($0),
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // MB
        }
        return 0.0
    }
    
    private func checkSystemThresholds() {
        // CPU 과부하 경고
        if cpuUsage > 80.0 {
            logWarning("High CPU usage detected: \(cpuUsage)%")
        }
        
        // 메모리 과부하 경고
        if memoryUsage > 500.0 { // 500MB 임계값
            logWarning("High memory usage detected: \(memoryUsage)MB")
        }
        
        // 열 상태 경고
        if thermalState == .serious || thermalState == .critical {
            logWarning("Thermal throttling detected: \(thermalState)")
        }
    }
    
    // MARK: - 스트리밍 상태 확인
    @MainActor
    private func checkStreamingHealth() async {
        // 버퍼 상태 확인 (실제 구현에서는 AVPlayer에서 가져옴)
        // bufferHealth = getCurrentBufferHealth()
        
        // 에러 패턴 분석
        analyzeErrorPatterns()
        
        // 품질 권장사항 생성
        generateQualityRecommendations()
    }
    
    private func analyzeErrorPatterns() {
        let recentErrors = streamingErrors.filter {
            $0.timestamp > Date().addingTimeInterval(-300) // 최근 5분
        }
        
        if recentErrors.count > 10 {
            logWarning("High error rate detected: \(recentErrors.count) errors in 5 minutes")
        }
        
        // VideoCodec -12902 에러 패턴 감지
        let codecErrors = recentErrors.filter { $0.code == -12902 }
        if codecErrors.count > 3 {
            logError("VideoCodec error pattern detected - may need fallback settings")
        }
    }
    
    private func generateQualityRecommendations() {
        var recommendations: [String] = []
        
        // 네트워크 기반 권장사항
        if bandwidthEstimate < 2.0 {
            recommendations.append("Consider lowering video quality due to low bandwidth")
        }
        
        // 시스템 기반 권장사항
        if cpuUsage > 70.0 {
            recommendations.append("High CPU usage - consider reducing frame rate")
        }
        
        if thermalState == .serious {
            recommendations.append("Device overheating - reduce streaming quality")
        }
        
        // 권장사항 로깅
        if !recommendations.isEmpty {
            os_log("Quality recommendations: %@", log: .default, type: .info, recommendations.joined(separator: ", "))
        }
    }
    
    // MARK: - 에러 관리
    func reportError(_ error: StreamingError) {
        DispatchQueue.main.async {
            self.streamingErrors.append(error)
            self.logError("Streaming error reported: \(error.description)")
        }
    }
    
    @MainActor
    private func cleanupOldErrors() async {
        let cutoff = Date().addingTimeInterval(-3600) // 1시간 전
        streamingErrors.removeAll { $0.timestamp < cutoff }
    }
    
    // MARK: - 열 상태 모니터링
    private func setupThermalStateMonitoring() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.thermalState = ProcessInfo.processInfo.thermalState
            self?.handleThermalStateChange()
        }
    }
    
    private func handleThermalStateChange() {
        switch thermalState {
        case .nominal:
            os_log("Thermal state: Normal", log: .default, type: .info)
            
        case .fair:
            os_log("Thermal state: Fair - monitoring closely", log: .default, type: .info)
            
        case .serious:
            os_log("Thermal state: Serious - performance may be throttled", log: .default, type: .fault)
            
        case .critical:
            os_log("Thermal state: Critical - significant throttling expected", log: .default, type: .error)
            
        @unknown default:
            os_log("Thermal state: Unknown", log: .default, type: .info)
        }
    }
    
    // MARK: - 진단 리포트 생성
    func generateDiagnosticReport() -> DiagnosticReport {
        return DiagnosticReport(
            timestamp: Date(),
            networkStatus: networkStatus,
            bandwidthEstimate: bandwidthEstimate,
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            thermalState: thermalState,
            recentErrors: Array(streamingErrors.suffix(10)),
            recommendations: generateCurrentRecommendations()
        )
    }
    
    private func generateCurrentRecommendations() -> [String] {
        var recommendations: [String] = []
        
        if networkStatus == DiagnosticNetworkStatus.disconnected {
            recommendations.append("No network connection - check WiFi/cellular settings")
        } else if bandwidthEstimate < 2.0 {
            recommendations.append("Low bandwidth detected - use lower quality settings")
        }
        
        if cpuUsage > 80.0 {
            recommendations.append("High CPU usage - close other apps or reduce quality")
        }
        
        if memoryUsage > 500.0 {
            recommendations.append("High memory usage - restart app if issues persist")
        }
        
        if thermalState == .serious || thermalState == .critical {
            recommendations.append("Device overheating - pause streaming and let device cool down")
        }
        
        return recommendations
    }
    
    // MARK: - 유틸리티 메서드
    private func logNetworkChange() {
        os_log("Network status changed to: %@ (bandwidth: %.1f Mbps)", 
               log: .default, type: .info, networkStatus.description, bandwidthEstimate)
    }
    
    private func logWarning(_ message: String) {
        os_log("%@", log: .default, type: .fault, message)
    }
    
    private func logError(_ message: String) {
        os_log("%@", log: .default, type: .error, message)
    }
    
    private func stopDiagnostics() {
        diagnosticsTimer?.invalidate()
        diagnosticsTimer = nil
        networkMonitor?.cancel()
        networkMonitor = nil
    }
}

// MARK: - 데이터 모델
enum DiagnosticNetworkStatus: CaseIterable {
    case wifi, cellular, ethernet, other, disconnected, requiresConnection, unknown
    
    var description: String {
        switch self {
        case .wifi: return "WiFi"
        case .cellular: return "Cellular"
        case .ethernet: return "Ethernet"
        case .other: return "Other"
        case .disconnected: return "Disconnected"
        case .requiresConnection: return "Requires Connection"
        case .unknown: return "Unknown"
        }
    }
}

struct StreamingError {
    let code: Int
    let description: String
    let timestamp: Date
    let context: [String: Any]?
    
    init(code: Int, description: String, context: [String: Any]? = nil) {
        self.code = code
        self.description = description
        self.timestamp = Date()
        self.context = context
    }
}

struct DiagnosticReport {
    let timestamp: Date
    let networkStatus: DiagnosticNetworkStatus
    let bandwidthEstimate: Double
    let cpuUsage: Double
    let memoryUsage: Double
    let thermalState: ProcessInfo.ThermalState
    let recentErrors: [StreamingError]
    let recommendations: [String]
}

// MARK: - 진단 뷰 헬퍼
extension StreamingDiagnostics {
    
    var networkStatusColor: Color {
        switch networkStatus {
        case .wifi, .ethernet: return .green
        case .cellular: return .orange
        case .disconnected: return .red
        default: return .gray
        }
    }
    
    var systemHealthColor: Color {
        if cpuUsage > 80 || memoryUsage > 500 || thermalState == .critical {
            return .red
        } else if cpuUsage > 60 || memoryUsage > 300 || thermalState == .serious {
            return .orange
        } else {
            return .green
        }
    }
} 
