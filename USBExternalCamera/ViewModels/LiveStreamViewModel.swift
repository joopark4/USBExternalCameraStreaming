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

/// 라이브 스트리밍 뷰모델
/// HaishinKit을 사용한 유튜브 라이브 스트리밍을 관리합니다.
@MainActor
final class LiveStreamViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 현재 스트리밍 설정
    @Published var settings: LiveStreamSettings
    
    /// 스트리밍 상태
    @Published var streamingStatus: LiveStreamStatus = .idle
    
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
    
    /// 스트리밍 가능 여부 (카메라 선택됨 + 설정 완료)
    @Published var canStartStreaming: Bool = false
    
    // MARK: - Private Properties
    
    /// 라이브 스트림 매니저
    private let liveStreamManager = LiveStreamManager()
    
    /// 모델 컨텍스트
    private let modelContext: ModelContext
    
    /// Combine 구독 저장소
    private var cancellables = Set<AnyCancellable>()
    
    /// 현재 카메라 캡처 세션
    private var currentCaptureSession: AVCaptureSession?
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        // 기본 설정으로 임시 초기화
        self.settings = LiveStreamSettings()
        
        // 저장된 설정 로드 또는 기본 설정 생성
        self.settings = loadOrCreateSettings()
        
        setupBindings()
        updateStreamingAvailability()
    }
    
    // MARK: - Public Methods
    
    /// 라이브 스트리밍 시작
    /// - Parameter captureSession: 카메라 캡처 세션
    func startStreaming(with captureSession: AVCaptureSession) {
        guard canStartStreaming else {
            showError("스트리밍을 시작할 수 없습니다. 설정을 확인해주세요.")
            return
        }
        
        currentCaptureSession = captureSession
        
        Task {
            await liveStreamManager.startStreaming(with: settings, captureSession: captureSession)
        }
    }
    
    /// 라이브 스트리밍 중지
    func stopStreaming() {
        Task {
            await liveStreamManager.stopStreaming()
        }
    }
    
    /// 스트리밍 설정 저장
    func saveSettings() {
        settings.updatedAt = Date()
        
        do {
            try modelContext.save()
        } catch {
            showError("설정 저장에 실패했습니다: \(error.localizedDescription)")
        }
        
        updateStreamingAvailability()
        
        // 스트리밍 중인 경우 설정 업데이트
        if streamingStatus == .streaming {
            Task {
                await liveStreamManager.updateSettings(settings)
            }
        }
    }
    
    /// 스트리밍 토글 (시작/중지)
    /// - Parameter captureSession: 카메라 캡처 세션
    func toggleStreaming(with captureSession: AVCaptureSession) {
        switch streamingStatus {
        case .idle:
            startStreaming(with: captureSession)
        case .streaming, .connected, .connecting:
            stopStreaming()
        default:
            break
        }
    }
    
    /// 스트림 키 유효성 검사
    /// - Parameter streamKey: 검사할 스트림 키
    /// - Returns: 유효성 검사 결과
    func validateStreamKey(_ streamKey: String) -> Bool {
        // 유튜브 스트림 키는 일반적으로 16-24자의 영숫자와 하이픈으로 구성
        let pattern = "^[a-zA-Z0-9\\-]{16,24}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: streamKey.utf16.count)
        return regex?.firstMatch(in: streamKey, options: [], range: range) != nil
    }
    
    /// RTMP URL 유효성 검사
    /// - Parameter url: 검사할 URL
    /// - Returns: 유효성 검사 결과
    func validateRTMPURL(_ url: String) -> Bool {
        url.hasPrefix("rtmp://") && !url.isEmpty
    }
    
    /// 설정 초기화
    func resetSettings() {
        settings = LiveStreamSettings()
        settings.rtmpURL = "rtmp://a.rtmp.youtube.com/live2/"
        saveSettings()
    }
    
    /// 스트리밍 통계 포맷팅
    /// - Returns: 포맷된 통계 문자열
    func formatStreamStats() -> String {
        let stats = streamStats
        return """
        비디오: \(String(format: "%.1f", stats.videoBitrate)) kbps
        오디오: \(String(format: "%.1f", stats.audioBitrate)) kbps
        프레임률: \(String(format: "%.1f", stats.frameRate)) fps
        드롭 프레임: \(stats.droppedFrames)
        """
    }
    
    // MARK: - Private Methods
    
    /// 저장된 설정 로드 또는 새로운 설정 생성
    /// - Returns: 라이브 스트림 설정
    private func loadOrCreateSettings() -> LiveStreamSettings {
        let descriptor = FetchDescriptor<LiveStreamSettings>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        do {
            let existingSettings = try modelContext.fetch(descriptor)
            if let settings = existingSettings.first {
                return settings
            }
        } catch {
            print("설정 로드 실패: \(error)")
        }
        
        // 기본 설정 생성
        let newSettings = LiveStreamSettings()
        newSettings.rtmpURL = "rtmp://a.rtmp.youtube.com/live2/"
        modelContext.insert(newSettings)
        
        do {
            try modelContext.save()
        } catch {
            print("기본 설정 저장 실패: \(error)")
        }
        
        return newSettings
    }
    
    /// 바인딩 설정
    private func setupBindings() {
        // LiveStreamManager의 상태를 뷰모델에 바인딩
        liveStreamManager.$status
            .receive(on: DispatchQueue.main)
            .assign(to: \.streamingStatus, on: self)
            .store(in: &cancellables)
        
        liveStreamManager.$statusMessage
            .receive(on: DispatchQueue.main)
            .assign(to: \.statusMessage, on: self)
            .store(in: &cancellables)
        
        liveStreamManager.$streamStats
            .receive(on: DispatchQueue.main)
            .assign(to: \.streamStats, on: self)
            .store(in: &cancellables)
        
        liveStreamManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] errorMessage in
                if let error = errorMessage {
                    self?.showError(error)
                }
            }
            .store(in: &cancellables)
    }
    
    /// 스트리밍 가능 여부 업데이트
    private func updateStreamingAvailability() {
        canStartStreaming = !settings.streamKey.isEmpty && 
                           validateStreamKey(settings.streamKey) && 
                           validateRTMPURL(settings.rtmpURL)
    }
    
    /// 오류 표시
    /// - Parameter message: 오류 메시지
    private func showError(_ message: String) {
        currentErrorMessage = message
        showingErrorAlert = true
    }
}

// MARK: - Supporting Extensions

extension LiveStreamViewModel {
    
    /// 스트리밍 상태에 따른 컨트롤 버튼 텍스트
    var streamControlButtonText: String {
        switch streamingStatus {
        case .idle:
            return "스트리밍 시작"
        case .connecting:
            return "연결 중..."
        case .connected:
            return "준비됨"
        case .streaming:
            return "스트리밍 중지"
        case .disconnecting:
            return "중지 중..."
        case .error:
            return "다시 시도"
        }
    }
    
    /// 스트리밍 상태에 따른 컨트롤 버튼 색상
    var streamControlButtonColor: Color {
        switch streamingStatus {
        case .idle, .error:
            return .blue
        case .connecting, .disconnecting:
            return .gray
        case .connected:
            return .green
        case .streaming:
            return .red
        }
    }
    
    /// 컨트롤 버튼 활성화 여부
    var isStreamControlButtonEnabled: Bool {
        switch streamingStatus {
        case .connecting, .disconnecting:
            return false
        default:
            return true
        }
    }
} 