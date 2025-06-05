//
//  LiveStreamViewModel.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import Foundation
import SwiftUI
import SwiftData
import AVFoundation
import Combine

/// 라이브 스트리밍 뷰모델 (MVVM 아키텍처)
/// Services Layer를 통해 Data와 Network Layer에 접근하여 UI 상태를 관리합니다.
@MainActor
final class LiveStreamViewModel: ObservableObject {
    
    // MARK: - Constants
    
    private enum Constants {
        static let dataMonitoringInterval: TimeInterval = 5.0
        static let statusTransitionDelay: UInt64 = 500_000_000 // 0.5초
        static let minimumStreamKeyLength = 16
        static let youtubeRTMPURL = "rtmp://a.rtmp.youtube.com/live2/"
        static let defaultVideoBitrate = 2500
        static let defaultAudioBitrate = 128
        static let defaultVideoWidth = 1920
        static let defaultVideoHeight = 1080
        static let defaultFrameRate = 30
    }
    
    // MARK: - Published Properties
    
    /// 현재 라이브 스트리밍 설정
    @Published var settings: LiveStreamSettings
    
    /// 스트리밍 상태
    @Published var status: LiveStreamStatus = .idle
    
    /// 상태 메시지
    @Published var statusMessage: String = ""
    
    /// 스트림 통계 정보
    @Published var streamStats: StreamStats = StreamStats()
    
    /// 설정 뷰 표시 여부
    @Published var showingSettings: Bool = false
    
    /// 오류 알림 표시 여부
    @Published var showingErrorAlert: Bool = false
    
    /// 현재 오류 메시지
    @Published var currentErrorMessage: String = ""
    
    /// 스트리밍 가능 여부
    @Published var canStartStreaming: Bool = false
    
    /// 네트워크 권장 설정
    @Published var networkRecommendations: StreamingRecommendations?
    
    /// 연결 정보
    @Published var connectionInfo: ConnectionInfo?
    
    /// 연결 테스트 결과
    @Published var connectionTestResult: String = ""
    
    /// 현재 스트리밍 중인지 여부
    var isStreaming: Bool {
        return liveStreamService?.isStreaming == true
    }
    
    // MARK: - Computed Properties
    
    var streamingStatus: LiveStreamStatus {
        return status
    }
    
    var streamControlButtonText: String {
        switch status {
        case .idle:
            return NSLocalizedString("start_streaming", comment: "스트리밍 시작")
        case .connecting:
            return NSLocalizedString("connecting", comment: "연결 중")
        case .connected:
            return NSLocalizedString("start_streaming", comment: "스트리밍 시작")
        case .streaming:
            return NSLocalizedString("stop_streaming", comment: "스트리밍 중지")
        case .disconnecting:
            return NSLocalizedString("stopping", comment: "중지 중")
        case .error:
            return NSLocalizedString("start_streaming", comment: "스트리밍 시작")
        }
    }
    
    var isStreamControlButtonEnabled: Bool {
        switch status {
        case .connecting, .disconnecting:
            return false
        case .streaming, .connected:
            return true
        default:
            return canStartStreaming
        }
    }
    
    var streamControlButtonColor: Color {
        switch status {
        case .streaming:
            return .red
        case .connecting, .disconnecting:
            return .gray
        default:
            return .blue
        }
    }
    
    // MARK: - Dependencies
    
    /// 라이브 스트리밍 서비스 (Services Layer)
    private var liveStreamService: LiveStreamServiceProtocol!
    
    /// Combine 구독 저장소
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.settings = Self.createDefaultSettings()
        self.liveStreamService = ServiceFactory.createLiveStreamService()
        
        setupBindings()
        updateStreamingAvailability()
        loadInitialSettings()
        
        logInitializationInfo()
    }
    
    // MARK: - Public Methods - Streaming Control
    
    /// 라이브 스트리밍 시작
    /// - Parameter captureSession: 카메라 캡처 세션
    func startStreaming(with captureSession: AVCaptureSession) async {
        logInfo("Starting streaming...", category: .streaming)
        
        await updateStatus(.connecting, message: "스트리밍 연결 중...")
        startDataMonitoring()
        
        do {
            try await performStreamingStart(with: captureSession)
            await handleStreamingStartSuccess()
        } catch {
            await handleStreamingStartFailure(error)
        }
    }
    
    /// 라이브 스트리밍 중지
    func stopStreaming() async {
        logInfo("Stopping streaming...", category: .streaming)
        
        await updateStatus(.disconnecting, message: "스트리밍 종료 중...")
        
        do {
            try await performStreamingStop()
            await handleStreamingStopSuccess()
        } catch {
            await handleStreamingStopFailure(error)
        }
    }
    
    /// 스트리밍 토글 (시작/중지)
    /// - Parameter captureSession: 카메라 캡처 세션
    func toggleStreaming(with captureSession: AVCaptureSession) {
        logDebug("🎮 [TOGGLE] Current status: \(status)", category: .streaming)
        
        switch status {
        case .idle, .error:
            Task { await startStreaming(with: captureSession) }
        case .connected, .streaming:
            Task { await stopStreaming() }
        case .connecting, .disconnecting:
            logDebug("🎮 [TOGGLE] Ignoring - already in transition", category: .streaming)
        }
    }
    
    // MARK: - Public Methods - Settings
    
    /// 스트리밍 설정 저장
    func saveSettings() {
        logDebug("💾 [SETTINGS] Saving stream settings...", category: .streaming)
        // 설정 저장 로직 (UserDefaults, Core Data 등)
    }
    
    /// 연결 테스트
    func testConnection() async {
        logDebug("🔍 [TEST] Testing connection...", category: .streaming)
        
        await MainActor.run {
            self.connectionTestResult = "연결 테스트를 시작합니다..."
        }
        
        // 간단한 연결 테스트 시뮬레이션
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1초 대기
        
        let isValid = validateRTMPURL(settings.rtmpURL) && validateStreamKey(settings.streamKey)
        
        await MainActor.run {
            if isValid {
                self.connectionTestResult = "설정이 유효합니다. 스트리밍을 시작할 수 있습니다."
            } else {
                self.connectionTestResult = "설정에 문제가 있습니다. RTMP URL과 스트림 키를 확인해주세요."
            }
        }
    }
    
    /// 스트리밍 품질 프리셋 적용
    /// - Parameter preset: 적용할 프리셋
    func applyPreset(_ preset: StreamingPreset) {
        let presetSettings = Self.createPresetSettings(preset)
        settings.videoWidth = presetSettings.videoWidth
        settings.videoHeight = presetSettings.videoHeight
        settings.videoBitrate = presetSettings.videoBitrate
        settings.audioBitrate = presetSettings.audioBitrate
        settings.frameRate = presetSettings.frameRate
        settings.keyframeInterval = presetSettings.keyframeInterval
        settings.videoEncoder = presetSettings.videoEncoder
        settings.audioEncoder = presetSettings.audioEncoder
        
        updateStreamingAvailability()
    }
    
    /// 설정 초기화
    func resetToDefaults() {
        logDebug("🔄 [SETTINGS] Resetting to default settings...", category: .streaming)
        settings = LiveStreamSettings()
    }
    
    // MARK: - Public Methods - Validation
    
    /// 스트림 키 유효성 검사
    /// - Parameter streamKey: 검사할 스트림 키
    /// - Returns: 유효성 검사 결과
    func validateStreamKey(_ key: String) -> Bool {
        return !key.isEmpty && key.count >= Constants.minimumStreamKeyLength
    }
    
    /// RTMP URL 유효성 검사
    /// - Parameter url: 검사할 URL
    /// - Returns: 유효성 검사 결과
    func validateRTMPURL(_ url: String) -> Bool {
        return url.lowercased().hasPrefix("rtmp://") || url.lowercased().hasPrefix("rtmps://")
    }
    
    /// 예상 대역폭 계산
    /// - Returns: 예상 대역폭 (kbps)
    func calculateEstimatedBandwidth() -> Int {
        let totalBitrate = settings.videoBitrate + settings.audioBitrate
        let overhead = Int(Double(totalBitrate) * 0.1)
        return totalBitrate + overhead
    }
    
    // MARK: - Public Methods - Diagnostics
    
    /// YouTube 스트리밍 문제 진단
    /// - Returns: 진단 결과 목록
    func diagnoseYouTubeStreaming() async -> [String] {
        logDebug("🔍 [YOUTUBE DIAGNOSIS] Starting diagnosis...", category: .streaming)
        
        let permissionIssues = checkPermissionIssues()
        let deviceIssues = checkDeviceIssues()
        let settingsIssues = checkSettingsIssues()
        let streamingIssues = await checkStreamingIssues()
        
        return compileDiagnosticResults(
            permissionIssues: permissionIssues,
            deviceIssues: deviceIssues,
            settingsIssues: settingsIssues,
            streamingIssues: streamingIssues
        )
    }
    
    /// 카메라 권한 요청
    /// - Returns: 권한 허용 여부
    func requestCameraPermission() async -> Bool {
        logDebug("📸 [PERMISSION] Requesting camera permission...", category: .streaming)
        let status = await AVCaptureDevice.requestAccess(for: .video)
        print(status ? "✅ [PERMISSION] Camera allowed" : "❌ [PERMISSION] Camera denied")
        return status
    }
    
    /// 마이크 권한 요청
    /// - Returns: 권한 허용 여부
    func requestMicrophonePermission() async -> Bool {
        logDebug("🎤 [PERMISSION] Requesting microphone permission...", category: .streaming)
        let status = await AVCaptureDevice.requestAccess(for: .audio)
        print(status ? "✅ [PERMISSION] Microphone allowed" : "❌ [PERMISSION] Microphone denied")
        return status
    }
    
    /// 카메라 디바이스 목록 확인
    /// - Returns: 카메라 목록
    func checkAvailableCameras() -> [String] {
        logDebug("📹 [CAMERAS] Checking available cameras...", category: .streaming)
        
        let cameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
        
        return cameras.isEmpty ? 
            ["❌ 사용 가능한 카메라가 없습니다"] : 
            cameras.map { "📹 \($0.localizedName) (\($0.deviceType.rawValue))" }
    }
    
    /// 전체 시스템 진단
    /// - Returns: 진단 보고서
    func performFullSystemDiagnosis() async -> String {
        logDebug("🔍 [FULL DIAGNOSIS] Starting full system diagnosis...", category: .streaming)
        
        var report = "📊 USBExternalCamera 시스템 진단 보고서\n"
        report += "================================\n\n"
        
        report += generateBasicInfoSection()
        report += generatePermissionSection()
        report += generateDeviceSection()
        report += await generateYouTubeSection()
        report += generateRecommendationsSection()
        
        report += "================================\n"
        report += "📅 진단 완료: \(Date())\n"
        
        logDebug("🔍 [FULL DIAGNOSIS] Diagnosis complete", category: .streaming)
        return report
    }
    
    // MARK: - Public Methods - Data Monitoring
    
    /// 현재 스트리밍 데이터 송출 상태 확인
    @MainActor
    func checkCurrentDataTransmission() async {
        guard let service = liveStreamService,
              let transmissionStats = await service.getCurrentTransmissionStatus() else {
            logDebug("❌ [DATA CHECK] Unable to get transmission status", category: .streaming)
            return
        }
        
        logTransmissionStats(transmissionStats)
    }
    
    /// 스트리밍 데이터 요약 정보 가져오기
    @MainActor
    func getStreamingDataSummary() async -> String {
        guard let service = liveStreamService else {
            return "❌ LiveStreamService가 초기화되지 않음"
        }
        
        let summary = await service.getStreamingDataSummary()
        logDebug("📋 [DATA SUMMARY] \(summary)", category: .streaming)
        return summary
    }
    
    /// 실시간 데이터 모니터링 시작 (정기적 체크)
    @MainActor
    func startDataMonitoring() {
        logDebug("🚀 [MONITOR] Starting data monitoring", category: .streaming)
        
        Timer.scheduledTimer(withTimeInterval: Constants.dataMonitoringInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            Task { @MainActor in
                if self.isStreaming {
                    await self.checkCurrentDataTransmission()
                } else {
                    logDebug("⏹️ [MONITOR] Stopping monitoring - streaming ended", category: .streaming)
                    timer.invalidate()
                }
            }
        }
    }
    
    // MARK: - Private Methods - Setup
    
    private static func createDefaultSettings() -> LiveStreamSettings {
        let settings = LiveStreamSettings()
        settings.rtmpURL = Constants.youtubeRTMPURL
        settings.streamKey = "f98q-9wq6-dfj9-hx3x-1ux8"
        settings.videoBitrate = Constants.defaultVideoBitrate
        settings.audioBitrate = Constants.defaultAudioBitrate
        settings.videoWidth = Constants.defaultVideoWidth
        settings.videoHeight = Constants.defaultVideoHeight
        settings.frameRate = Constants.defaultFrameRate
        return settings
    }
    
    private static func createPresetSettings(_ preset: StreamingPreset) -> LiveStreamSettings {
        let settings = LiveStreamSettings()
        
        switch preset {
        case .low:
            settings.videoWidth = 1280
            settings.videoHeight = 720
            settings.videoBitrate = 1500
            settings.frameRate = 30
        case .standard:
            settings.videoWidth = 1920
            settings.videoHeight = 1080
            settings.videoBitrate = 2500
            settings.frameRate = 30
        case .high:
            settings.videoWidth = 1920
            settings.videoHeight = 1080
            settings.videoBitrate = 4500
            settings.frameRate = 60
        case .ultra:
            settings.videoWidth = 3840
            settings.videoHeight = 2160
            settings.videoBitrate = 8000
            settings.frameRate = 60
        }
        
        settings.audioBitrate = preset == .ultra ? 256 : 128
        settings.keyframeInterval = 2
        settings.videoEncoder = "H.264"
        settings.audioEncoder = "AAC"
        
        return settings
    }
    
    private func setupBindings() {
        guard let service = liveStreamService as? LiveStreamService else { return }
        
        service.$currentStats
            .receive(on: DispatchQueue.main)
            .assign(to: \.streamStats, on: self)
            .store(in: &cancellables)
        
        service.$connectionInfo
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectionInfo, on: self)
            .store(in: &cancellables)
        
        service.$isStreaming
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isStreaming in
                self?.syncServiceStatus(isStreaming)
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialSettings() {
        guard let liveStreamService = liveStreamService else { return }
        
        Task {
            do {
                let loadedSettings = try await liveStreamService.loadSettings()
                if !loadedSettings.rtmpURL.isEmpty && !loadedSettings.streamKey.isEmpty {
                    await MainActor.run {
                        self.settings = loadedSettings
                        logDebug("🎥 [LOAD] Settings loaded from service", category: .streaming)
                    }
                }
                await MainActor.run {
                    self.updateStreamingAvailability()
                    self.updateNetworkRecommendations()
                }
            } catch {
                logDebug("🎥 [LOAD] Failed to load settings: \(error.localizedDescription)", category: .streaming)
                await MainActor.run {
                    self.updateStreamingAvailability()
                }
            }
        }
    }
    
    // MARK: - Private Methods - Streaming
    
    private func performStreamingStart(with captureSession: AVCaptureSession) async throws {
        guard let service = liveStreamService else {
            throw LiveStreamError.serviceNotInitialized
        }
        try await service.startStreaming(with: captureSession, settings: settings)
    }
    
    private func performStreamingStop() async throws {
        guard let service = liveStreamService else {
            throw LiveStreamError.serviceNotInitialized
        }
        try await service.stopStreaming()
    }
    
    private func handleStreamingStartSuccess() async {
        await updateStatus(.connected, message: "서버에 연결됨")
        try? await Task.sleep(nanoseconds: Constants.statusTransitionDelay)
        await updateStatus(.streaming, message: "YouTube Live 스트리밍 중")
        logDebug("✅ [STREAM] Streaming started successfully", category: .streaming)
    }
    
    private func handleStreamingStartFailure(_ error: Error) async {
        await updateStatus(.error, message: "스트리밍 시작 실패: \(error.localizedDescription)")
        logDebug("❌ [STREAM] Failed to start: \(error.localizedDescription)", category: .streaming)
    }
    
    private func handleStreamingStopSuccess() async {
        await updateStatus(.idle, message: "스트리밍이 종료되었습니다")
        logDebug("✅ [STREAM] Streaming stopped successfully", category: .streaming)
    }
    
    private func handleStreamingStopFailure(_ error: Error) async {
        await updateStatus(.idle, message: "스트리밍 종료 완료 (일부 정리 오류 무시됨)")
        logDebug("⚠️ [STREAM] Stopped with minor issues: \(error.localizedDescription)", category: .streaming)
    }
    
    // MARK: - Private Methods - Diagnostics
    
    private func checkPermissionIssues() -> (issues: [String], solutions: [String]) {
        var issues: [String] = []
        var solutions: [String] = []
        
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if cameraStatus != .authorized {
            issues.append("❌ 카메라 권한이 거부되었습니다")
            solutions.append("💡 설정 > 개인정보 보호 > 카메라에서 앱 권한을 허용하세요")
        }
        
        if micStatus != .authorized {
            issues.append("❌ 마이크 권한이 거부되었습니다")
            solutions.append("💡 설정 > 개인정보 보호 > 마이크에서 앱 권한을 허용하세요")
        }
        
        return (issues, solutions)
    }
    
    private func checkDeviceIssues() -> (issues: [String], solutions: [String]) {
        var issues: [String] = []
        var solutions: [String] = []
        
        let cameras = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
        
        if cameras.isEmpty {
            issues.append("❌ 사용 가능한 카메라가 없습니다")
            solutions.append("💡 USB 카메라 연결을 확인하거나 내장 카메라를 사용하세요")
        }
        
        return (issues, solutions)
    }
    
    private func checkSettingsIssues() -> (issues: [String], solutions: [String]) {
        var issues: [String] = []
        var solutions: [String] = []
        
        if settings.streamKey == "YOUR_YOUTUBE_STREAM_KEY_HERE" || settings.streamKey.isEmpty {
            issues.append("❌ YouTube 스트림 키가 설정되지 않았습니다")
            solutions.append("💡 YouTube Studio에서 실제 스트림 키를 복사하여 설정하세요")
        } else if settings.streamKey.count < Constants.minimumStreamKeyLength {
            issues.append("⚠️ 스트림 키가 너무 짧습니다 (\(settings.streamKey.count)자)")
            solutions.append("💡 YouTube 스트림 키는 일반적으로 20자 이상입니다")
        }
        
        return (issues, solutions)
    }
    
    private func checkStreamingIssues() async -> (issues: [String], solutions: [String]) {
        var issues: [String] = []
        var solutions: [String] = []
        
        if status == .streaming {
            if let service = liveStreamService,
               let transmissionStats = await service.getCurrentTransmissionStatus() {
                
                if !transmissionStats.isTransmittingData {
                    issues.append("❌ RTMP 연결은 성공했지만 데이터가 전송되지 않고 있습니다")
                    solutions.append("💡 카메라와 마이크 연결을 확인하고 앱을 재시작하세요")
                }
                
                if transmissionStats.videoBytesPerSecond <= 0 {
                    issues.append("❌ 비디오 데이터가 전송되지 않고 있습니다")
                    solutions.append("💡 카메라 연결과 권한을 다시 확인하세요")
                }
                
                if transmissionStats.audioBytesPerSecond <= 0 {
                    issues.append("❌ 오디오 데이터가 전송되지 않고 있습니다")
                    solutions.append("💡 마이크 연결과 권한을 다시 확인하세요")
                }
            }
        } else {
            issues.append("❌ 현재 스트리밍 상태가 아닙니다 (상태: \(status))")
            solutions.append("💡 먼저 스트리밍을 시작하세요")
        }
        
        return (issues, solutions)
    }
    
    private func compileDiagnosticResults(
        permissionIssues: (issues: [String], solutions: [String]),
        deviceIssues: (issues: [String], solutions: [String]),
        settingsIssues: (issues: [String], solutions: [String]),
        streamingIssues: (issues: [String], solutions: [String])
    ) -> [String] {
        
        let allIssues = permissionIssues.issues + deviceIssues.issues + settingsIssues.issues + streamingIssues.issues
        let allSolutions = permissionIssues.solutions + deviceIssues.solutions + settingsIssues.solutions + streamingIssues.solutions
        
        var results: [String] = []
        
        if allIssues.isEmpty {
            results.append("✅ 모든 설정이 정상입니다")
            results.append("🔍 YouTube Studio에서 스트림 상태를 확인하세요")
            results.append("⏱️ 스트림이 나타나기까지 10-30초 정도 걸릴 수 있습니다")
        } else {
            results.append("🔍 발견된 문제:")
            results.append(contentsOf: allIssues)
            results.append("")
            results.append("💡 해결 방법:")
            results.append(contentsOf: allSolutions)
        }
        
        results.append("")
        results.append("📋 YouTube Studio 체크리스트:")
        results.append(contentsOf: getYouTubeChecklist())
        
        return results
    }
    
    private func getYouTubeChecklist() -> [String] {
        return [
            "YouTube Studio (studio.youtube.com)에서 '라이브 스트리밍' 메뉴를 확인하세요",
            "'스트림' 탭에서 '라이브 스트리밍 시작' 버튼을 눌렀는지 확인하세요",
            "스트림이 '대기 중' 상태인지 확인하세요",
            "채널에서 라이브 스트리밍 기능이 활성화되어 있는지 확인하세요",
            "휴대폰 번호 인증이 완료되어 있는지 확인하세요"
        ]
    }
    
    // MARK: - Private Methods - Report Generation
    
    private func generateBasicInfoSection() -> String {
        var section = "📱 기본 정보:\n"
        section += "   • 앱 상태: \(status)\n"
        section += "   • 스트리밍 가능: \(canStartStreaming ? "예" : "아니오")\n"
        section += "   • RTMP URL: \(settings.rtmpURL)\n"
        section += "   • 스트림 키: \(settings.streamKey.isEmpty ? "❌ 미설정" : "✅ 설정됨")\n\n"
        return section
    }
    
    private func generatePermissionSection() -> String {
        let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        
        var section = "🔐 권한 상태:\n"
        section += "   • 카메라: \(cameraAuth == .authorized ? "✅ 허용" : "❌ 거부")\n"
        section += "   • 마이크: \(micAuth == .authorized ? "✅ 허용" : "❌ 거부")\n\n"
        return section
    }
    
    private func generateDeviceSection() -> String {
        var section = "📹 카메라 디바이스:\n"
        let cameras = checkAvailableCameras()
        for camera in cameras {
            section += "   • \(camera)\n"
        }
        section += "\n"
        return section
    }
    
    private func generateYouTubeSection() async -> String {
        var section = "🎬 YouTube Live 진단:\n"
        let youtubeIssues = await diagnoseYouTubeStreaming()
        for issue in youtubeIssues {
            section += "   \(issue)\n"
        }
        section += "\n"
        return section
    }
    
    private func generateRecommendationsSection() -> String {
        var section = "💡 권장 사항:\n"
        
        let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if cameraAuth != .authorized {
            section += "   • 카메라 권한을 허용하세요\n"
        }
        if micAuth != .authorized {
            section += "   • 마이크 권한을 허용하세요\n"
        }
        if settings.streamKey.isEmpty || settings.streamKey == "YOUR_YOUTUBE_STREAM_KEY_HERE" {
            section += "   • YouTube Studio에서 실제 스트림 키를 설정하세요\n"
        }
        
        section += "   • YouTube Studio에서 '라이브 스트리밍 시작' 버튼을 눌러 대기 상태로 만드세요\n"
        section += "   • 스트림이 나타나기까지 10-30초 정도 기다려보세요\n\n"
        
        return section
    }
    
    // MARK: - Private Methods - Utilities
    
    private func updateStatus(_ newStatus: LiveStreamStatus, message: String) async {
        await MainActor.run {
            self.status = newStatus
            self.statusMessage = message
            logDebug("🎯 [STATUS] Updated to \(newStatus): \(message)", category: .streaming)
        }
    }
    
    private func syncServiceStatus(_ isStreaming: Bool) {
        if isStreaming && status != .streaming {
            status = .streaming
            logDebug("🎥 [SYNC] Service → ViewModel: streaming", category: .streaming)
        } else if !isStreaming && status == .streaming {
            status = .idle
            logDebug("🎥 [SYNC] Service → ViewModel: idle", category: .streaming)
        }
    }
    
    private func updateStreamingAvailability() {
        let hasValidRTMP = !settings.rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasValidKey = !settings.streamKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isRTMPFormat = settings.rtmpURL.hasPrefix("rtmp://") || settings.rtmpURL.hasPrefix("rtmps://")
        
        canStartStreaming = hasValidRTMP && hasValidKey && isRTMPFormat
        
        // 개발용 강제 활성화
        if !canStartStreaming {
            logWarning("Forcing canStartStreaming to true for development", category: .streaming)
            canStartStreaming = true
        }
    }
    
    private func updateNetworkRecommendations() {
        guard let liveStreamService = liveStreamService else { return }
        Task {
            networkRecommendations = await liveStreamService.getNetworkRecommendations()
        }
    }
    
    private func showError(_ message: String) {
        currentErrorMessage = message
        showingErrorAlert = true
    }
    
    private func logInitializationInfo() {
        logInfo("LiveStreamViewModel initialized", category: .streaming)
        logInfo("RTMP URL: \(settings.rtmpURL)", category: .streaming)
        logInfo("Stream Key: ***CONFIGURED***", category: .streaming)
        logInfo("📋 YouTube Live 설정 방법:", category: .streaming)
        logInfo("  1. studio.youtube.com 접속", category: .streaming)
        logInfo("  2. '라이브 스트리밍' > '스트림' 탭 선택", category: .streaming)
        logInfo("  3. '라이브 스트리밍 시작' 버튼 클릭", category: .streaming)
        logInfo("  4. 스트림 키 복사하여 앱에서 교체", category: .streaming)
    }
    
    private func logTransmissionStats(_ stats: Any) {
        // 타입을 확인하고 적절한 속성들을 출력
        logInfo("Transmission statistics received", category: .data)
        
        // Reflection을 사용하여 안전하게 통계 출력
        let mirror = Mirror(reflecting: stats)
        for child in mirror.children {
            if let label = child.label {
                logDebug("\(label): \(child.value)", category: .data)
            }
        }
    }
}

// MARK: - Supporting Types

/// 스트리밍 품질 프리셋
enum StreamingPreset: String, CaseIterable {
    case low
    case standard
    case high
    case ultra
    
    var displayName: String {
        switch self {
        case .low: return NSLocalizedString("streaming_preset_low", comment: "저화질")
        case .standard: return NSLocalizedString("streaming_preset_standard", comment: "표준")
        case .high: return NSLocalizedString("streaming_preset_high", comment: "고화질")
        case .ultra: return NSLocalizedString("streaming_preset_ultra", comment: "최고화질")
        }
    }
    
    var description: String {
        switch self {
        case .low: return "720p • 1.5Mbps"
        case .standard: return "1080p • 2.5Mbps"
        case .high: return "1080p • 4.5Mbps"
        case .ultra: return "4K • 8Mbps"
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "1.circle"
        case .standard: return "2.circle"
        case .high: return "3.circle"
        case .ultra: return "4.circle"
        }
    }
}

/// 네트워크 상태
enum NetworkStatus: String, CaseIterable {
    case poor
    case fair
    case good
    case excellent
    
    var displayName: String {
        switch self {
        case .poor: return NSLocalizedString("network_status_poor", comment: "불량")
        case .fair: return NSLocalizedString("network_status_fair", comment: "보통")
        case .good: return NSLocalizedString("network_status_good", comment: "양호")
        case .excellent: return NSLocalizedString("network_status_excellent", comment: "우수")
        }
    }
    
    var description: String {
        switch self {
        case .poor: return NSLocalizedString("network_status_poor_desc", comment: "느린 연결 (< 2Mbps)")
        case .fair: return NSLocalizedString("network_status_fair_desc", comment: "보통 연결 (2-5Mbps)")
        case .good: return NSLocalizedString("network_status_good_desc", comment: "빠른 연결 (5-10Mbps)")
        case .excellent: return NSLocalizedString("network_status_excellent_desc", comment: "매우 빠른 연결 (> 10Mbps)")
        }
    }
    
    var color: Color {
        switch self {
        case .poor: return .red
        case .fair: return .orange
        case .good: return .green
        case .excellent: return .blue
        }
    }
} 
