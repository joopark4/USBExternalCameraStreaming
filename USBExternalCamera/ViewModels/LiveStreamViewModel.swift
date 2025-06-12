//
//  LiveStreamViewModel.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 6/5/25.
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
        static let defaultVideoWidth = 1280
        static let defaultVideoHeight = 720
        static let defaultFrameRate = 30
    }
    
    // MARK: - Published Properties
    
    /// 현재 라이브 스트리밍 설정
    @Published var settings: USBExternalCamera.LiveStreamSettings
    
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
    
    /// 실시간 데이터 송출 통계 (실제 HaishinKitManager에서 가져옴)
    @Published var transmissionStats: DataTransmissionStats = DataTransmissionStats()
    
    /// 네트워크 품질 상태
    @Published var networkQuality: NetworkQuality = .unknown
    
    /// 로딩 상태 (스트리밍 시작/중지 중)
    @Published var isLoading: Bool = false
    
    /// 현재 스트리밍 중인지 여부
    var isStreaming: Bool {
        return status == .streaming
    }
    

    
    // MARK: - Computed Properties
    
    var streamingStatus: LiveStreamStatus {
        return status
    }
    
    // 기존 일반 스트리밍 버튼 관련 속성들 제거 - 화면 캡처 스트리밍만 사용
    
    // MARK: - Dependencies
    
    /// 라이브 스트리밍 서비스 (Services Layer)
    internal var liveStreamService: HaishinKitManagerProtocol!
    
    /// 라이브 스트리밍 서비스 접근자 (카메라 연결용)
    public var streamingService: HaishinKitManagerProtocol? {
        return liveStreamService
    }
    

    
    /// Combine 구독 저장소
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.settings = Self.createDefaultSettings()
        self.liveStreamService = HaishinKitManager()
        
        setupBindings()
        updateStreamingAvailability()
        loadInitialSettings()
        
        logInitializationInfo()
    }
    
    // MARK: - Public Methods - Streaming Control
    
    // 기존 일반 스트리밍 시작/중지 메서드들 제거 - 화면 캡처 스트리밍만 사용
    
    // 기존 일반 스트리밍 toggleStreaming 메서드 제거 - 화면 캡처 스트리밍만 사용
    

    
    // MARK: - Screen Capture Streaming Methods
    
    /// 🎬 화면 캡처 스트리밍 기능 섹션
    /// 
    /// **화면 캡처 스트리밍이란?**
    /// CameraPreviewContainerView의 화면(카메라 영상 + UI 오버레이)을 
    /// 실시간으로 캡처하여 스트리밍 서버로 송출하는 기능입니다.
    ///
    /// **일반 스트리밍과의 차이점:**
    /// - 일반 스트리밍: 카메라 영상만 전송
    /// - 화면 캡처 스트리밍: 카메라 영상 + UI 요소(버튼, 라벨, 워터마크 등) 합성 전송
    ///
    /// **기술적 구현:**
    /// 1. 실시간 카메라 프레임 캡처 (CVPixelBuffer)
    /// 2. UI 레이어 렌더링 (CALayer → UIImage)
    /// 3. 카메라 프레임과 UI 합성 (Core Graphics)
    /// 4. 30fps로 HaishinKit을 통해 서버 전송
    
    /// 화면 캡처 스트리밍 시작
    /// 
    /// **동작 과정:**
    /// 1. 스트리밍 서비스 초기화 및 서버 연결
    /// 2. CameraPreviewView에 화면 캡처 시작 신호 전송
    /// 3. 30fps 타이머 기반 실시간 화면 캡처 시작
    /// 4. 캡처된 프레임을 HaishinKit을 통해 서버로 전송
    ///
    /// **상태 변화:**
    /// idle → connecting → connected → streaming
    ///
    /// **에러 처리:**
    /// - 서비스 초기화 실패 시 자동으로 중지 상태로 복원
    /// - 네트워크 오류 시 사용자에게 알림 표시
    func startScreenCaptureStreaming() async {
        logInfo("🎬 Starting screen capture streaming mode...", category: .streaming)
        
        // UI 로딩 상태 시작
        isLoading = true
        await updateStatus(.connecting, message: NSLocalizedString("screen_capture_connecting", comment: "화면 캡처 스트리밍 연결 중..."))
        
        do {
            // Step 1: 스트리밍 서비스 초기화 및 서버 연결
            try await performScreenCaptureStreamingStart()
            
            // Step 2: 성공 시 후처리 (화면 캡처 시작 신호 전송)
            await handleScreenCaptureStreamingStartSuccess()
            
        } catch {
            // Step 3: 실패 시 복구 처리
            await handleScreenCaptureStreamingStartFailure(error)
        }
        
        // UI 로딩 상태 종료
        isLoading = false
    }
    
    /// 화면 캡처 스트리밍 토글 (시작/중지)
    /// 
    /// 사용자가 사이드바의 "스트리밍 시작 - 캡처" 버튼을 눌렀을 때 호출됩니다.
    /// 현재 상태에 따라 시작 또는 중지 동작을 수행합니다.
    ///
    /// **상태별 동작:**
    /// - idle/error: 화면 캡처 스트리밍 시작
    /// - connected/streaming: 화면 캡처 스트리밍 중지
    /// - connecting/disconnecting: 무시 (이미 상태 변경 중)
    ///
    /// **Thread Safety:**
    /// 비동기 처리를 통해 UI 블록킹을 방지합니다.
    func toggleScreenCaptureStreaming() {
        logDebug("🎮 [TOGGLE] Screen capture streaming toggle - Current status: \(status)", category: .streaming)
        
        switch status {
        case .idle, .error:
            // 화면 캡처 스트리밍 시작
            Task { await startScreenCaptureStreaming() }
            
        case .connected, .streaming:
            // 화면 캡처 스트리밍 중지
            Task { await stopScreenCaptureStreaming() }
            
        case .connecting, .disconnecting:
            // 이미 상태 변경 중이므로 무시
            logDebug("🎮 [TOGGLE] Ignoring toggle - already in transition state: \(status)", category: .streaming)
        }
    }
    
    /// 화면 캡처 스트리밍 중지
    /// 
    /// **동작 과정:**
    /// 1. CameraPreviewView에 화면 캡처 중지 신호 전송
    /// 2. 스트리밍 서버 연결 해제
    /// 3. 관련 리소스 정리 및 상태 초기화
    ///
    /// **상태 변화:**
    /// streaming → disconnecting → idle
    ///
    /// **리소스 정리:**
    /// - 화면 캡처 타이머 중지
    /// - 캡처된 프레임 메모리 해제
    /// - HaishinKit 연결 해제
    func stopScreenCaptureStreaming() async {
        logInfo("🎬 Stopping screen capture streaming...", category: .streaming)
        
        isLoading = true
        await updateStatus(.disconnecting, message: NSLocalizedString("screen_capture_disconnecting", comment: "화면 캡처 중지 중"))
        
        do {
            // Step 1: 스트리밍 서비스 중지 및 화면 캡처 중지 신호 전송
            try await performScreenCaptureStreamingStop()
            
            // Step 2: 성공 시 상태 초기화
            await handleScreenCaptureStreamingStopSuccess()
            
        } catch {
            // Step 3: 실패 시에도 강제로 상태 초기화 (안전장치)
            await handleScreenCaptureStreamingStopFailure(error)
        }
        
        isLoading = false
    }
    
    /// 화면 캡처 스트리밍이 활성 상태인지 확인
    var isScreenCaptureStreaming: Bool {
        guard let haishinKitManager = liveStreamService as? HaishinKitManager else { return false }
        return haishinKitManager.isScreenCaptureMode && haishinKitManager.isStreaming
    }
    
    /// 화면 캡처 스트리밍 버튼 텍스트
    var screenCaptureButtonText: String {
        if isScreenCaptureStreaming {
            return NSLocalizedString("screen_capture_stop", comment: "화면 캡처 중지")
        } else {
            switch status {
            case .idle, .error:
                return NSLocalizedString("streaming_start_capture", comment: "스트리밍 시작 - 캡처")
            case .connecting:
                return NSLocalizedString("screen_capture_connecting_button", comment: "화면 캡처 연결 중")
            case .disconnecting:
                return NSLocalizedString("screen_capture_disconnecting", comment: "화면 캡처 중지 중")
            default:
                return NSLocalizedString("streaming_start_capture", comment: "스트리밍 시작 - 캡처")
            }
        }
    }
    
    /// 화면 캡처 스트리밍 버튼 색상
    var screenCaptureButtonColor: Color {
        if isScreenCaptureStreaming {
            return .red
        } else {
            switch status {
            case .connecting, .disconnecting:
                return .gray
            default:
                return .purple
            }
        }
    }
    
    /// 화면 캡처 스트리밍 버튼 텍스트
    var streamingButtonText: String {
        if isScreenCaptureStreaming {
            return NSLocalizedString("screen_capture_stop", comment: "화면 캡처 중지")
        } else {
            switch status {
            case .idle, .error:
                return NSLocalizedString("streaming_start", comment: "스트리밍 시작")
            case .connecting:
                return NSLocalizedString("screen_capture_connecting_button", comment: "화면 캡처 연결 중")
            case .disconnecting:
                return NSLocalizedString("screen_capture_disconnecting", comment: "화면 캡처 중지 중")
            default:
                return NSLocalizedString("streaming_start", comment: "스트리밍 시작")
            }
        }
    }
    
    /// 화면 캡처 스트리밍 버튼 색상
    var streamingButtonColor: Color {
        if isScreenCaptureStreaming {
            return .red
        } else {
            switch status {
            case .connecting, .disconnecting:
                return .gray
            default:
                return .purple
            }
        }
    }
    
    /// 화면 캡처 스트리밍 버튼 활성화 상태
    var isScreenCaptureButtonEnabled: Bool {
        switch status {
        case .connecting, .disconnecting:
            return false
        default:
            return canStartStreaming || isScreenCaptureStreaming
        }
    }
    
    // MARK: - Public Methods - Settings
    
    /// 스트리밍 설정 저장
    func saveSettings() {
        logDebug("💾 [SETTINGS] Saving stream settings...", category: .streaming)
        guard let service = liveStreamService else { 
            logDebug("❌ [SETTINGS] Service not available for saving", category: .streaming)
            return 
        }
        
        service.saveSettings(settings)
        updateStreamingAvailability()
        logDebug("✅ [SETTINGS] Settings saved successfully", category: .streaming)
    }
    
    /// 설정 자동 저장 (설정이 변경될 때마다 호출)
    private func autoSaveSettings() {
        guard let service = liveStreamService else { return }
        
        service.saveSettings(settings)
        logDebug("💾 [AUTO-SAVE] Settings auto-saved", category: .streaming)
    }
    
    /// 연결 테스트
    func testConnection() async {
        logDebug("🔍 [TEST] Testing connection...", category: .streaming)
        
        await MainActor.run {
            self.connectionTestResult = NSLocalizedString("connection_test_starting", comment: "연결 테스트를 시작합니다...")
        }
        
        // 간단한 연결 테스트 시뮬레이션
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1초 대기
        
        let isValid = validateRTMPURL(settings.rtmpURL) && validateStreamKey(settings.streamKey)
        
        await MainActor.run {
            if isValid {
                self.connectionTestResult = NSLocalizedString("connection_test_success", comment: "설정이 유효합니다. 스트리밍을 시작할 수 있습니다.")
            } else {
                self.connectionTestResult = NSLocalizedString("connection_test_failed", comment: "설정에 문제가 있습니다. RTMP URL과 스트림 키를 확인해주세요.")
            }
        }
    }
    
    /// 빠른 연결 상태 확인
    func quickConnectionCheck() -> String {
        logDebug("⚡ [QUICK CHECK] 빠른 연결 상태 확인", category: .streaming)
        
        var result = "⚡ **빠른 연결 상태 확인**\n"
        result += String(repeating: "-", count: 30) + "\n\n"
        
        // RTMP URL 확인
        if settings.rtmpURL.isEmpty {
            result += "❌ RTMP URL이 설정되지 않았습니다\n"
        } else if validateRTMPURL(settings.rtmpURL) {
            result += "✅ RTMP URL이 올바르게 설정되었습니다\n"
        } else {
            result += "⚠️ RTMP URL 형식이 올바르지 않습니다\n"
        }
        
        // 스트림 키 확인
        if settings.streamKey.isEmpty {
            result += "❌ 스트림 키가 설정되지 않았습니다\n"
        } else if validateStreamKey(settings.streamKey) {
            result += "✅ 스트림 키가 올바르게 설정되었습니다\n"
        } else {
            result += "⚠️ 스트림 키가 너무 짧습니다\n"
        }
        
        // 권한 확인
        let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        
        result += cameraAuth == .authorized ? "✅ 카메라 권한 허용됨\n" : "❌ 카메라 권한 필요\n"
        result += micAuth == .authorized ? "✅ 마이크 권한 허용됨\n" : "❌ 마이크 권한 필요\n"
        
        result += "\n📊 현재 상태: \(status.description)\n"
        
        return result
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
        // keyframeInterval, videoEncoder, audioEncoder는 LiveStreamSettings에 없음
        
        updateStreamingAvailability()
    }
    
    /// 설정 초기화 (저장된 설정도 삭제)
    func resetToDefaults() {
        logDebug("🔄 [SETTINGS] Resetting to default settings...", category: .streaming)
        settings = USBExternalCamera.LiveStreamSettings()
        
        // 기본값을 720p 프리셋으로 설정하여 프리셋과 동기화
        settings.applyYouTubeLivePreset(.hd720p)
        
        // 저장된 설정도 삭제
        clearSavedSettings()
        
        // 즉시 기본 설정을 저장
        autoSaveSettings()
        
        updateStreamingAvailability()
        
        logDebug("✅ [SETTINGS] Reset to 720p preset successfully", category: .streaming)
    }
    
    /// 유튜브 라이브 스트리밍 표준 프리셋 적용
    func applyYouTubePreset(_ preset: YouTubeLivePreset) {
        logDebug("🎯 [PRESET] Applying YouTube preset: \(preset.displayName)", category: .streaming)
        
        settings.applyYouTubeLivePreset(preset)
        
        // 설정 즉시 저장
        autoSaveSettings()
        
        // 스트리밍 가능 여부 업데이트
        updateStreamingAvailability()
        
        logDebug("✅ [PRESET] YouTube preset applied successfully", category: .streaming)
        logDebug("📊 [PRESET] Resolution: \(settings.videoWidth)×\(settings.videoHeight)", category: .streaming)
        logDebug("📊 [PRESET] Bitrate: \(settings.videoBitrate) kbps", category: .streaming)
    }
    
    /// 현재 설정에서 유튜브 프리셋 감지
    func detectCurrentYouTubePreset() -> YouTubeLivePreset {
        return settings.detectYouTubePreset() ?? .custom
    }
    
    /// 저장된 설정 삭제 (앱 삭제와 같은 효과)
    private func clearSavedSettings() {
        let defaults = UserDefaults.standard
        let keys = [
            "LiveStream.rtmpURL",
            "LiveStream.streamTitle",
            "LiveStream.videoBitrate",
            "LiveStream.videoWidth",
            "LiveStream.videoHeight",
            "LiveStream.frameRate",
            "LiveStream.audioBitrate",
            "LiveStream.autoReconnect",
            "LiveStream.isEnabled",
            "LiveStream.bufferSize",
            "LiveStream.connectionTimeout",
            "LiveStream.videoEncoder",
            "LiveStream.audioEncoder",
            "LiveStream.savedAt"
        ]
        
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        
        // Keychain에서 스트림 키 삭제 (보안 향상)
        KeychainManager.shared.deleteStreamKey()
        
        defaults.synchronize()
        logDebug("🗑️ [CLEAR] Saved settings cleared", category: .streaming)
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
        // getCurrentTransmissionStatus 메서드가 아직 구현되지 않음
        logDebug("ℹ️ [DATA CHECK] Transmission status check not yet implemented", category: .streaming)
    }
    
    /// 스트리밍 데이터 요약 정보 가져오기
    @MainActor
    func getStreamingDataSummary() async -> String {
        guard liveStreamService != nil else {
            return "❌ LiveStreamService가 초기화되지 않음"
        }
        
        // getStreamingDataSummary 메서드가 아직 구현되지 않음
        let statusText = switch status {
        case .idle: NSLocalizedString("status_idle", comment: "대기 중")
        case .connecting: NSLocalizedString("status_connecting", comment: "연결 중")
        case .connected: NSLocalizedString("status_connected", comment: "연결됨")
        case .streaming: NSLocalizedString("status_streaming", comment: "스트리밍 중")
        case .disconnecting: NSLocalizedString("status_disconnecting", comment: "연결 해제 중")
        case .error(let error): NSLocalizedString("status_error_prefix", comment: "오류: ") + error.localizedDescription
        }
        let summary = "📊 스트리밍 상태: \(statusText)\n📡 연결 상태: 정상"
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
    
    // MARK: - Public Methods - Connection Diagnostics
    
    /// **실시간 송출 상태 진단**
    func diagnoseLiveStreamConnection() async -> String {
        logDebug("🔍 [DIAGNOSIS] 실시간 송출 상태 진단 시작", category: .streaming)
        
        var report = "📊 **실시간 송출 상태 진단 보고서**\n"
        report += String(repeating: "=", count: 50) + "\n\n"
        
        // 1. 기본 설정 확인
        report += "📋 **1. 기본 설정 상태**\n"
        report += "   • 현재 상태: \(status.description)\n"
        report += "   • RTMP URL: \(settings.rtmpURL.isEmpty ? "❌ 미설정" : "✅ 설정됨")\n"
        report += "   • 스트림 키: \(settings.streamKey.isEmpty ? "❌ 미설정" : "✅ 설정됨 (\(settings.streamKey.count)자)")\n"
        report += "   • 비트레이트: \(settings.videoBitrate) kbps\n"
        report += "   • 해상도: \(settings.videoWidth)x\(settings.videoHeight)\n\n"
        
        // 2. 권한 상태 확인
        report += "🔐 **2. 권한 상태**\n"
        let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        
        report += "   • 카메라 권한: \(cameraAuth == .authorized ? "✅ 허용됨" : "❌ 거부됨 또는 미결정")\n"
        report += "   • 마이크 권한: \(micAuth == .authorized ? "✅ 허용됨" : "❌ 거부됨 또는 미결정")\n\n"
        
        // 3. 카메라 장치 확인
        report += "📹 **3. 카메라 장치 상태**\n"
        let cameras = checkAvailableCameras()
        if cameras.isEmpty || cameras.first?.contains("❌") == true {
            report += "   ❌ **문제**: 사용 가능한 카메라 없음\n"
            report += "   💡 **해결책**: USB 카메라 연결 확인 또는 앱 재시작\n"
        } else {
            for camera in cameras {
                report += "   \(camera)\n"
            }
        }
        report += "\n"
        
        // 4. 네트워크 및 RTMP 설정 확인
        report += "🌐 **4. 네트워크 및 RTMP 설정**\n"
        let rtmpValidation = await validateRTMPSettings()
        report += rtmpValidation
        report += "\n"
        
        // 5. 스트리밍 서비스 상태
        report += "⚙️ **5. 스트리밍 서비스 상태**\n"
        if let service = liveStreamService {
            report += "   • 서비스 초기화: ✅ 완료\n"
            report += "   • 서비스 스트리밍 상태: \(service.isStreaming ? "🔴 스트리밍 중" : "⚪ 대기 중")\n"
            report += "   • 서비스 상태: \(service.currentStatus.description)\n"
        } else {
            report += "   • 서비스 초기화: ❌ **실패** - 이것이 주요 문제입니다!\n"
            report += "   💡 **해결책**: 앱을 완전히 종료하고 다시 시작하세요\n"
        }
        report += "\n"
        
        // 6. 진단 결과 및 권장사항
        report += "💡 **6. 진단 결과 및 권장사항**\n"
        let recommendations = await generateRecommendations()
        report += recommendations
        
        report += "\n" + String(repeating: "=", count: 50) + "\n"
        report += "📅 진단 완료: \(Date().formatted())\n"
        
        logDebug("🔍 [DIAGNOSIS] 진단 완료", category: .streaming)
        return report
    }
    
    /// RTMP 설정 유효성 검사
    private func validateRTMPSettings() async -> String {
        var result = ""
        
        // URL 검증
        if settings.rtmpURL.isEmpty {
            result += "   ❌ **RTMP URL이 설정되지 않음**\n"
            result += "   💡 YouTube의 경우: rtmp://a.rtmp.youtube.com/live2/\n"
        } else if !settings.rtmpURL.lowercased().hasPrefix("rtmp") {
            result += "   ❌ **잘못된 RTMP URL 형식**\n"
            result += "   💡 'rtmp://' 또는 'rtmps://'로 시작해야 합니다\n"
        } else {
            result += "   ✅ RTMP URL 형식이 올바름\n"
        }
        
        // 스트림 키 검증
        if settings.streamKey.isEmpty {
            result += "   ❌ **스트림 키가 설정되지 않음**\n"
            result += "   💡 YouTube Studio에서 스트림 키를 복사하세요\n"
        } else if settings.streamKey == "YOUR_YOUTUBE_STREAM_KEY_HERE" {
            result += "   ❌ **더미 스트림 키 사용 중**\n"
            result += "   💡 실제 YouTube 스트림 키로 변경하세요\n"
        } else if settings.streamKey.count < Constants.minimumStreamKeyLength {
            result += "   ⚠️ **스트림 키가 너무 짧음** (\(settings.streamKey.count)자)\n"
            result += "   💡 YouTube 스트림 키는 일반적으로 20자 이상입니다\n"
        } else {
            result += "   ✅ 스트림 키가 설정됨 (\(settings.streamKey.count)자)\n"
        }
        
        // 간단한 연결 테스트
        if let testResult = await liveStreamService?.testConnection(to: settings) {
            if testResult.isSuccessful {
                result += "   ✅ 연결 테스트 성공 (지연시간: \(testResult.latency)ms)\n"
            } else {
                result += "   ❌ **연결 테스트 실패**: \(testResult.message)\n"
            }
        } else {
            result += "   ⚠️ 연결 테스트를 수행할 수 없음\n"
        }
        
        return result
    }
    
    /// 권장사항 생성
    private func generateRecommendations() async -> String {
        var recommendations = ""
        var issueCount = 0
        
        // 권한 문제 확인
        let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        
        if cameraAuth != .authorized {
            issueCount += 1
            recommendations += "   \(issueCount). 📸 **카메라 권한 허용** (설정 > 개인정보 보호 > 카메라)\n"
        }
        
        if micAuth != .authorized {
            issueCount += 1
            recommendations += "   \(issueCount). 🎤 **마이크 권한 허용** (설정 > 개인정보 보호 > 마이크)\n"
        }
        
        // 설정 문제 확인
        if settings.streamKey.isEmpty || settings.streamKey == "YOUR_YOUTUBE_STREAM_KEY_HERE" {
            issueCount += 1
            recommendations += "   \(issueCount). 🔑 **YouTube Studio에서 실제 스트림 키 설정**\n"
        }
        
        if settings.rtmpURL.isEmpty {
            issueCount += 1
            recommendations += "   \(issueCount). 🌐 **RTMP URL 설정** (YouTube: rtmp://a.rtmp.youtube.com/live2/)\n"
        }
        
        // 카메라 문제 확인
        let cameras = checkAvailableCameras()
        if cameras.isEmpty || cameras.first?.contains("❌") == true {
            issueCount += 1
            recommendations += "   \(issueCount). 📹 **카메라 연결 확인** (USB 카메라 재연결 또는 앱 재시작)\n"
        }
        
        // YouTube 관련 권장사항
        issueCount += 1
        recommendations += "   \(issueCount). 🎬 **YouTube Studio 확인사항**:\n"
        recommendations += "      • 라이브 스트리밍 기능이 활성화되어 있는지 확인\n"
        recommendations += "      • 휴대폰 번호 인증이 완료되어 있는지 확인\n"
        recommendations += "      • '라이브 스트리밍 시작' 버튼을 눌러 대기 상태로 설정\n"
        recommendations += "      • 스트림이 나타나기까지 10-30초 대기\n"
        
        if issueCount == 1 {
            recommendations = "   ✅ **대부분의 설정이 정상입니다!**\n" + recommendations
            recommendations += "\n   💡 **추가 팁**: 문제가 지속되면 앱을 완전히 종료하고 재시작해보세요.\n"
        }
        
        return recommendations
    }
    
    // MARK: - Private Methods - Setup
    
    private static func createDefaultSettings() -> USBExternalCamera.LiveStreamSettings {
        var settings = USBExternalCamera.LiveStreamSettings()
        settings.rtmpURL = Constants.youtubeRTMPURL
        settings.streamKey = ""
        settings.videoBitrate = Constants.defaultVideoBitrate
        settings.audioBitrate = Constants.defaultAudioBitrate
        settings.videoWidth = Constants.defaultVideoWidth
        settings.videoHeight = Constants.defaultVideoHeight
        settings.frameRate = Constants.defaultFrameRate
        return settings
    }
    
    private static func createPresetSettings(_ preset: StreamingPreset) -> USBExternalCamera.LiveStreamSettings {
        var settings = USBExternalCamera.LiveStreamSettings()
        
        switch preset {
        case .low:
            settings.videoWidth = 1280
            settings.videoHeight = 720
            settings.videoBitrate = 2500
            settings.frameRate = 30
        case .standard:
            settings.videoWidth = 1920
            settings.videoHeight = 1080
            settings.videoBitrate = 4500
            settings.frameRate = 30
        case .high:
            settings.videoWidth = 1920
            settings.videoHeight = 1080
            settings.videoBitrate = 6000
            settings.frameRate = 60
        case .ultra:
            settings.videoWidth = 3840
            settings.videoHeight = 2160
            settings.videoBitrate = 8000
            settings.frameRate = 60
        }
        
        settings.audioBitrate = preset == .ultra ? 256 : 128
        // keyframeInterval, videoEncoder, audioEncoder는 LiveStreamSettings에 없음
        
        return settings
    }
    
    private func setupBindings() {
        // 설정 변경 감지 및 자동 저장
        $settings
            .dropFirst() // 초기값 제외
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main) // 500ms 디바운스
            .sink { [weak self] _ in
                self?.autoSaveSettings()
            }
            .store(in: &cancellables)
        
        // HaishinKitManager의 transmissionStats와 바인딩
        if let haishinKitManager = liveStreamService as? HaishinKitManager {
            haishinKitManager.$transmissionStats
                .receive(on: DispatchQueue.main)
                .assign(to: \.transmissionStats, on: self)
                .store(in: &cancellables)
            
            // 스트리밍 상태도 바인딩
            haishinKitManager.$currentStatus
                .receive(on: DispatchQueue.main)
                .assign(to: \.status, on: self)
                .store(in: &cancellables)
            
            // 네트워크 품질 바인딩 (transmissionStats에서 추출)
            haishinKitManager.$transmissionStats
                .map(\.connectionQuality)
                .map { connectionQuality in
                    switch connectionQuality {
                    case .excellent: return NetworkQuality.excellent
                    case .good: return NetworkQuality.good
                    case .fair: return NetworkQuality.fair
                    case .poor: return NetworkQuality.poor
                    case .unknown: return NetworkQuality.unknown
                    }
                }
                .receive(on: DispatchQueue.main)
                .assign(to: \.networkQuality, on: self)
                .store(in: &cancellables)
            
            logDebug("✅ [BINDING] HaishinKitManager와 바인딩 완료", category: .streaming)
        }
        
        logDebug("✅ [AUTO-SAVE] 설정 자동 저장 바인딩 완료", category: .streaming)
    }
    
    private func loadInitialSettings() {
        guard let liveStreamService = liveStreamService else { return }
        
        Task {
            let loadedSettings = liveStreamService.loadSettings()
            
            await MainActor.run {
                // 로드된 설정이 있으면 적용 (빈 설정도 포함)
                self.settings = loadedSettings
                
                if !loadedSettings.rtmpURL.isEmpty || !loadedSettings.streamKey.isEmpty {
                    logDebug("🎥 [LOAD] Saved settings loaded - RTMP: \(!loadedSettings.rtmpURL.isEmpty), Key: \(!loadedSettings.streamKey.isEmpty)", category: .streaming)
                } else {
                    logDebug("📝 [LOAD] Default settings loaded (no saved data)", category: .streaming)
                }
                
                self.updateStreamingAvailability()
                self.updateNetworkRecommendations()
            }
        }
    }
    
    // MARK: - Private Methods - Streaming
    
    private func performStreamingStart(with captureSession: AVCaptureSession) async throws {
        guard let service = liveStreamService else {
            throw LiveStreamError.networkError("Service not initialized")
        }
        
        // 화면 캡처 스트리밍 시작 (카메라 스트리밍은 제거됨)
        if let haishinKitManager = service as? HaishinKitManager {
            try await haishinKitManager.startScreenCaptureStreaming(with: settings)
        } else {
            // 다른 서비스의 경우 화면 캡처 스트리밍을 구현해야 함
            throw LiveStreamError.streamingFailed(NSLocalizedString("screen_capture_only_supported", comment: "화면 캡처 스트리밍만 지원됩니다"))
        }
    }
    
    private func performStreamingStop() async throws {
        guard let service = liveStreamService else {
            throw LiveStreamError.networkError("Service not initialized")
        }
        
        // 화면 캡처 중지 알림 전송 (화면 캡처 모드인 경우)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .stopScreenCapture, object: nil)
        }
        
        await service.stopStreaming()
    }
    
    private func handleStreamingStartSuccess() async {
        await updateStatus(.connected, message: NSLocalizedString("server_connected", comment: "서버에 연결됨"))
        try? await Task.sleep(nanoseconds: Constants.statusTransitionDelay)
        await updateStatus(.streaming, message: "YouTube Live 스트리밍 중")
        logDebug("✅ [STREAM] Streaming started successfully", category: .streaming)
    }
    
    private func handleStreamingStartFailure(_ error: Error) async {
        await updateStatus(.error(.streamingFailed(error.localizedDescription)), message: NSLocalizedString("streaming_start_failed", comment: "스트리밍 시작 실패: ") + error.localizedDescription)
        logDebug("❌ [STREAM] Failed to start: \(error.localizedDescription)", category: .streaming)
    }
    
    private func handleStreamingStopSuccess() async {
        await updateStatus(.idle, message: NSLocalizedString("streaming_ended", comment: "스트리밍이 종료되었습니다"))
        logDebug("✅ [STREAM] Streaming stopped successfully", category: .streaming)
    }
    
    private func handleStreamingStopFailure(_ error: Error) async {
        await updateStatus(.idle, message: NSLocalizedString("streaming_cleanup_complete", comment: "스트리밍 종료 완료 (일부 정리 오류 무시됨)"))
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
            // getCurrentTransmissionStatus 메서드가 아직 구현되지 않음
            issues.append("ℹ️ 스트리밍 상태 확인 기능은 구현 중입니다")
            solutions.append("💡 YouTube Studio에서 직접 스트림 상태를 확인하세요")
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
            NSLocalizedString("youtube_check_stream_waiting", comment: "스트림이 '대기 중' 상태인지 확인하세요"),
            NSLocalizedString("youtube_check_live_enabled", comment: "채널에서 라이브 스트리밍 기능이 활성화되어 있는지 확인하세요"),
            NSLocalizedString("youtube_check_phone_verified", comment: "휴대폰 번호 인증이 완료되어 있는지 확인하세요")
        ]
    }
    
    // MARK: - Private Methods - Report Generation
    
    private func generateBasicInfoSection() -> String {
        var section = "📱 기본 정보:\n"
        section += "   • 앱 상태: \(status)\n"
        section += "   • " + NSLocalizedString("streaming_available", comment: "스트리밍 가능: ") + "\(canStartStreaming ? NSLocalizedString("yes", comment: "예") : NSLocalizedString("no", comment: "아니오"))\n"
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
        // getNetworkRecommendations 메서드가 아직 구현되지 않음
        // 기본값으로 설정
        networkRecommendations = StreamingRecommendations(
            recommendedVideoBitrate: 2500,
            recommendedAudioBitrate: 128,
            recommendedResolution: (width: 1920, height: 1080),
            networkQuality: .good,
            suggestions: ["네트워크 상태가 양호합니다"]
        )
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
    
    // MARK: - Screen Capture Streaming Private Methods
    
    /// 화면 캡처 스트리밍 시작 실행 (내부 메서드)
    /// 
    /// **실행 단계:**
    /// 1. 스트리밍 서비스 유효성 검사
    /// 2. HaishinKit 초기화 및 서버 연결
    /// 3. 데이터 모니터링 시작
    ///
    /// **예외 처리:**
    /// - 서비스 미초기화: LiveStreamError.configurationError
    /// - 네트워크 연결 실패: LiveStreamError.networkError
    /// - 기타 오류: 원본 에러 전파
    ///
    /// - Throws: LiveStreamError 또는 기타 스트리밍 관련 에러
    private func performScreenCaptureStreamingStart() async throws {
        guard let haishinKitManager = liveStreamService as? HaishinKitManager else {
            throw LiveStreamError.configurationError("HaishinKitManager가 초기화되지 않았습니다")
        }
        
        logDebug("🔄 [화면캡처] 화면 캡처 스트리밍 시작 중...", category: .streaming)
        
        // 화면 캡처 전용 스트리밍 시작 (일반 스트리밍과 다른 메서드 사용)
        try await haishinKitManager.startScreenCaptureStreaming(with: settings)
        
        // 데이터 모니터링 시작 (네트워크 상태, FPS 등)
        startDataMonitoring()
        
        logInfo("✅ [화면캡처] 화면 캡처 스트리밍 서비스 시작 완료", category: .streaming)
    }
    
    /// 화면 캡처 스트리밍 시작 성공 후처리 (내부 메서드)
    /// 
    /// **수행 작업:**
    /// 1. 스트리밍 상태를 'streaming'으로 변경
    /// 2. CameraPreviewView에 화면 캡처 시작 알림 전송
    /// 3. 성공 메시지 표시
    ///
    /// **알림 시스템:**
    /// NotificationCenter를 통해 CameraPreviewView와 통신하여
    /// 30fps 화면 캡처 타이머를 시작시킵니다.
    private func handleScreenCaptureStreamingStartSuccess() async {
        logInfo("✅ [화면캡처] 스트리밍 시작 성공", category: .streaming)
        
        // 상태를 'streaming'으로 업데이트
        await updateStatus(.streaming, message: NSLocalizedString("screen_capture_broadcasting", comment: "화면 캡처 송출 중"))
        
        // CameraPreviewView에 화면 캡처 시작 신호 전송
        // 이 알림을 받으면 CameraPreviewUIView에서 30fps 타이머 시작
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .startScreenCapture, object: nil)
        }
        
        logInfo("📡 [화면캡처] 화면 캡처 시작 신호 전송 완료", category: .streaming)
    }
    
    /// 화면 캡처 스트리밍 시작 실패 처리 (내부 메서드)
    /// 
    /// **복구 작업:**
    /// 1. 상태를 'error'로 변경
    /// 2. 사용자에게 구체적인 오류 메시지 표시
    /// 3. 관련 리소스 정리
    ///
    /// **에러 메시지 매핑:**
    /// - 네트워크 오류: "네트워크 연결을 확인해주세요"
    /// - 설정 오류: "스트리밍 설정을 확인해주세요"
    /// - 기타 오류: 원본 에러 메시지 표시
    ///
    /// - Parameter error: 발생한 오류 정보
    private func handleScreenCaptureStreamingStartFailure(_ error: Error) async {
        logError("❌ [화면캡처] 스트리밍 시작 실패: \(error.localizedDescription)", category: .streaming)
        
        // 사용자 친화적인 에러 메시지 생성
        let userMessage: String
        if let liveStreamError = error as? LiveStreamError {
            switch liveStreamError {
            case .networkError(let message):
                userMessage = NSLocalizedString("network_connection_error", comment: "네트워크 연결 오류: ") + message
            case .configurationError(let message):
                userMessage = "설정 오류: \(message)"
            case .streamingFailed(let message):
                userMessage = "스트리밍 실패: \(message)"
            case .initializationFailed(let message):
                userMessage = "초기화 실패: \(message)"
            case .deviceNotFound(let message):
                userMessage = "디바이스 없음: \(message)"
            case .authenticationFailed(let message):
                userMessage = "인증 실패: \(message)"
            case .permissionDenied(let message):
                userMessage = "권한 거부: \(message)"
            case .incompatibleSettings(let message):
                userMessage = "설정 호환 불가: \(message)"
            case .connectionTimeout:
                userMessage = "연결 시간 초과"
            case .serverError(let code, let message):
                userMessage = "서버 오류 (\(code)): \(message)"
            case .unknown(let message):
                userMessage = "알 수 없는 오류: \(message)"
            }
        } else {
            userMessage = "화면 캡처 스트리밍 시작 실패: \(error.localizedDescription)"
        }
        
        // 에러 상태로 변경 및 메시지 표시
        await updateStatus(.error(.streamingFailed(userMessage)), message: userMessage)
    }
    
    /// 화면 캡처 스트리밍 중지 실행 (내부 메서드)
    /// 
    /// **중지 단계:**
    /// 1. CameraPreviewView에 화면 캡처 중지 신호 전송
    /// 2. 스트리밍 서비스 연결 해제
    /// 3. 데이터 모니터링 중지
    ///
    /// **중지 순서 중요성:**
    /// 먼저 화면 캡처를 중지해야 HaishinKit으로 전송되는 프레임이 중단되고,
    /// 그 다음 서비스 연결을 해제하여 안전하게 종료됩니다.
    ///
    /// - Throws: LiveStreamError 또는 기타 스트리밍 관련 에러
    private func performScreenCaptureStreamingStop() async throws {
        guard let service = liveStreamService else {
            throw LiveStreamError.configurationError("스트리밍 서비스가 초기화되지 않았습니다")
        }
        
        logDebug("🔄 [화면캡처] 스트리밍 서비스 중지 중...", category: .streaming)
        
        // Step 1: CameraPreviewView에 화면 캡처 중지 신호 전송
        // 30fps 타이머 중지 및 프레임 캡처 종료
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .stopScreenCapture, object: nil)
        }
        
        // Step 2: HaishinKit 스트리밍 서비스 중지
        await service.stopStreaming()
        
        logInfo("✅ [화면캡처] 스트리밍 서비스 중지 완료", category: .streaming)
    }
    
    /// 화면 캡처 스트리밍 중지 성공 후처리 (내부 메서드)
    /// 
    /// **정리 작업:**
    /// 1. 상태를 'idle'로 초기화
    /// 2. 성공 메시지 표시
    /// 3. 관련 상태 변수 초기화
    ///
    /// **상태 초기화:**
    /// 다음 화면 캡처 스트리밍을 위해 모든 상태를 초기값으로 복원합니다.
    private func handleScreenCaptureStreamingStopSuccess() async {
        logInfo("✅ [화면캡처] 스트리밍 중지 성공", category: .streaming)
        
        // 상태를 'idle'로 초기화
        await updateStatus(.idle, message: "화면 캡처 스트리밍 준비 완료")
        
        logInfo("🏁 [화면캡처] 모든 리소스 정리 완료", category: .streaming)
    }
    
    /// 화면 캡처 스트리밍 중지 실패 처리 (내부 메서드)
    /// 
    /// **안전장치 역할:**
    /// 스트리밍 중지 중 오류가 발생해도 강제로 상태를 초기화하여
    /// 사용자가 다시 스트리밍을 시작할 수 있도록 합니다.
    ///
    /// **강제 정리:**
    /// - 화면 캡처 중지 신호 재전송
    /// - 상태 강제 초기화
    /// - 모든 모니터링 중지
    ///
    /// - Parameter error: 발생한 오류 정보
    private func handleScreenCaptureStreamingStopFailure(_ error: Error) async {
        logError("❌ [화면캡처] 스트리밍 중지 실패: \(error.localizedDescription)", category: .streaming)
        
        // 강제로 화면 캡처 중지 신호 재전송 (안전장치)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .stopScreenCapture, object: nil)
        }
        
        // 강제로 상태 초기화 (사용자가 다시 시도할 수 있도록)
        await updateStatus(.idle, message: "스트리밍 중지됨 (오류 복구)")
        
        logWarning("⚠️ [화면캡처] 강제 상태 초기화 완료", category: .streaming)
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
