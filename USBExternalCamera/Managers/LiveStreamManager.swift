//
//  LiveStreamManager.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import Foundation
import AVFoundation
import Combine

/// 라이브 스트리밍 매니저 (기본 구현)
/// 향후 HaishinKit 2.0.8 API 완전 통합 예정
@MainActor
final class LiveStreamManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// 현재 스트리밍 상태
    @Published var status: LiveStreamStatus = .idle
    
    /// 연결 상태 메시지
    @Published var statusMessage: String = ""
    
    /// 스트리밍 통계 정보
    @Published var streamStats: StreamStats = StreamStats()
    
    /// 오류 메시지
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    /// 현재 스트리밍 설정
    private var currentSettings: LiveStreamSettings?
    
    /// 카메라 캡처 세션
    private var captureSession: AVCaptureSession?
    
    /// Combine 구독 저장소
    private var cancellables = Set<AnyCancellable>()
    
    /// 재연결 타이머
    private var reconnectTimer: Timer?
    
    /// 재연결 시도 횟수
    private var reconnectAttempts: Int = 0
    
    /// 최대 재연결 시도 횟수
    private let maxReconnectAttempts: Int = 3
    
    /// 시뮬레이션을 위한 타이머
    private var simulationTimer: Timer?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    deinit {
        Task { @MainActor in
            await stopStreaming()
        }
        cancellables.removeAll()
        reconnectTimer?.invalidate()
        simulationTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// 라이브 스트리밍 시작
    /// - Parameters:
    ///   - settings: 스트리밍 설정
    ///   - captureSession: 카메라 캡처 세션
    func startStreaming(with settings: LiveStreamSettings, captureSession: AVCaptureSession) async {
        guard status == .idle else {
            await updateStatus(.error, message: NSLocalizedString("already_streaming", comment: ""))
            return
        }
        
        self.currentSettings = settings
        self.captureSession = captureSession
        
        await updateStatus(.connecting, message: NSLocalizedString("connecting_to_server", comment: ""))
        
        // 시뮬레이션: 2초 후 연결 완료
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if !settings.streamKey.isEmpty && !settings.rtmpURL.isEmpty {
                    await self.updateStatus(.connected, message: NSLocalizedString("connected_to_server", comment: ""))
                    
                    // 1초 후 스트리밍 시작
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        Task { @MainActor [weak self] in
                            await self?.publishStream(with: settings.streamKey)
                        }
                    }
                } else {
                    await self.updateStatus(.error, message: NSLocalizedString("stream_key_rtmp_required", comment: ""))
                }
            }
        }
    }
    
    /// 라이브 스트리밍 중지
    func stopStreaming() async {
        guard status != .idle else { return }
        
        await updateStatus(.disconnecting, message: NSLocalizedString("disconnecting", comment: ""))
        
        // 시뮬레이션 타이머 정리
        simulationTimer?.invalidate()
        simulationTimer = nil
        
        await updateStatus(.idle, message: NSLocalizedString("streaming_stopped", comment: ""))
        
        // 리소스 정리
        currentSettings = nil
        captureSession = nil
        reconnectAttempts = 0
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    /// 스트리밍 설정 업데이트
    /// - Parameter settings: 새로운 스트리밍 설정
    func updateSettings(_ settings: LiveStreamSettings) async {
        currentSettings = settings
    }
    
    // MARK: - Private Methods
    
    /// 스트리밍 게시 시작 (시뮬레이션)
    /// - Parameter streamKey: 스트림 키
    private func publishStream(with streamKey: String) async {
        await updateStatus(.streaming, message: NSLocalizedString("streaming_live", comment: ""))
        
        // 통계 정보 업데이트 시작
        startStatsUpdating()
    }
    
    /// 상태 업데이트
    /// - Parameters:
    ///   - newStatus: 새로운 상태
    ///   - message: 상태 메시지
    private func updateStatus(_ newStatus: LiveStreamStatus, message: String) async {
        status = newStatus
        statusMessage = message
    }
    
    /// 통계 정보 업데이트 시작
    private func startStatsUpdating() {
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStreamStats()
            }
        }
    }
    
    /// 스트림 통계 정보 업데이트 (시뮬레이션)
    private func updateStreamStats() {
        guard status == .streaming, let settings = currentSettings else { return }
        
        // 실제 설정값을 기반으로 한 시뮬레이션 통계
        streamStats.videoBitrate = Double(settings.videoBitrate)
        streamStats.audioBitrate = Double(settings.audioBitrate)
        streamStats.frameRate = Double(settings.frameRate)
        streamStats.droppedFrames = Int.random(in: 0...5) // 랜덤 드롭 프레임
        streamStats.streamDuration += 1.0 // 1초씩 증가
    }
}

// MARK: - Supporting Types

/// 스트림 통계 정보
struct StreamStats {
    var videoBitrate: Double = 0
    var audioBitrate: Double = 0
    var frameRate: Double = 0
    var droppedFrames: Int = 0
    var streamDuration: TimeInterval = 0
    
    mutating func updateWith(stream: Any) {
        // 향후 HaishinKit API 통합시 구현 예정
    }
}

/// 라이브 스트리밍 관련 오류
enum LiveStreamError: LocalizedError {
    case streamConfigurationFailed
    case connectionFailed
    case invalidSettings
    case cameraNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .streamConfigurationFailed:
            return NSLocalizedString("stream_setup_failed", comment: "")
        case .connectionFailed:
            return NSLocalizedString("server_connection_failed", comment: "")
        case .invalidSettings:
            return NSLocalizedString("invalid_streaming_settings", comment: "")
        case .cameraNotAvailable:
            return NSLocalizedString("camera_unavailable", comment: "")
        }
    }
} 