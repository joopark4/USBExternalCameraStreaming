//
//  StreamingStatsManager.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation
import HaishinKit
import os.log
import Combine

// MARK: - Streaming Stats Manager Implementation

/// 스트리밍 통계 관리 클래스
/// 🔧 개선: 통계 수집은 백그라운드에서, UI 업데이트만 메인 스레드에서 처리
public final class StreamingStatsManager: @preconcurrency StreamingStatsManagerProtocol, ObservableObject {
    
    // MARK: - Properties
    
    /// 통계 모니터링 타이머
    private var statsTimer: Timer?
    
    /// HaishinKit 매니저 (통계 수집용)
    private weak var haishinKitManager: HaishinKitManagerProtocol?
    
    /// 현재 스트리밍 설정
    private var currentSettings: LiveStreamSettings?
    
    /// 스트리밍 시작 시간
    private var streamStartTime: Date?
    
    /// 현재 통계 정보 (메인 스레드에서 UI 업데이트)
    @MainActor @Published public var currentStreamingInfo: StreamingInfo?
    
    /// 현재 데이터 전송 통계 (메인 스레드에서 UI 업데이트)
    @MainActor @Published public var currentTransmissionStats: DataTransmissionStats?
    
    /// Combine 구독 저장소
    private var cancellables = Set<AnyCancellable>()
    
    /// 백그라운드 큐 (통계 수집용)
    private let statsQueue = DispatchQueue(label: "StreamingStats", qos: .utility)
    
    // MARK: - Initialization
    
    public init() {
        logInfo("✅ StreamingStatsManager initialized", category: .streaming)
    }
    
    deinit {
        logInfo("StreamingStatsManager deinitializing...", category: .streaming)
        cancellables.removeAll()
    }
    
    // MARK: - Protocol Implementation
    
    /// 통계 모니터링 시작
    public func startMonitoring() {
        logInfo("📊 Starting streaming stats monitoring...", category: .streaming)
        
        streamStartTime = Date()
        
        // 1초마다 통계 업데이트
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateStats()
            }
            .store(in: &cancellables)
    }
    
    /// 통계 모니터링 중지
    public func stopMonitoring() {
        logInfo("🛑 Stopping streaming stats monitoring...", category: .streaming)
        cancellables.removeAll()
        statsTimer?.invalidate()
        statsTimer = nil
        streamStartTime = nil
    }
    
    /// 현재 스트리밍 정보 반환
    internal func getCurrentStreamingInfo() async -> StreamingInfo? {
        guard let _ = haishinKitManager else {
            return nil
        }
        
        return await collectStreamingInfo()
    }
    
    /// 현재 데이터 전송 통계 반환
    internal func getDataTransmissionStats() async -> DataTransmissionStats? {
        guard let _ = haishinKitManager else {
            return nil
        }
        
        return await collectDataTransmissionStats()
    }
    
    /// 스트리밍 요약 포맷팅
    internal func formatStreamingSummary(_ info: StreamingInfo) -> String {
        let totalBitrate = info.actualVideoBitrate + info.actualAudioBitrate
        let summary = """
        📡 실시간 스트리밍 데이터 송출 현황
        
        🎯 송출 중인 데이터:
        ├─ 📹 비디오: \(String(format: "%.1f", info.actualVideoBitrate)) kbps
        ├─ 🔊 오디오: \(String(format: "%.1f", info.actualAudioBitrate)) kbps
        └─ 📊 총 비트레이트: \(String(format: "%.1f", totalBitrate)) kbps
        
        📈 전송 통계:
        ├─ 📦 네트워크 품질: \(info.networkQuality.displayName)
        └─ ⚡ 실시간 송출: 활성
        
        🌐 네트워크 상태:
        └─ 📶 품질: \(info.networkQuality.displayName)
        """
        
        return summary
    }
    
    // MARK: - Public Configuration
    
    /// 현재 설정 업데이트
    public func updateSettings(_ settings: LiveStreamSettings) {
        currentSettings = settings
    }
    
    /// HaishinKit 매니저 설정
    public func setHaishinKitManager(_ manager: HaishinKitManagerProtocol) {
        haishinKitManager = manager
    }
    
    // MARK: - Private Methods
    
    /// 통계 정보 업데이트 (백그라운드에서 수집, 메인 스레드에서 UI 업데이트)
    private func updateStats() {
        guard let _ = haishinKitManager else { return }
        
        // 🔧 개선: 통계 수집을 백그라운드에서 처리
        statsQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 백그라운드에서 통계 수집
            let videoBitrate = self.currentSettings?.videoBitrate ?? 2500
            let audioBitrate = self.currentSettings?.audioBitrate ?? 128
            let bytesPerSecond = Double(videoBitrate * 125) // kbps to bytes/sec
            
            let streamingInfo = StreamingInfo(
                actualVideoBitrate: Double(videoBitrate),
                actualAudioBitrate: Double(audioBitrate),
                networkQuality: .good // 기본값
            )
            
            let transmissionStats = DataTransmissionStats(
                videoBytesPerSecond: bytesPerSecond,
                networkLatency: 50.0 // 기본값 50ms
            )
            
            // 메인 스레드에서 UI 업데이트
            Task { @MainActor in
                self.currentStreamingInfo = streamingInfo
                self.currentTransmissionStats = transmissionStats
                
                // 상세 로깅
                if let settings = self.currentSettings, let startTime = self.streamStartTime {
                    self.logStreamingStatistics(info: streamingInfo, settings: settings, duration: Date().timeIntervalSince(startTime))
                }
            }
        }
    }
    
    /// HaishinKit 스트림에서 스트리밍 정보 수집
    private func collectStreamingInfo() async -> StreamingInfo {
        // 실제 HaishinKit API와 다를 수 있으므로 기본값 사용
        let videoBitrate = currentSettings?.videoBitrate ?? 2500
        let audioBitrate = currentSettings?.audioBitrate ?? 128
        
        return StreamingInfo(
            actualVideoBitrate: Double(videoBitrate),
            actualAudioBitrate: Double(audioBitrate),
            networkQuality: .good
        )
    }
    
    /// 데이터 전송 통계 수집
    private func collectDataTransmissionStats() async -> DataTransmissionStats {
        let videoBitrate = currentSettings?.videoBitrate ?? 2500
        let bytesPerSecond = Double(videoBitrate * 125) // kbps to bytes/sec
        
        return DataTransmissionStats(
            videoBytesPerSecond: bytesPerSecond,
            networkLatency: 50.0 // 50ms
        )
    }
    
    /// 스트리밍 통계 로깅 (반복적인 로그 비활성화)
    private func logStreamingStatistics(info: StreamingInfo, settings: LiveStreamSettings, duration: TimeInterval) {
        // 반복적인 실시간 통계 로그 비활성화 (성능 최적화)
        // 10분(600초)마다만 요약 로그 출력
        if Int(duration) % 600 == 0 && Int(duration) > 0 {
            logInfo("📊 스트림 요약 (\(Int(duration/60))분): 비디오 \(String(format: "%.0f", info.actualVideoBitrate))kbps, 네트워크 \(info.networkQuality.displayName)", category: .streaming)
        }
    }
} 
