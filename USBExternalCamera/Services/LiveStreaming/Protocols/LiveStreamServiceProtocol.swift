//
//  LiveStreamServiceProtocol.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation
import Combine
import HaishinKit

/// 라이브 스트리밍 서비스 프로토콜
public protocol LiveStreamServiceProtocol: AnyObject {
    /// 현재 스트리밍 상태
    var status: LiveStreamStatus { get }
    
    /// 현재 스트리밍 정보
    var streamingInfo: StreamingInfo? { get }
    
    /// 현재 전송 통계
    var transmissionStats: DataTransmissionStats? { get }
    
    /// 현재 네트워크 품질
    var networkQuality: NetworkQuality { get }
    
    /// 현재 연결 테스트 결과
    var connectionTestResult: ConnectionTestResult? { get }
    
    /// 현재 스트리밍 추천 설정
    var recommendations: StreamingRecommendations? { get }
    
    // 기존 일반 스트리밍 메서드들 제거 - 화면 캡처 스트리밍만 사용
    
    /// 연결 테스트
    func testConnection(to settings: USBExternalCamera.LiveStreamSettings) async -> ConnectionTestResult
    
    /// 설정 로드
    func loadSettings() -> USBExternalCamera.LiveStreamSettings?
    
    /// 설정 저장
    func saveSettings(_ settings: USBExternalCamera.LiveStreamSettings)
    
    /// 설정 내보내기
    func exportSettings() -> Data?
    
    /// 설정 가져오기
    func importSettings(from data: Data) -> USBExternalCamera.LiveStreamSettings?
}

// HaishinKitManagerProtocol은 HaishinKitManager.swift에서 정의됨

/// 스트리밍 통계 매니저 프로토콜
public protocol StreamingStatsManagerProtocol: AnyObject {
    /// 현재 스트리밍 정보
    var currentStreamingInfo: StreamingInfo? { get }
    
    /// 현재 전송 통계
    var currentTransmissionStats: DataTransmissionStats? { get }
    
    /// HaishinKit 매니저 설정
    func setHaishinKitManager(_ manager: HaishinKitManagerProtocol)
    
    /// 설정 업데이트
    func updateSettings(_ settings: USBExternalCamera.LiveStreamSettings)
    
    /// 모니터링 시작
    func startMonitoring()
    
    /// 모니터링 중지
    func stopMonitoring()
}

/// 네트워크 모니터링 매니저 프로토콜
public protocol NetworkMonitoringManagerProtocol: AnyObject {
    /// 현재 네트워크 품질
    var currentNetworkQuality: NetworkQuality { get }
    
    /// 모니터링 시작
    func startMonitoring()
    
    /// 모니터링 중지
    func stopMonitoring()
    
    /// 네트워크 품질 평가
    func assessNetworkQuality() async
} 