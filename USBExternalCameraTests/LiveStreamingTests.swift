//
//  LiveStreamingTests.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 6/5/25.
//

import XCTest
@testable import USBExternalCamera

@MainActor
final class LiveStreamingTests: XCTestCase {
    
    private var haishinKitManager: HaishinKitManager!
    private var streamingStatsManager: StreamingStatsManager!
    private var networkMonitoringManager: NetworkMonitoringManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        haishinKitManager = HaishinKitManager()
        streamingStatsManager = StreamingStatsManager()
        networkMonitoringManager = NetworkMonitoringManager()
        
        // 매니저 간 의존성 설정
        streamingStatsManager.setHaishinKitManager(haishinKitManager)
    }
    
    override func tearDown() async throws {
        await haishinKitManager.stopStreaming()
        streamingStatsManager.stopMonitoring()
        networkMonitoringManager.stopMonitoring()
        
        haishinKitManager = nil
        streamingStatsManager = nil
        networkMonitoringManager = nil
        
        try await super.tearDown()
    }
    
    func testHaishinKitManager() async throws {
        // 초기 상태 확인
        let connectionStatus = haishinKitManager.connectionStatus
        XCTAssertEqual(connectionStatus, "idle")
        
        // 스트리밍 시작 테스트
        var testSettings = USBExternalCamera.LiveStreamSettings()
        testSettings.rtmpURL = "rtmp://test.youtube.com/live2/"
        testSettings.streamKey = "test-stream-key"
        testSettings.videoBitrate = 2500
        testSettings.audioBitrate = 128
        
        do {
            try await haishinKitManager.startScreenCaptureStreaming(with: testSettings)
            let status = haishinKitManager.connectionStatus
            XCTAssertEqual(status, "streaming")
            
            await haishinKitManager.stopStreaming()
            let finalStatus = haishinKitManager.connectionStatus
            XCTAssertEqual(finalStatus, "idle")
        } catch {
            XCTFail("Streaming start failed: \(error)")
        }
    }
    
    func testStreamingStatsManager() async throws {
        let currentStats = streamingStatsManager.currentStreamingInfo
        XCTAssertNil(currentStats)
        
        let transmissionStats = streamingStatsManager.currentTransmissionStats
        XCTAssertNil(transmissionStats)
        
        streamingStatsManager.startMonitoring()
        
        // 모니터링 시작 후 기본값 확인
        let statsAfterStart = streamingStatsManager.currentStreamingInfo
        XCTAssertNil(statsAfterStart) // 아직 스트리밍이 시작되지 않았으므로 nil
        
        streamingStatsManager.stopMonitoring()
    }
    
    func testNetworkMonitoringManager() async throws {
        let initialQuality = networkMonitoringManager.currentNetworkQuality
        XCTAssertNotNil(initialQuality)
        
        networkMonitoringManager.startMonitoring()
        let qualityAfterStart = networkMonitoringManager.currentNetworkQuality
        XCTAssertNotNil(qualityAfterStart)
        
        networkMonitoringManager.stopMonitoring()
        let qualityAfterStop = networkMonitoringManager.currentNetworkQuality
        XCTAssertNotNil(qualityAfterStop)
        
        await networkMonitoringManager.assessNetworkQuality()
        let assessedQuality = networkMonitoringManager.currentNetworkQuality
        XCTAssertNotNil(assessedQuality)
    }
    
    func testIntegration() async throws {
        networkMonitoringManager.startMonitoring()
        streamingStatsManager.startMonitoring()
        
        var testSettings = USBExternalCamera.LiveStreamSettings()
        testSettings.rtmpURL = "rtmp://test.youtube.com/live2/"
        testSettings.streamKey = "test-stream-key"
        testSettings.videoBitrate = 2500
        testSettings.audioBitrate = 128
        
        do {
            try await haishinKitManager.startScreenCaptureStreaming(with: testSettings)
            
            // 잠시 대기 후 상태 확인
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1초
            
            let connectionStatus = haishinKitManager.connectionStatus
            XCTAssertEqual(connectionStatus, "streaming")
            let networkQuality = networkMonitoringManager.currentNetworkQuality
            XCTAssertNotNil(networkQuality)
            
            await haishinKitManager.stopStreaming()
            let finalStatus = haishinKitManager.connectionStatus
            XCTAssertEqual(finalStatus, "idle")
        } catch {
            XCTFail("Integration test failed: \(error)")
        }
        
        networkMonitoringManager.stopMonitoring()
        streamingStatsManager.stopMonitoring()
    }
} 