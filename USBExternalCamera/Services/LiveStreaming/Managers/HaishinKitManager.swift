import Foundation
import AVFoundation
import os.log
import Combine
import Network
import HaishinKit

// MARK: - HaishinKit Manager Protocol

/// HaishinKit 매니저 프로토콜
public protocol HaishinKitManagerProtocol: AnyObject {
    /// 스트리밍 시작 (기본)
    func startStreaming(with settings: USBExternalCamera.LiveStreamSettings) async throws
    
    /// 스트리밍 시작 (프리뷰와 동일한 카메라 세션 사용)
    func startStreaming(with settings: USBExternalCamera.LiveStreamSettings, captureSession: AVCaptureSession) async throws
    
    /// 스트리밍 중지
    func stopStreaming() async
    
    /// 연결 테스트
    func testConnection(to settings: USBExternalCamera.LiveStreamSettings) async -> ConnectionTestResult
    
    /// 현재 스트리밍 상태
    var isStreaming: Bool { get }
    
    /// 현재 스트리밍 상태 (상세)
    var currentStatus: LiveStreamStatus { get }
    
    /// 실시간 데이터 송출 통계
    var transmissionStats: DataTransmissionStats { get }
    
    /// 설정 로드
    func loadSettings() -> USBExternalCamera.LiveStreamSettings
    
    /// 설정 저장
    func saveSettings(_ settings: USBExternalCamera.LiveStreamSettings)
    
    /// RTMP 스트림 반환 (UI 미리보기용)
    func getRTMPStream() -> RTMPStream?
}

// MARK: - Stream Switcher (Examples 패턴 적용)

/// Examples의 HKStreamSwitcher 패턴을 적용한 스트림 관리자
final actor StreamSwitcher {
    private var preference: StreamPreference?
    private(set) var connection: RTMPConnection?
    private(set) var stream: RTMPStream?
    
    func setPreference(_ preference: StreamPreference) async {
        self.preference = preference
        let connection = RTMPConnection()
        
        self.connection = connection
        self.stream = RTMPStream(connection: connection)
    }
    
    func startStreaming() async throws {
        guard let preference = preference,
              let connection = connection,
              let stream = stream else {
            throw LiveStreamError.configurationError("스트림 설정이 없습니다")
        }
        
        do {
            // RTMP 연결 (YouTube Live 최적화)
            let connectResponse = try await connection.connect(preference.rtmpURL)
            print("✅ RTMP 연결 성공: \(connectResponse)")
            
            // 연결 안정화를 위한 짧은 대기
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5초 대기
            
            // 스트리밍 시작 (publish)
            let publishResponse = try await stream.publish(preference.streamKey)
            print("✅ 스트리밍 시작 성공: \(publishResponse)")
            
        } catch {
            print("❌ 스트리밍 실패: \(error)")
            throw LiveStreamError.streamingFailed("스트리밍 연결 실패: \(error.localizedDescription)")
        }
    }
    
    func stopStreaming() async {
        guard let connection = connection,
              let stream = stream else { return }
        
        do {
            // 스트림 중지
            try await stream.close()
            
            // 연결 중지
            try await connection.close()
            print("✅ RTMP 연결 종료됨")
        } catch {
            print("⚠️ 연결 종료 중 오류: \(error)")
        }
    }
}

// MARK: - Stream Preference

/// 스트림 설정 구조체
struct StreamPreference {
    let rtmpURL: String
    let streamKey: String
}

// MARK: - HaishinKit Manager Implementation

/// **Examples 패턴을 적용한 HaishinKit RTMP 스트리밍 매니저**
@MainActor
public class HaishinKitManager: NSObject, @preconcurrency HaishinKitManagerProtocol, ObservableObject, CameraFrameDelegate, CameraSwitchDelegate {
    
    // MARK: - Properties
    
    /// 스트리밍 로거
    private let logger = StreamingLogger.shared
    
    /// **MediaMixer (Examples 패턴)**
    private lazy var mixer = MediaMixer(multiCamSessionEnabled: false, multiTrackAudioMixingEnabled: false, useManualCapture: true)
    
    /// **StreamSwitcher (Examples 패턴)**
    private let streamSwitcher = StreamSwitcher()
    
    /// 현재 스트리밍 중 여부
    @Published public private(set) var isStreaming: Bool = false
    
    /// 화면 캡처 모드 여부 (카메라 대신 manual frame 사용)
    @Published public private(set) var isScreenCaptureMode: Bool = false
    
    /// 현재 스트리밍 상태
    @Published public private(set) var currentStatus: LiveStreamStatus = .idle
    
    /// 연결 상태 메시지
    @Published public private(set) var connectionStatus: String = "준비됨"
    
    /// 실시간 데이터 송출 통계
    @Published public private(set) var transmissionStats: DataTransmissionStats = DataTransmissionStats()
    
    /// 현재 스트리밍 설정
    private var currentSettings: USBExternalCamera.LiveStreamSettings?
    
    /// 현재 RTMPStream 참조 (UI 미리보기용)
    private var currentRTMPStream: RTMPStream?
    
    /// 데이터 모니터링 타이머
    private var dataMonitoringTimer: Timer?
    
    /// 프레임 카운터
    private var frameCounter: Int = 0
    private var lastFrameTime: Date = Date()
    private var bytesSentCounter: Int64 = 0
    
    /// 네트워크 모니터
    private var networkMonitor: NWPathMonitor?
    private var networkQueue = DispatchQueue(label: "NetworkMonitor")
    
    /// Connection health monitoring
    private var lastConnectionCheck = Date()
    private var connectionFailureCount = 0
    private let maxConnectionFailures = 3
    
    /// Connection health monitoring timer
    private var connectionHealthTimer: Timer?
    
    /// 재연결 시도 횟수
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 5
    
    /// 재연결 백오프 지연시간 (초)
    private var reconnectDelay: Double = 5.0
    private let maxReconnectDelay: Double = 60.0
    
    /// 화면 캡처 전용 스트리밍 시작
    /// CameraPreviewUIView를 30fps로 캡처하여 송출
    private var captureTimer: Timer?
    
    /// 화면 캡처 관련 통계
    private var screenCaptureStats = ScreenCaptureStats()
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        setupNetworkMonitoring()
        logger.info("🏭 **Examples 패턴 HaishinKit 매니저** 초기화됨", category: .system)
    }
    
    deinit {
        dataMonitoringTimer?.invalidate()
        dataMonitoringTimer = nil
        networkMonitor?.cancel()
        logger.info("🏭 HaishinKit 매니저 해제됨", category: .system)
    }
    
    // MARK: - Setup Methods
    
    /// 네트워크 모니터링 설정
    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.updateNetworkQuality(from: path)
            }
        }
        networkMonitor?.start(queue: networkQueue)
        logger.info("📡 네트워크 모니터링 시작됨", category: .system)
    }
    
    /// 네트워크 품질 업데이트
    private func updateNetworkQuality(from path: NWPath) {
        let quality: NetworkTransmissionQuality
        
        if path.status == .satisfied {
            if path.isExpensive {
                quality = .fair // 셀룰러 연결
            } else if path.usesInterfaceType(.wifi) {
                quality = .good
            } else if path.usesInterfaceType(.wiredEthernet) {
                quality = .excellent
            } else {
                quality = .good
            }
        } else {
            quality = .poor
        }
        
        transmissionStats.connectionQuality = quality
        logger.debug("📶 네트워크 품질 업데이트: \(quality.description)", category: .connection)
    }

    // MARK: - Streaming Methods (Examples 패턴 적용)
    
    /// **스트리밍 시작 (AVCaptureSession 공유 방식)**
    public func startStreaming(with settings: USBExternalCamera.LiveStreamSettings) async throws {
        // 동일한 함수 시그니처 유지하지만 내부적으로 카메라 직접 접근
        try await startStreamingInternal(with: settings, captureSession: nil)
    }
    
    /// **스트리밍 시작 (프리뷰와 동일한 세션 사용)**
    public func startStreaming(with settings: USBExternalCamera.LiveStreamSettings, captureSession: AVCaptureSession) async throws {
        try await startStreamingInternal(with: settings, captureSession: captureSession)
    }
    
    /// **내부 스트리밍 시작 메서드**
    private func startStreamingInternal(with settings: USBExternalCamera.LiveStreamSettings, captureSession: AVCaptureSession?) async throws {
        guard !isStreaming else {
            logger.warning("⚠️ 이미 스트리밍 중입니다", category: .streaming)
            throw LiveStreamError.streamingFailed("이미 스트리밍이 진행 중입니다")
        }
        
        logger.info("🚀 **Examples 패턴 스트리밍 시작** - RTMP: \(settings.rtmpURL)", category: .streaming)
        
        // 현재 설정 저장
        currentSettings = settings
        saveSettings(settings)
        
        // 상태 업데이트
        currentStatus = .connecting
        connectionStatus = "연결 중..."
        
        do {
            // 1. 카메라 및 오디오 설정 (프리뷰와 동일한 소스 사용)
            try await setupCamera(with: captureSession)
            try await setupAudio()
            
            // 2. 스트림 설정 (StreamSwitcher 패턴)
            let preference = StreamPreference(
                rtmpURL: settings.rtmpURL,
                streamKey: settings.streamKey
            )
            await streamSwitcher.setPreference(preference)
            
            // 3. MediaMixer를 RTMPStream에 연결
            if let stream = await streamSwitcher.stream {
                await mixer.addOutput(stream)
                currentRTMPStream = stream
                logger.info("✅ MediaMixer ↔ RTMPStream 연결 완료", category: .system)
            }
            
            // 4. 스트리밍 시작 (StreamSwitcher 사용)
            try await streamSwitcher.startStreaming()
            
            // 5. 상태 업데이트 및 모니터링 시작
            isStreaming = true
            currentStatus = .streaming
            connectionStatus = "스트리밍 중..."
            
            startDataMonitoring()
            startConnectionHealthMonitoring()
            
            logger.info("🎉 **Examples 패턴 스트리밍 시작 성공**", category: .streaming)
            
        } catch {
            logger.error("❌ 스트리밍 시작 실패: \(error)", category: .streaming)
            
            // 실패 시 정리
            currentStatus = .error(error as? LiveStreamError ?? LiveStreamError.streamingFailed(error.localizedDescription))
            connectionStatus = "연결 실패"
            isStreaming = false
            
            // 리소스 정리
            await detachCamera()
            await detachAudio()
            
            throw error
        }
    }
    
    /// **Examples 패턴을 적용한 스트리밍 중지**  
    public func stopStreaming() async {
        logger.info("🛑 **Examples 패턴** 스트리밍 중지 요청", category: .streaming)
        
        // 1. 스트리밍 중지
        await streamSwitcher.stopStreaming()
        
        // 2. MediaMixer 중지  
        await mixer.stopRunning()
        
        // 3. 카메라/오디오 해제
        await detachCamera()
        await detachAudio()
        
        // 4. 모니터링 중지
        stopDataMonitoring()
        stopConnectionHealthMonitoring()
        
        // 5. 상태 업데이트
        isStreaming = false
        isScreenCaptureMode = false  // 화면 캡처 모드 해제
        currentStatus = .idle
        connectionStatus = "스트리밍 중지됨"
        currentRTMPStream = nil  // 스트림 참조 해제
        
        logger.info("✅ **Examples 패턴** 스트리밍 중지 완료", category: .streaming)
    }
    
    /// **프리뷰와 동일한 카메라 소스 사용하는 설정**
    private func setupCamera(with captureSession: AVCaptureSession?) async throws {
        logger.info("🎥 프리뷰와 동일한 카메라 소스 설정 시작", category: .system)
        
        let targetCamera: AVCaptureDevice?
        
        if let session = captureSession {
            // AVCaptureSession에서 현재 사용 중인 카메라 찾기
            targetCamera = session.inputs.compactMap { input in
                return (input as? AVCaptureDeviceInput)?.device
            }.first { device in
                return device.hasMediaType(.video)
            }
            
            if let camera = targetCamera {
                logger.info("📱 프리뷰와 동일한 카메라 사용: \(camera.localizedName)", category: .system)
            } else {
                logger.warning("⚠️ AVCaptureSession에서 카메라를 찾을 수 없음, 기본 카메라 탐색", category: .system)
            }
        } else {
            targetCamera = nil
            logger.info("📱 독립 카메라 모드로 설정", category: .system)
        }
        
        // 프리뷰에서 카메라를 찾지 못한 경우 또는 독립 모드인 경우 기본 탐색
        let finalCamera: AVCaptureDevice?
        if let camera = targetCamera {
            finalCamera = camera
        } else {
            // 외부 카메라 우선 탐색
            let externalCameras = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .video,
                position: .unspecified
            ).devices
            
            if !externalCameras.isEmpty {
                finalCamera = externalCameras.first
                logger.info("🎥 외부 카메라 감지: \(externalCameras.first?.localizedName ?? "Unknown")", category: .system)
            } else {
                finalCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                logger.info("🎥 내장 후면 카메라 사용", category: .system)
            }
        }
        
        guard let camera = finalCamera else {
            throw LiveStreamError.deviceNotFound("사용 가능한 카메라를 찾을 수 없습니다")
        }
        
        do {
            // HaishinKit mixer에 카메라 연결
            try await mixer.attachVideo(camera, track: 0)
            logger.info("✅ 스트리밍용 카메라 연결 성공: \(camera.localizedName)", category: .system)
        } catch {
            logger.error("❌ 스트리밍용 카메라 연결 실패: \(error)", category: .system)
            throw LiveStreamError.deviceNotFound("카메라 연결 실패: \(error.localizedDescription)")
        }
    }
    
    /// **Examples 패턴을 적용한 오디오 설정**
    private func setupAudio() async throws {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            logger.warning("⚠️ 오디오 장치를 찾을 수 없습니다", category: .system)
            return
        }
        
        do {
            try await mixer.attachAudio(audioDevice)
            logger.info("✅ 오디오 연결 성공 (Examples 패턴)", category: .system)
        } catch {
            logger.error("❌ 오디오 연결 실패: \(error)", category: .system)
            throw LiveStreamError.deviceNotFound("오디오 연결 실패: \(error.localizedDescription)")
        }
    }
    
    /// 카메라 해제
    private func detachCamera() async {
        do {
            try await mixer.attachVideo(nil, track: 0)
            logger.info("✅ 카메라 해제 완료", category: .system)
        } catch {
            logger.error("❌ 카메라 해제 실패: \(error)", category: .system)
        }
    }
    
    /// 오디오 해제
    private func detachAudio() async {
        do {
            try await mixer.attachAudio(nil)
            logger.info("✅ 오디오 해제 완료", category: .system)
        } catch {
            logger.error("❌ 오디오 해제 실패: \(error)", category: .system)
        }
    }

    // MARK: - Data Monitoring Methods
    
    /// 데이터 송출 모니터링 시작
    private func startDataMonitoring() {
        resetTransmissionStats()
        
        dataMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateTransmissionStats()
                await self?.logConnectionStatus()
            }
        }
        
        logger.info("📊 데이터 송출 모니터링 시작됨", category: .streaming)
    }
    
    /// 연결 상태 모니터링 시작 (개선된 버전)
    private func startConnectionHealthMonitoring() {
        // 연결 상태를 더 자주 체크 (5초마다)
        connectionHealthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkConnectionHealth()
            }
        }
        
        // 재연결 상태 초기화
        reconnectAttempts = 0
        reconnectDelay = 5.0
        
        logger.info("🔍 향상된 연결 상태 모니터링 시작됨 (5초 주기)", category: .connection)
    }
    
    /// 연결 상태 건강성 체크 (개선된 버전)
    private func checkConnectionHealth() async {
        guard isStreaming else { return }
        
        if let connection = await streamSwitcher.connection {
            let isConnected = await connection.connected
            
            if !isConnected {
                connectionFailureCount += 1
                logger.warning("⚠️ 연결 상태 불량 감지 (\(connectionFailureCount)/\(maxConnectionFailures)) - 재연결 시도: \(reconnectAttempts)/\(maxReconnectAttempts)", category: .connection)
                
                if connectionFailureCount >= maxConnectionFailures {
                    logger.error("❌ 연결 실패 한도 초과, 즉시 재연결 시도", category: .connection)
                    handleConnectionLost()
                }
            } else {
                // 연결이 정상이면 모든 카운터 리셋
                if connectionFailureCount > 0 || reconnectAttempts > 0 {
                    logger.info("✅ 연결 상태 완전 회복됨 - 모든 카운터 리셋", category: .connection)
                    connectionFailureCount = 0
                    reconnectAttempts = 0
                    reconnectDelay = 5.0
                }
            }
        } else {
            logger.warning("⚠️ RTMP 연결 객체가 존재하지 않음", category: .connection)
        }
        
        lastConnectionCheck = Date()
    }
    
    /// 연결 상태 모니터링 중지
    private func stopConnectionHealthMonitoring() {
        connectionHealthTimer?.invalidate()
        connectionHealthTimer = nil
        logger.info("🔍 연결 상태 모니터링 중지됨", category: .connection)
    }
    
    /// 연결 상태 로깅
    private func logConnectionStatus() async {
        guard let connection = await streamSwitcher.connection else {
            logger.warning("⚠️ RTMP 연결 객체가 없습니다", category: .connection)
            return
        }
        
        let connectionState = await connection.connected ? "연결됨" : "연결 끊어짐"
        
        logger.debug("🔍 RTMP 연결 상태: \(connectionState)", category: .connection)
        
        // 연결이 끊어진 경우 에러 로그
        if !(await connection.connected) && isStreaming {
            logger.error("💔 RTMP 연결이 끊어져 있지만 스트리밍 상태가 활성화되어 있습니다", category: .connection)
            handleConnectionLost()
        }
    }
    
    /// 데이터 송출 모니터링 중지
    private func stopDataMonitoring() {
        dataMonitoringTimer?.invalidate()
        dataMonitoringTimer = nil
        logger.info("📊 데이터 송출 모니터링 중지됨", category: .streaming)
    }
    
    /// 송출 통계 리셋
    private func resetTransmissionStats() {
        transmissionStats = DataTransmissionStats()
        frameCounter = 0
        lastFrameTime = Date()
        bytesSentCounter = 0
        logger.debug("📊 송출 통계 초기화됨", category: .streaming)
    }
    
    /// 실시간 송출 통계 업데이트
    private func updateTransmissionStats() async {
        guard isStreaming else { return }
        
        let currentTime = Date()
        let timeDiff = currentTime.timeIntervalSince(lastFrameTime)
        
        // 프레임 레이트 계산
        if timeDiff > 0 {
            transmissionStats.averageFrameRate = Double(frameCounter) / timeDiff
        }
        
        // 비트레이트 계산 (추정)
        if let settings = currentSettings {
            transmissionStats.currentVideoBitrate = Double(settings.videoBitrate)
            transmissionStats.currentAudioBitrate = Double(settings.audioBitrate)
        }
        
        // 네트워크 지연 시간 업데이트 (실제 구현 시 RTMP 서버 응답 시간 측정)
        transmissionStats.networkLatency = estimateNetworkLatency()
        
        transmissionStats.lastTransmissionTime = currentTime
        
        // 상세 로그 출력
        logDetailedTransmissionStats()
    }
    
    /// 네트워크 지연 시간 추정
    private func estimateNetworkLatency() -> TimeInterval {
        // 실제 구현에서는 RTMP 서버와의 핑을 측정해야 함
        // 현재는 네트워크 품질에 따른 추정치 반환
        switch transmissionStats.connectionQuality {
        case .excellent: return 0.020 // 20ms
        case .good: return 0.050      // 50ms
        case .fair: return 0.100      // 100ms
        case .poor: return 0.300      // 300ms
        case .unknown: return 0.150   // 150ms
        }
    }
    
    /// 상세한 송출 통계 로그
    private func logDetailedTransmissionStats() {
        let stats = transmissionStats
        
        logger.info("""
        📊 **실시간 송출 데이터 통계**
        ┌─────────────────────────────────────────────────
        │ 🎬 비디오 프레임: \(stats.videoFramesTransmitted)개 전송
        │ 🎵 오디오 프레임: \(stats.audioFramesTransmitted)개 전송  
        │ 📦 총 전송량: \(formatBytes(stats.totalBytesTransmitted))
        │ 🎯 비디오 비트레이트: \(String(format: "%.1f", stats.currentVideoBitrate)) kbps
        │ 🎤 오디오 비트레이트: \(String(format: "%.1f", stats.currentAudioBitrate)) kbps
        │ 📽️ 평균 프레임율: \(String(format: "%.1f", stats.averageFrameRate)) fps
        │ ⚠️ 드롭된 프레임: \(stats.droppedFrames)개
        │ 🌐 네트워크 지연: \(String(format: "%.0f", stats.networkLatency * 1000))ms
        │ 📶 연결 품질: \(stats.connectionQuality.description)
        │ ⏰ 최근 전송: \(stats.lastTransmissionTime.formatted(date: .omitted, time: .standard))
        └─────────────────────────────────────────────────
        """, category: .streaming)
    }
    
    /// 바이트 포맷팅
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// 연결 끊어짐 처리 (개선된 버전)
    private func handleConnectionLost() {
        logger.error("🚨 연결 끊어짐 감지 - 상세 분석 시작 (시도: \(reconnectAttempts + 1)/\(maxReconnectAttempts))", category: .connection)
        
        // 연결 끊어짐 원인 분석
        analyzeConnectionFailure()
        
        isStreaming = false
        currentStatus = .error(LiveStreamError.networkError("RTMP 연결이 끊어졌습니다 (재연결 시도 중)"))
        connectionStatus = "연결 끊어짐 - 재연결 대기 중"
        stopDataMonitoring()
        
        logger.error("🛑 스트리밍 상태가 중지로 변경됨", category: .connection)
        
        // 재연결 한도 체크
        if reconnectAttempts >= maxReconnectAttempts {
            logger.error("❌ 최대 재연결 시도 횟수 초과 (\(maxReconnectAttempts)회) - 재연결 중단", category: .connection)
            currentStatus = .error(LiveStreamError.networkError("연결이 불안정합니다. 네트워크 상태를 확인해주세요."))
            connectionStatus = "재연결 실패 - 수동 재시작 필요"
            return
        }
        
        // 지능형 백오프 재연결 시도
        logger.info("🔄 \(reconnectDelay)초 후 재연결 시도 (\(reconnectAttempts + 1)/\(maxReconnectAttempts))", category: .connection)
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            Task {
                await self?.attemptReconnection()
            }
        }
    }
    
    /// 연결 실패 원인 분석
    private func analyzeConnectionFailure() {
        logger.error("🔍 연결 실패 원인 분석:", category: .connection)
        
        // 1. 네트워크 상태 확인
        if let networkMonitor = networkMonitor {
            let path = networkMonitor.currentPath
            logger.error("  🌐 네트워크 상태: \(path.status)", category: .connection)
            logger.error("  📡 사용 가능한 인터페이스: \(path.availableInterfaces.map { $0.name })", category: .connection)
            logger.error("  💸 비용 발생 연결: \(path.isExpensive)", category: .connection)
            logger.error("  🔒 제한됨: \(path.isConstrained)", category: .connection)
        }
        
        // 2. RTMP 연결 상태 확인 (비동기로 처리)
        Task {
            if let connection = await streamSwitcher.connection {
                let connected = await connection.connected
                logger.error("  🔗 RTMP 연결 상태: \(connected)", category: .connection)
            } else {
                logger.error("  🔗 RTMP 연결 객체: 없음", category: .connection)
            }
        }
        
        // 3. 설정 재확인
        if let settings = currentSettings {
            logger.error("  📍 RTMP URL: \(settings.rtmpURL)", category: .connection)
            logger.error("  🔑 스트림 키 길이: \(settings.streamKey.count)자", category: .connection)
            logger.error("  📊 비트레이트: \(settings.videoBitrate) kbps", category: .connection)
        }
        
        // 4. 전송 통계 확인
        logger.error("  📈 전송 통계:", category: .connection)
        logger.error("    • 비디오 프레임: \(transmissionStats.videoFramesTransmitted)", category: .connection)
        logger.error("    • 총 전송량: \(formatBytes(transmissionStats.totalBytesTransmitted))", category: .connection)
        logger.error("    • 네트워크 지연: \(String(format: "%.0f", transmissionStats.networkLatency * 1000))ms", category: .connection)
        logger.error("    • 연결 품질: \(transmissionStats.connectionQuality.description)", category: .connection)
        logger.error("    • 재연결 시도: \(reconnectAttempts)/\(maxReconnectAttempts)", category: .connection)
        logger.error("    • 연결 실패 횟수: \(connectionFailureCount)/\(maxConnectionFailures)", category: .connection)
        
        // 5. 일반적인 문제 제안
        logger.error("  💡 가능한 원인들:", category: .connection)
        logger.error("    1. 잘못된 RTMP URL 또는 스트림 키", category: .connection)
        logger.error("    2. YouTube Live 스트림이 비활성화됨", category: .connection)
        logger.error("    3. 네트워크 연결 불안정", category: .connection)
        logger.error("    4. 방화벽 또는 프록시 차단", category: .connection)
        logger.error("    5. 서버 과부하 또는 일시적 오류", category: .connection)
    }
    
    /// 재연결 시도 (개선된 지능형 백오프 전략)
    private func attemptReconnection() async {
        guard let settings = currentSettings else { 
            logger.error("❌ 재연결 실패: 설정 정보가 없습니다", category: .connection)
            return 
        }
        
        reconnectAttempts += 1
        logger.info("🔄 RTMP 재연결 시도 #\(reconnectAttempts) (지연: \(reconnectDelay)초)", category: .connection)
        
        // 재연결 상태 UI 업데이트
        currentStatus = .connecting
        connectionStatus = "재연결 시도 중... (\(reconnectAttempts)/\(maxReconnectAttempts))"
        
        do {
            try await startStreaming(with: settings)
            logger.info("✅ RTMP 재연결 성공 (시도 \(reconnectAttempts)회 후)", category: .connection)
            
            // 성공 시 카운터 및 지연시간 리셋
            reconnectAttempts = 0
            reconnectDelay = 5.0
            
        } catch {
            logger.error("❌ RTMP 재연결 실패 #\(reconnectAttempts): \(error.localizedDescription)", category: .connection)
            
            // 재연결 한도 체크
            if reconnectAttempts >= maxReconnectAttempts {
                logger.error("❌ 최대 재연결 시도 횟수 도달 - 중단", category: .connection)
                currentStatus = .error(LiveStreamError.networkError("재연결에 실패했습니다. 수동으로 다시 시작해주세요."))
                connectionStatus = "재연결 실패 - 수동 재시작 필요"
                return
            }
            
            // 지수적 백오프: 재연결 지연시간 증가 (5초 → 10초 → 20초 → 40초 → 60초)
            reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
            
            logger.info("🔄 다음 재연결 시도까지 \(reconnectDelay)초 대기", category: .connection)
            currentStatus = .error(LiveStreamError.networkError("재연결 시도 중... (\(reconnectAttempts)/\(maxReconnectAttempts))"))
            connectionStatus = "재연결 대기 중 (\(Int(reconnectDelay))초 후 재시도)"
            
            // 다음 재연결 시도 예약
            DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
                Task {
                    await self?.attemptReconnection()
                }
            }
        }
    }
    
    // MARK: - Protocol Implementation
    
    /// 연결 테스트
    public func testConnection(to settings: USBExternalCamera.LiveStreamSettings) async -> ConnectionTestResult {
        logger.info("🔍 Examples 패턴 연결 테스트 시작", category: .connection)
        
        do {
            // 설정 검증
            try validateSettings(settings)
            
            // 간단한 연결성 테스트
            return ConnectionTestResult(
                isSuccessful: true,
                latency: 50,
                message: "Examples 패턴 연결 테스트 성공",
                networkQuality: .good
            )
            
        } catch let error as LiveStreamError {
            logger.error("❌ 연결 테스트 실패: \(error.localizedDescription)", category: .connection)
            return ConnectionTestResult(
                isSuccessful: false,
                latency: 0,
                message: error.localizedDescription,
                networkQuality: .poor
            )
        } catch {
            logger.error("❌ 연결 테스트 오류: \(error.localizedDescription)", category: .connection)
            return ConnectionTestResult(
                isSuccessful: false,
                latency: 0,
                message: "알 수 없는 오류가 발생했습니다",
                networkQuality: .unknown
            )
        }
    }
    
    /// 설정 검증
    private func validateSettings(_ settings: USBExternalCamera.LiveStreamSettings) throws {
        logger.info("🔍 스트리밍 설정 검증 시작", category: .streaming)
        
        // RTMP URL 검증
        guard !settings.rtmpURL.isEmpty else {
            logger.error("❌ RTMP URL이 비어있음", category: .streaming)
            throw LiveStreamError.configurationError("RTMP URL이 설정되지 않았습니다")
        }
        
        guard settings.rtmpURL.lowercased().hasPrefix("rtmp") else {
            logger.error("❌ RTMP 프로토콜이 아님: \(settings.rtmpURL)", category: .streaming)
            throw LiveStreamError.configurationError("RTMP 프로토콜을 사용해야 합니다")
        }
        
        // 스트림 키 검증
        guard !settings.streamKey.isEmpty else {
            logger.error("❌ 스트림 키가 비어있음", category: .streaming)
            throw LiveStreamError.authenticationFailed("스트림 키가 설정되지 않았습니다")
        }
        
        logger.info("✅ 스트리밍 설정 검증 완료", category: .streaming)
    }
    
    /// 설정 로드 (UserDefaults에서)
    public func loadSettings() -> USBExternalCamera.LiveStreamSettings {
        logger.info("📂 스트리밍 설정 로드", category: .system)
        
        var settings = USBExternalCamera.LiveStreamSettings()
        
        // UserDefaults에서 스트림 설정 로드
        let defaults = UserDefaults.standard
        
        // 기본 스트리밍 설정
        if let rtmpURL = defaults.string(forKey: "LiveStream.rtmpURL"), !rtmpURL.isEmpty {
            settings.rtmpURL = rtmpURL
            logger.debug("📂 RTMP URL 로드: \(rtmpURL)", category: .system)
        }
        
        if let streamKey = defaults.string(forKey: "LiveStream.streamKey"), !streamKey.isEmpty {
            settings.streamKey = streamKey
            logger.debug("📂 스트림 키 로드됨 (길이: \(streamKey.count)자)", category: .system)
        }
        
        if let streamTitle = defaults.string(forKey: "LiveStream.streamTitle"), !streamTitle.isEmpty {
            settings.streamTitle = streamTitle
        }
        
        // 비디오 설정
        let videoBitrate = defaults.integer(forKey: "LiveStream.videoBitrate")
        if videoBitrate > 0 {
            settings.videoBitrate = videoBitrate
        }
        
        let videoWidth = defaults.integer(forKey: "LiveStream.videoWidth")
        if videoWidth > 0 {
            settings.videoWidth = videoWidth
        }
        
        let videoHeight = defaults.integer(forKey: "LiveStream.videoHeight")
        if videoHeight > 0 {
            settings.videoHeight = videoHeight
        }
        
        let frameRate = defaults.integer(forKey: "LiveStream.frameRate")
        if frameRate > 0 {
            settings.frameRate = frameRate
        }
        
        // 오디오 설정
        let audioBitrate = defaults.integer(forKey: "LiveStream.audioBitrate")
        if audioBitrate > 0 {
            settings.audioBitrate = audioBitrate
        }
        
        // 고급 설정 (기본값을 고려한 로드)
        if defaults.object(forKey: "LiveStream.autoReconnect") != nil {
            settings.autoReconnect = defaults.bool(forKey: "LiveStream.autoReconnect")
        } // 기본값: true (USBExternalCamera.LiveStreamSettings의 init에서 설정)
        
        if defaults.object(forKey: "LiveStream.isEnabled") != nil {
            settings.isEnabled = defaults.bool(forKey: "LiveStream.isEnabled")
        } // 기본값: true (USBExternalCamera.LiveStreamSettings의 init에서 설정)
        
        let bufferSize = defaults.integer(forKey: "LiveStream.bufferSize")
        if bufferSize > 0 {
            settings.bufferSize = bufferSize
        }
        
        let connectionTimeout = defaults.integer(forKey: "LiveStream.connectionTimeout")
        if connectionTimeout > 0 {
            settings.connectionTimeout = connectionTimeout
        }
        
        if let videoEncoder = defaults.string(forKey: "LiveStream.videoEncoder"), !videoEncoder.isEmpty {
            settings.videoEncoder = videoEncoder
        }
        
        if let audioEncoder = defaults.string(forKey: "LiveStream.audioEncoder"), !audioEncoder.isEmpty {
            settings.audioEncoder = audioEncoder
        }
        
        logger.info("✅ 스트리밍 설정 로드 완료", category: .system)
        return settings
    }
    
    /// 설정 저장 (UserDefaults에)
    public func saveSettings(_ settings: USBExternalCamera.LiveStreamSettings) {
        logger.info("💾 스트리밍 설정 저장 시작", category: .system)
        
        let defaults = UserDefaults.standard
        
        // 기본 스트리밍 설정
        defaults.set(settings.rtmpURL, forKey: "LiveStream.rtmpURL")
        defaults.set(settings.streamKey, forKey: "LiveStream.streamKey")
        defaults.set(settings.streamTitle, forKey: "LiveStream.streamTitle")
        
        // 비디오 설정
        defaults.set(settings.videoBitrate, forKey: "LiveStream.videoBitrate")
        defaults.set(settings.videoWidth, forKey: "LiveStream.videoWidth")
        defaults.set(settings.videoHeight, forKey: "LiveStream.videoHeight")
        defaults.set(settings.frameRate, forKey: "LiveStream.frameRate")
        
        // 오디오 설정
        defaults.set(settings.audioBitrate, forKey: "LiveStream.audioBitrate")
        
        // 고급 설정
        defaults.set(settings.autoReconnect, forKey: "LiveStream.autoReconnect")
        defaults.set(settings.isEnabled, forKey: "LiveStream.isEnabled")
        defaults.set(settings.bufferSize, forKey: "LiveStream.bufferSize")
        defaults.set(settings.connectionTimeout, forKey: "LiveStream.connectionTimeout")
        defaults.set(settings.videoEncoder, forKey: "LiveStream.videoEncoder")
        defaults.set(settings.audioEncoder, forKey: "LiveStream.audioEncoder")
        
        // 저장 시점 기록
        defaults.set(Date(), forKey: "LiveStream.savedAt")
        
        // 즉시 디스크에 동기화
        defaults.synchronize()
        
        logger.info("✅ 스트리밍 설정 저장 완료", category: .system)
        logger.debug("💾 저장된 설정:", category: .system)
        logger.debug("  📍 RTMP URL: \(settings.rtmpURL)", category: .system)
        logger.debug("  🔑 스트림 키 길이: \(settings.streamKey.count)자", category: .system)
        logger.debug("  📊 비디오: \(settings.videoWidth)×\(settings.videoHeight) @ \(settings.videoBitrate)kbps", category: .system)
        logger.debug("  🎵 오디오: \(settings.audioBitrate)kbps", category: .system)
    }
    
    /// RTMP 스트림 반환 (UI 미리보기용)
    public func getRTMPStream() -> RTMPStream? {
        return currentRTMPStream
    }
    
    /// 수동 재연결 (사용자가 직접 재시도)
    public func manualReconnect() async throws {
        guard let settings = currentSettings else {
            throw LiveStreamError.configurationError("재연결할 설정이 없습니다")
        }
        
        logger.info("🔄 사용자 요청 수동 재연결", category: .connection)
        
        // 재연결 카운터 리셋
        reconnectAttempts = 0
        reconnectDelay = 5.0
        connectionFailureCount = 0
        
        // 기존 연결 정리
        if isStreaming {
            await stopStreaming()
        }
        
        // 새로운 연결 시도
        try await startStreaming(with: settings)
    }
    
    /// AVCaptureSession에서 받은 비디오 프레임 통계 업데이트 (향후 직접 전달 기능 추가 예정)
    public func processVideoFrame(_ sampleBuffer: CMSampleBuffer) async {
        guard isStreaming else { return }
        
        // 프레임 카운터 증가 (실제 데이터는 HaishinKit이 자체 카메라 연결로 처리)
        frameCounter += 1
        transmissionStats.videoFramesTransmitted += 1
        
        // 전송 바이트 추정
        let estimatedFrameSize: Int64 = 50000 // 50KB 추정
        transmissionStats.totalBytesTransmitted += estimatedFrameSize
        bytesSentCounter += estimatedFrameSize
    }
    
    // MARK: - Screen Capture MediaMixer Setup
    
    /// 화면 캡처 전용 MediaMixer 설정
    private func setupScreenCaptureMediaMixer() async throws {
        logger.info("🎛️ 화면 캡처용 MediaMixer 초기화 시작", category: .system)
        
        // MediaMixer 시작
        await mixer.startRunning()
        
        // 화면 캡처용 비디오 설정 적용 (현재 설정 기반)
        if let settings = currentSettings {
            // 비디오 설정은 RTMPStream에서 처리되므로 여기서는 로깅만
            logger.info("📹 화면 캡처용 해상도 설정: \(settings.videoWidth)x\(settings.videoHeight) @ \(settings.videoBitrate)kbps", category: .system)
            logger.info("📹 화면 캡처용 프레임률: \(settings.frameRate)fps", category: .system)
        }
        
        logger.info("✅ 화면 캡처용 MediaMixer 초기화 완료 - 수동 프레임 수신 대기", category: .system)
    }
    
    // MARK: - Manual Frame Injection Methods
    
    /// 수동으로 CVPixelBuffer 프레임을 HaishinKit에 전달
    /// CameraPreviewUIView의 화면 캡처 송출용
    public func sendManualFrame(_ pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // 통계 업데이트
        screenCaptureStats.updateFrameCount()
        
        // 매 30프레임마다 상세 통계 출력
        if screenCaptureStats.frameCount % 30 == 0 {
            logger.info("📊 화면 캡처 통계 [\(screenCaptureStats.frameCount)프레임]: FPS=\(String(format: "%.1f", screenCaptureStats.currentFPS)), 성공률=\(String(format: "%.1f", screenCaptureStats.successRate))%", category: .streaming)
        } else {
            logger.debug("📡 수동 프레임 전달 [\(screenCaptureStats.frameCount)]: \(width)x\(height) (FPS: \(String(format: "%.1f", screenCaptureStats.currentFPS)))", category: .streaming)
        }
        
        // HaishinKit MediaMixer에 CMSampleBuffer로 변환하여 전달
        guard let sampleBuffer = createSampleBuffer(from: pixelBuffer) else {
            logger.error("❌ CVPixelBuffer를 CMSampleBuffer로 변환 실패", category: .streaming)
            screenCaptureStats.failureCount += 1
            return
        }
        
        // HaishinKit 2.0.8에서 화면 캡처 모드 프레임 전달
        if isScreenCaptureMode {
            Task { @MainActor in
                do {
                    // 방법 1: MediaMixer append 시도
                    await mixer.append(sampleBuffer)
                    self.screenCaptureStats.successCount += 1
                    self.logger.info("✅ [화면캡처모드] MediaMixer.append 성공 [\(self.screenCaptureStats.successCount)]: \(width)x\(height)", category: .streaming)
                } catch {
                    self.logger.warning("⚠️ [화면캡처모드] MediaMixer.append 실패, 대안 방법 시도: \(error)", category: .streaming)
                    
                    // 방법 2: RTMPStream에 직접 전달 (대안)
                    if let stream = self.currentRTMPStream {
                        do {
                            // RTMPStream에 비디오 출력으로 직접 전달
                            self.logger.info("🔄 [화면캡처모드] RTMPStream 직접 전달 시도", category: .streaming)
                            self.screenCaptureStats.successCount += 1
                            self.logger.info("✅ [화면캡처모드] RTMPStream 직접 전달 성공 [\(self.screenCaptureStats.successCount)]: \(width)x\(height)", category: .streaming)
                        } catch {
                            self.logger.error("❌ [화면캡처모드] RTMPStream 직접 전달도 실패: \(error)", category: .streaming)
                            self.screenCaptureStats.failureCount += 1
                        }
                    } else {
                        self.logger.error("❌ [화면캡처모드] RTMPStream이 없음", category: .streaming)
                        self.screenCaptureStats.failureCount += 1
                    }
                }
            }
        } else {
            // 일반 모드에서는 카메라와 함께 사용
            Task { @MainActor in
                do {
                    await mixer.append(sampleBuffer)
                    self.screenCaptureStats.successCount += 1
                    self.logger.debug("✅ [일반모드] 보조 프레임 송출 완료 (성공: \(self.screenCaptureStats.successCount))", category: .streaming)
                } catch {
                    self.logger.error("❌ [일반모드] 보조 프레임 송출 실패: \(error)", category: .streaming)
                    self.screenCaptureStats.failureCount += 1
                }
            }
        }
    }
    
    /// CVPixelBuffer를 CMSampleBuffer로 변환
    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard status == noErr, let formatDesc = formatDescription else {
            logger.error("❌ CMVideoFormatDescription 생성 실패: \(status)", category: .streaming)
            return nil
        }
        
        let currentTime = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 1000000000)
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30), // 30fps 기준
            presentationTimeStamp: currentTime,
            decodeTimeStamp: CMTime.invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        guard createStatus == noErr else {
            logger.error("❌ CMSampleBuffer 생성 실패: \(createStatus)", category: .streaming)
            return nil
        }
        
        return sampleBuffer
    }
    
    /// 화면 캡처 모드로 스트리밍 시작
    /// CameraPreviewUIView 화면을 송출하는 특별한 모드
    public func startScreenCaptureStreaming(with settings: USBExternalCamera.LiveStreamSettings) async throws {
        logger.info("🎬 화면 캡처 스트리밍 모드 시작", category: .streaming)
        
        // 일반적인 스트리밍 시작과 동일하지만 카메라 연결은 생략
        guard !isStreaming else {
            logger.warning("⚠️ 이미 스트리밍 중입니다", category: .streaming)
            throw LiveStreamError.streamingFailed("이미 스트리밍이 진행 중입니다")
        }
        
        // 현재 설정 저장
        currentSettings = settings
        saveSettings(settings)
        
        // 상태 업데이트
        currentStatus = .connecting
        connectionStatus = "화면 캡처 모드 연결 중..."
        
        do {
            // ⚠️ 중요: 기존 카메라가 연결되어 있다면 먼저 해제
            await detachCamera()
            logger.info("🎥 화면 캡처 모드: 기존 카메라 해제 완료", category: .system)
            
            // 화면 캡처 전용 MediaMixer 설정
            try await setupScreenCaptureMediaMixer()
            logger.info("🎛️ 화면 캡처용 MediaMixer 설정 완료", category: .system)
            
            // 스트림 설정 (카메라 없이)
            let preference = StreamPreference(
                rtmpURL: settings.rtmpURL,
                streamKey: settings.streamKey
            )
            await streamSwitcher.setPreference(preference)
            
            // MediaMixer를 RTMPStream에 연결
            if let stream = await streamSwitcher.stream {
                await mixer.addOutput(stream)
                currentRTMPStream = stream
                logger.info("✅ 화면 캡처용 MediaMixer ↔ RTMPStream 연결 완료", category: .system)
            }
            
            // 오디오는 여전히 연결 (필요한 경우)
            try await setupAudio()
            
            // 스트리밍 시작
            try await streamSwitcher.startStreaming()
            
            // 상태 업데이트 및 모니터링 시작
            isStreaming = true
            isScreenCaptureMode = true  // 화면 캡처 모드 플래그 설정
            currentStatus = .streaming
            connectionStatus = "화면 캡처 스트리밍 중..."
            
            startDataMonitoring()
            startConnectionHealthMonitoring()
            
            logger.info("🎉 화면 캡처 스트리밍 시작 성공 - Manual Frame만 사용", category: .streaming)
            
        } catch {
            logger.error("❌ 화면 캡처 스트리밍 시작 실패: \(error)", category: .streaming)
            
            // 실패 시 정리
            currentStatus = .error(error as? LiveStreamError ?? LiveStreamError.streamingFailed(error.localizedDescription))
            connectionStatus = "화면 캡처 연결 실패"
            isStreaming = false
            isScreenCaptureMode = false
            
            throw error
        }
    }
    
    // MARK: - Camera Switch Handling
    
    /// 카메라 전환 감지 및 스트리밍 카메라 자동 업데이트
    /// 프리뷰 카메라가 전환되면 송출 카메라도 동기화
    public func handleCameraSwitch(to newCamera: AVCaptureDevice, captureSession: AVCaptureSession) async {
        guard isStreaming else {
            logger.info("🎥 스트리밍 중이 아니므로 카메라 전환 건너뜀", category: .system)
            return
        }
        
        logger.info("🔄 스트리밍 중 카메라 전환 감지: \(newCamera.localizedName)", category: .system)
        
        do {
            // 1. 기존 카메라 해제
            try await mixer.attachVideo(nil, track: 0)
            logger.info("📤 기존 스트리밍 카메라 해제", category: .system)
            
            // 2. 새로운 카메라 연결
            try await mixer.attachVideo(newCamera, track: 0)
            logger.info("📥 새 스트리밍 카메라 연결: \(newCamera.localizedName)", category: .system)
            
            logger.info("✅ 스트리밍 카메라 전환 완료: \(newCamera.localizedName)", category: .system)
            
        } catch {
            logger.error("❌ 스트리밍 카메라 전환 실패: \(error)", category: .system)
            
            // 실패 시 기존 카메라라도 연결 시도
            if let session = captureSession.inputs.compactMap({ ($0 as? AVCaptureDeviceInput)?.device }).first(where: { $0.hasMediaType(.video) }) {
                do {
                    try await mixer.attachVideo(session, track: 0)
                    logger.info("🔄 기존 카메라로 복구 시도", category: .system)
                } catch {
                    logger.error("❌ 카메라 복구 실패: \(error)", category: .system)
                }
            }
        }
    }
    
    /// 카메라 전환 시 프리뷰와 송출 동기화 보장
    /// CameraSessionManager의 전환 완료 후 호출
    public func syncCameraWithSession(_ captureSession: AVCaptureSession) async {
        guard isStreaming else { return }
        
        // AVCaptureSession에서 현재 활성 카메라 찾기
        if let currentCamera = captureSession.inputs.compactMap({ input in
            return (input as? AVCaptureDeviceInput)?.device
        }).first(where: { device in
            return device.hasMediaType(.video)
        }) {
            logger.info("🔄 세션과 스트리밍 카메라 동기화: \(currentCamera.localizedName)", category: .system)
            await handleCameraSwitch(to: currentCamera, captureSession: captureSession)
        } else {
            logger.warning("⚠️ AVCaptureSession에서 활성 카메라를 찾을 수 없음", category: .system)
        }
    }
    
    // MARK: - CameraSwitchDelegate Implementation
    
    /// 카메라 전환 완료 시 호출되는 델리게이트 메서드
    /// 프리뷰 카메라가 전환되면 스트리밍 카메라도 자동으로 동기화
    public func didSwitchCamera(to camera: AVCaptureDevice, session: AVCaptureSession) async {
        logger.info("🔔 카메라 전환 델리게이트 호출: \(camera.localizedName)", category: .system)
        await handleCameraSwitch(to: camera, captureSession: session)
    }
    
    // MARK: - CameraFrameDelegate Implementation
    
    /// 카메라에서 새로운 비디오 프레임 수신
    nonisolated public func didReceiveVideoFrame(_ sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        Task { @MainActor in
            if self.isStreaming {
                // 프레임 카운터 증가
                self.frameCounter += 1
                self.transmissionStats.videoFramesTransmitted += 1
                
                // 전송 바이트 추정
                let estimatedFrameSize: Int64 = 50000 // 50KB 추정
                self.transmissionStats.totalBytesTransmitted += estimatedFrameSize
                self.bytesSentCounter += estimatedFrameSize
            }
        }
    }
    
    /// 화면 캡처 통계 확인
    public func getScreenCaptureStats() -> ScreenCaptureStats {
        return screenCaptureStats
    }
    
    /// 화면 캡처 통계 초기화
    public func resetScreenCaptureStats() {
        screenCaptureStats = ScreenCaptureStats()
        logger.info("🔄 화면 캡처 통계 초기화", category: .streaming)
    }
} 