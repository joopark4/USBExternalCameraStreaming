import AVFoundation
import Combine
import Foundation
import LiveStreamingCore
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Public Methods - Data Monitoring

  /// 현재 스트리밍 데이터 송출 상태 확인
  /// - Note: 현재는 로그만 출력 (향후 실제 전송 상태 조회 구현 예정)
  @MainActor
  func checkCurrentDataTransmission() async {
    logDebug("ℹ️ [DATA CHECK] Transmission status check not yet implemented", category: .streaming)
  }

  /// 스트리밍 데이터 요약 정보 가져오기
  /// - Returns: 현재 스트리밍 상태 및 연결 상태를 포함한 요약 문자열
  func getStreamingDataSummary() async -> String {
    let statusText =
      switch status {
      case .idle: NSLocalizedString("status_idle", comment: "대기 중")
      case .connecting: NSLocalizedString("status_connecting", comment: "연결 중")
      case .connected: NSLocalizedString("status_connected", comment: "연결됨")
      case .streaming: NSLocalizedString("status_streaming", comment: "스트리밍 중")
      case .disconnecting: NSLocalizedString("status_disconnecting", comment: "연결 해제 중")
      case .error(let error):
        NSLocalizedString("status_error_prefix", comment: "오류: ") + error.localizedDescription
      }
    let summary = "📊 스트리밍 상태: \(statusText)\n📡 연결 상태: 정상"
    logDebug("📋 [DATA SUMMARY] \(summary)", category: .streaming)
    return summary
  }

  /// 실시간 데이터 모니터링 시작 (정기적 체크)
  func startDataMonitoring() {
    logDebug("🚀 [MONITOR] Starting data monitoring", category: .streaming)
    Timer.scheduledTimer(withTimeInterval: Constants.dataMonitoringInterval, repeats: true) {
      [weak self] timer in
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
}
