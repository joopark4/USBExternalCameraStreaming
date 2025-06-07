import Foundation
import Observation

/// LiveStreamViewModel의 스텁 구현 (UI 테스트용)
@MainActor
class LiveStreamViewModelStub: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isStreaming: Bool = false
    @Published var isLoading: Bool = false
    @Published var currentStatus: LiveStreamStatus = .idle
    @Published var connectionStatus: String = "대기 중"
    @Published var networkQuality: NetworkQuality = .good
    @Published var settings: USBExternalCamera.LiveStreamSettings = USBExternalCamera.LiveStreamSettings()
    @Published var transmissionStats: DataTransmissionStats = DataTransmissionStats()
    
    // MARK: - Private Properties
    
    private var streamStartTime: Date?
    private var simulationTimer: Timer?
    
    // MARK: - Computed Properties
    
    var streamDuration: TimeInterval {
        guard let startTime = streamStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    // MARK: - Public Methods
    
    func startStreaming() async {
        guard !isStreaming && !isLoading else { return }
        
        isLoading = true
        currentStatus = .connecting
        connectionStatus = "연결 중..."
        
        // 시뮬레이션: 연결 프로세스
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2초
        
        // 랜덤하게 성공/실패 결정 (90% 성공률)
        if Double.random(in: 0...1) < 0.9 {
            // 성공
            isStreaming = true
            currentStatus = .streaming
            connectionStatus = "스트리밍 중"
            streamStartTime = Date()
            
            // 송출 통계 초기화
            transmissionStats = DataTransmissionStats()
            
            startSimulation()
        } else {
            // 실패
            let errors: [LiveStreamError] = [
                .networkError("네트워크 연결이 불안정합니다"),
                .authenticationFailed("인증 정보를 확인해주세요"),
                .connectionTimeout
            ]
            currentStatus = .error(errors.randomElement()!)
        }
        
        isLoading = false
    }
    
    func stopStreaming() async {
        guard isStreaming else { return }
        
        isLoading = true
        currentStatus = .disconnecting
        connectionStatus = "연결 해제 중..."
        
        // 시뮬레이션: 연결 해제
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1초
        
        stopSimulation()
        isStreaming = false
        currentStatus = .idle
        connectionStatus = "대기 중"
        streamStartTime = nil
        isLoading = false
    }
    
    func testConnection() async -> ConnectionTestResult {
        // 시뮬레이션: 연결 테스트
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5초
        
        let isSuccessful = Double.random(in: 0...1) < 0.8 // 80% 성공률
        let latency = Int.random(in: 20...150)
        
        if isSuccessful {
            return ConnectionTestResult(
                isSuccessful: true,
                latency: latency,
                message: "연결 테스트 성공! 지연시간: \(latency)ms",
                networkQuality: determineNetworkQuality(latency: latency)
            )
        } else {
            return ConnectionTestResult(
                isSuccessful: false,
                latency: 0,
                message: "연결 테스트 실패. RTMP 서버 설정을 확인해주세요.",
                networkQuality: .poor
            )
        }
    }
    
    func retryConnection() async {
        guard case .error = currentStatus else { return }
        
        // 현재 에러 상태를 초기화하고 재시도
        currentStatus = .idle
        connectionStatus = "재시도 중..."
        
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초 대기
        
        await startStreaming()
    }
    
    // MARK: - Private Methods
    
    private func startSimulation() {
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSimulationState()
            }
        }
    }
    
    private func stopSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }
    
    private func updateSimulationState() {
        guard isStreaming else { return }
        
        // 네트워크 품질 시뮬레이션
        let qualities: [NetworkQuality] = [.excellent, .good, .fair, .poor]
        let weights = [0.4, 0.4, 0.15, 0.05] // 가중치
        
        let random = Double.random(in: 0...1)
        var cumulative = 0.0
        
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if random <= cumulative {
                networkQuality = qualities[index]
                break
            }
        }
        
        // 연결 상태 메시지 업데이트
        let messages = [
            "스트리밍 중 - 안정적 연결",
            "스트리밍 중 - 네트워크 양호",
            "스트리밍 중 - 최적 품질"
        ]
        
        connectionStatus = messages.randomElement() ?? "스트리밍 중"
        
        // 실시간 송출 데이터 시뮬레이션
        updateTransmissionStats()
        
        // 가끔 일시적인 문제 시뮬레이션 (3% 확률)
        if Double.random(in: 0...1) < 0.03 {
            simulateTemporaryIssue()
        }
    }
    
    /// 실시간 송출 데이터 시뮬레이션
    private func updateTransmissionStats() {
        // 프레임 수 증가 (30fps 기준으로 5초마다 150프레임 추가)
        transmissionStats.videoFramesTransmitted += Int.random(in: 140...160)
        transmissionStats.audioFramesTransmitted += Int.random(in: 200...250)
        
        // 전송 바이트 증가 (약간의 변동)
        let bytesPerFrame: Int64 = Int64.random(in: 45000...55000) // 45-55KB per frame
        transmissionStats.totalBytesTransmitted += bytesPerFrame * 150
        
        // 현재 비트레이트 (설정값 기준에서 약간 변동)
        let baseVideoBitrate = Double(settings.videoBitrate)
        transmissionStats.currentVideoBitrate = baseVideoBitrate + Double.random(in: -200...200)
        
        let baseAudioBitrate = Double(settings.audioBitrate)
        transmissionStats.currentAudioBitrate = baseAudioBitrate + Double.random(in: -20...20)
        
        // 프레임율 (30fps 기준에서 약간 변동)
        transmissionStats.averageFrameRate = Double.random(in: 28.5...30.5)
        
        // 네트워크 지연 시간 (네트워크 품질에 따라)
        switch networkQuality {
        case .excellent:
            transmissionStats.networkLatency = Double.random(in: 0.015...0.030) // 15-30ms
            transmissionStats.connectionQuality = .excellent
        case .good:
            transmissionStats.networkLatency = Double.random(in: 0.030...0.070) // 30-70ms
            transmissionStats.connectionQuality = .good
        case .fair:
            transmissionStats.networkLatency = Double.random(in: 0.070...0.120) // 70-120ms
            transmissionStats.connectionQuality = .fair
        case .poor:
            transmissionStats.networkLatency = Double.random(in: 0.120...0.300) // 120-300ms
            transmissionStats.connectionQuality = .poor
            // 네트워크가 나쁠 때 가끔 프레임 드롭
            if Double.random(in: 0...1) < 0.3 {
                transmissionStats.droppedFrames += Int.random(in: 1...5)
            }
        case .unknown:
            transmissionStats.networkLatency = Double.random(in: 0.080...0.150) // 80-150ms
            transmissionStats.connectionQuality = .unknown
        }
        
        // 마지막 전송 시간 업데이트
        transmissionStats.lastTransmissionTime = Date()
        
        // 비디오 바이트/초 계산
        let duration = streamDuration
        if duration > 0 {
            transmissionStats.videoBytesPerSecond = Double(transmissionStats.totalBytesTransmitted) / duration
        }
    }
    
    private func simulateTemporaryIssue() {
        let issues = [
            "네트워크 품질 저하 감지",
            "일시적인 연결 불안정",
            "서버 응답 지연"
        ]
        
        connectionStatus = issues.randomElement()!
        
        // 3초 후 정상 상태로 복구
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.isStreaming {
                self.connectionStatus = "스트리밍 중 - 연결 복구됨"
            }
        }
    }
    
    private func determineNetworkQuality(latency: Int) -> NetworkQuality {
        switch latency {
        case 0..<40:
            return .excellent
        case 40..<80:
            return .good
        case 80..<120:
            return .fair
        default:
            return .poor
        }
    }
    
    // MARK: - Deinitializer
    
    deinit {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }
} 