//
//  LiveStreamingTests.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 6/5/25.
//

import XCTest
@testable import USBExternalCamera
import LiveStreamingCore

/// `HaishinKitManager` / `StreamingStatsManager` / `NetworkMonitoringManager` 의 **초기 상태**
/// 와 시작/중지 사이클 전후의 관측 가능한 필드만 검증한다.
///
/// 의도적으로 실제 RTMP 연결을 요구하는 시나리오는 포함하지 않는다.
/// (이전 버전은 `rtmp://test.youtube.com/live2/` 에 hand-shake 를 시도해 CI 러너에서
/// 타임아웃/블록 됐음.) 네트워크 연결이 들어가는 통합 테스트는 실기기 smoke 로 다룬다.
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

    // MARK: - HaishinKitManager
    //
    // `connectionStatus` 는 사용자-대면 로컬라이즈 문자열("준비됨" 등)이라 안정적 단위 테스트
    // 기준으로는 부적합하다. 대신 `isStreaming` bool 과 `isScreenCaptureMode` 같은
    // 안정된 API 를 기준으로 invariants 를 검증한다.

    func testHaishinKitManagerInitialStateIsNotStreaming() {
        XCTAssertFalse(haishinKitManager.isStreaming)
        XCTAssertFalse(haishinKitManager.isScreenCaptureMode)
    }

    func testStopStreamingIsSafeBeforeStart() async {
        // 시작된 적 없어도 stop 호출이 상태 불변식을 깨지 않아야 한다.
        await haishinKitManager.stopStreaming()
        XCTAssertFalse(haishinKitManager.isStreaming)
        XCTAssertFalse(haishinKitManager.isScreenCaptureMode)
    }

    // MARK: - StreamingStatsManager

    func testStreamingStatsManagerInitialState() {
        XCTAssertNil(streamingStatsManager.currentStreamingInfo)
        XCTAssertNil(streamingStatsManager.currentTransmissionStats)
    }

    func testStreamingStatsManagerStartStopIsSafe() {
        streamingStatsManager.startMonitoring()
        // 스트리밍 미시작 상태이므로 info 는 여전히 nil 이어야 함.
        XCTAssertNil(streamingStatsManager.currentStreamingInfo)
        streamingStatsManager.stopMonitoring()
    }

    // MARK: - NetworkMonitoringManager

    func testNetworkMonitoringManagerProducesQualityReading() async {
        // 초기값 존재 확인
        XCTAssertNotNil(networkMonitoringManager.currentNetworkQuality)

        networkMonitoringManager.startMonitoring()
        XCTAssertNotNil(networkMonitoringManager.currentNetworkQuality)

        await networkMonitoringManager.assessNetworkQuality()
        XCTAssertNotNil(networkMonitoringManager.currentNetworkQuality)

        networkMonitoringManager.stopMonitoring()
        XCTAssertNotNil(networkMonitoringManager.currentNetworkQuality)
    }
}
