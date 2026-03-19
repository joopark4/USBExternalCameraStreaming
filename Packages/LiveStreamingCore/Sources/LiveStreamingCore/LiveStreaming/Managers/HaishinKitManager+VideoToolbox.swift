import AVFoundation
import Combine
import CoreImage
import Foundation
import HaishinKit
import Network
import UIKit
import VideoToolbox
import os.log

extension HaishinKitManager {
  // MARK: - 🔧 개선: VideoToolbox 통합 기능들

  /// VideoToolbox 프리셋 설정
  public func setVideoToolboxPreset(_ preset: VideoToolboxPreset) {
    videoToolboxPreset = preset
    logger.info("🎯 VideoToolbox 프리셋 변경: \(preset.description)", category: .streaming)
  }

  /// VideoToolbox 진단 수행
  @MainActor
  public func performVideoToolboxDiagnosis() -> VideoToolboxDiagnostics {
    let diagnostics = performanceOptimizer.diagnoseVideoToolboxHealth()
    self.videoToolboxDiagnostics = diagnostics

    logger.info("🔧 VideoToolbox 진단 완료:", category: .streaming)
    logger.info(diagnostics.description, category: .streaming)

    // 진단 결과에 따른 자동 최적화 제안
    if !diagnostics.hardwareAccelerationSupported {
      logger.warning("⚠️ 하드웨어 가속 미지원 - 소프트웨어 인코딩으로 전환 권장", category: .streaming)
    }

    if diagnostics.compressionErrorRate > 0.05 {  // 5% 이상 오류율
      logger.warning("⚠️ 높은 압축 오류율 감지 - 설정 조정 권장", category: .streaming)
    }

    return diagnostics
  }

  /// 실시간 VideoToolbox 성능 리포트 생성
  @MainActor
  public func generateVideoToolboxPerformanceReport() -> VideoToolboxPerformanceMetrics {
    let metrics = performanceOptimizer.generatePerformanceReport()

    // 성능 상태에 따른 로깅
    switch metrics.performanceStatus {
    case .good:
      logger.debug(
        "✅ VideoToolbox 성능 양호: \(metrics.performanceStatus.description)", category: .streaming)
    case .warning:
      logger.warning(
        "⚠️ VideoToolbox 성능 주의: \(metrics.performanceStatus.description)", category: .streaming)
    case .poor:
      logger.error(
        "❌ VideoToolbox 성능 불량: \(metrics.performanceStatus.description)", category: .streaming)
    }

    return metrics
  }

  /// 🔧 개선: VideoToolbox 성능 모니터링 시작
  func startVideoToolboxPerformanceMonitoring() async {
    logger.info("📊 VideoToolbox 성능 모니터링 시작", category: .streaming)

    // VideoToolbox 관련 Notification 수신 설정
    NotificationCenter.default.addObserver(
      forName: .videoToolboxError,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.handleVideoToolboxError(notification)
    }

    NotificationCenter.default.addObserver(
      forName: .videoToolboxMemoryWarning,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.handleVideoToolboxMemoryWarning(notification)
    }

    NotificationCenter.default.addObserver(
      forName: .videoToolboxPerformanceAlert,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.handleVideoToolboxPerformanceAlert(notification)
    }
  }

  /// VideoToolbox 오류 처리
  func handleVideoToolboxError(_ notification: Notification) {
    logger.error("❌ VideoToolbox 오류 수신: \(notification.userInfo ?? [:])", category: .streaming)

    // 오류 복구 시도
    Task {
      await handleVideoToolboxRecovery()
    }
  }

  /// VideoToolbox 메모리 경고 처리
  func handleVideoToolboxMemoryWarning(_ notification: Notification) {
    logger.warning("⚠️ VideoToolbox 메모리 경고 수신", category: .streaming)

    // 메모리 최적화 수행
    Task {
      await performMemoryOptimization()
    }
  }

  /// VideoToolbox 성능 알림 처리
  func handleVideoToolboxPerformanceAlert(_ notification: Notification) {
    guard let metrics = notification.userInfo?["metrics"] as? VideoToolboxPerformanceMetrics,
      let status = notification.userInfo?["status"] as? PerformanceStatus
    else {
      return
    }

    logger.info("📊 VideoToolbox 성능 알림: \(status.description)", category: .streaming)

    // 성능 상태에 따른 대응
    switch status {
    case .poor:
      Task {
        await handlePoorPerformance(metrics)
      }
    case .warning:
      logger.warning(
        "⚠️ VideoToolbox 성능 주의: CPU \(metrics.cpuUsage)%, 메모리 \(metrics.memoryUsage)MB",
        category: .streaming)
    case .good:
      logger.debug("✅ VideoToolbox 성능 양호", category: .streaming)
    }
  }

  /// VideoToolbox 복구 처리
  func handleVideoToolboxRecovery() async {
    logger.info("🔧 VideoToolbox 복구 시도", category: .streaming)

    // 현재 설정을 사용하여 VideoToolbox 재설정 (iOS 17.4 이상에서만)
    if let settings = currentSettings {
      if #available(iOS 17.4, *) {
        do {
          try await performanceOptimizer.setupHardwareCompressionWithRecovery(settings: settings)
          logger.info("✅ VideoToolbox 복구 성공", category: .streaming)
        } catch {
          logger.error("❌ VideoToolbox 복구 실패: \(error)", category: .streaming)
        }
      } else {
        logger.info("📱 iOS 17.4 미만 - VideoToolbox 고급 복구 기능 미사용", category: .streaming)
      }
    }
  }

  /// 메모리 최적화 수행
  func performMemoryOptimization() async {
    logger.info("🧹 VideoToolbox 메모리 최적화 수행", category: .streaming)

    // 필요시 품질 조정을 통한 메모리 압박 완화
    if let settings = currentSettings, let originalSettings = originalUserSettings {
      let optimizedSettings = await performanceOptimizer.adaptQualityRespectingUserSettings(
        currentSettings: settings,
        userDefinedSettings: originalSettings
      )

      // 메모리 최적화를 위한 임시 설정 적용
      if optimizedSettings.videoBitrate != settings.videoBitrate {
        logger.info(
          "🔽 메모리 최적화를 위한 임시 품질 조정: \(settings.videoBitrate) → \(optimizedSettings.videoBitrate)kbps",
          category: .streaming)
      }
    }
  }

  /// 성능 불량 상황 처리
  func handlePoorPerformance(_ metrics: VideoToolboxPerformanceMetrics) async {
    logger.warning("⚠️ VideoToolbox 성능 불량 감지 - 자동 최적화 수행", category: .streaming)
    logger.warning(
      "  CPU: \(metrics.cpuUsage)%, 메모리: \(metrics.memoryUsage)MB, 오류율: \(metrics.errorRate)",
      category: .streaming)

    // 성능 문제 대응 전략
    if metrics.errorRate > 0.1 {  // 10% 이상 오류율
      await handleVideoToolboxRecovery()
    }

    if metrics.cpuUsage > 80 || metrics.memoryUsage > 500 {
      await performMemoryOptimization()
    }

    // 심각한 성능 문제 시 사용자에게 알림
    if metrics.compressionTime > 0.1 {  // 100ms 이상
      logger.error("❌ 심각한 성능 문제 - 사용자 개입 필요", category: .streaming)

      // UI 알림 발송
      DispatchQueue.main.async { [weak self] in
        self?.connectionStatus = "⚠️ 성능 문제 감지 - 설정 확인 필요"
      }
    }
  }

}
