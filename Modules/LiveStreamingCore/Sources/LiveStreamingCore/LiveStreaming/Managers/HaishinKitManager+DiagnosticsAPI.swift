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
  // MARK: - 진단 시스템 공개 인터페이스

  /// 🔍 간단한 스트리밍 상태 체크 (UI용)
  public func quickHealthCheck() -> (score: Int, status: String, issues: [String]) {
    var issues: [String] = []
    var score = 100

    // 기본 상태 체크
    if !isStreaming {
      issues.append("스트리밍이 시작되지 않음")
      score -= 30
    }

    if currentRTMPStream == nil {
      issues.append("RTMP 연결이 설정되지 않음")
      score -= 25
    }

    if screenCaptureStats.frameCount == 0 {
      issues.append("화면 캡처 데이터가 없음")
      score -= 25
    }

    if reconnectAttempts > 0 {
      issues.append("재연결 시도 중 (\(reconnectAttempts)회)")
      score -= 10
    }

    if connectionFailureCount > 0 {
      issues.append("연결 실패 감지됨 (\(connectionFailureCount)회)")
      score -= 10
    }

    let status: String
    switch score {
    case 90...100: status = "완벽"
    case 70...89: status = "양호"
    case 50...69: status = "보통"
    case 30...49: status = "불량"
    default: status = "심각"
    }

    return (max(0, score), status, issues)
  }

  /// 📊 스트리밍 파이프라인 진단 (콘솔 출력)
  public func diagnoseStreamingPipeline() async {
    let report = await performComprehensiveStreamingDiagnosis()

    logInfo("═══════════════════════════════════════", category: .performance)
    logInfo("HaishinKit 스트리밍 진단 결과", category: .performance)
    logInfo("═══════════════════════════════════════", category: .performance)
    logInfo("종합 점수: \(report.overallScore)점/100점 (\(report.overallGrade))", category: .performance)
    logInfo("", category: .performance)
    logInfo("💡 평가: \(report.getRecommendation())", category: .performance)
    logInfo("═══════════════════════════════════════", category: .performance)
  }

  /// 🎯 실시간 모니터링 데이터 요약 (UI용)
  public func getRealtimeMonitoringSummary() -> [String: Any] {
    return [
      "isStreaming": isStreaming,
      "isScreenCaptureMode": isScreenCaptureMode,
      "frameCount": screenCaptureStats.frameCount,
      "successCount": screenCaptureStats.successCount,
      "currentFPS": screenCaptureStats.currentFPS,
      "reconnectAttempts": reconnectAttempts,
      "connectionFailures": connectionFailureCount,
      "hasRTMPStream": currentRTMPStream != nil,
      "networkLatency": transmissionStats.networkLatency,
      "totalBytesTransmitted": transmissionStats.totalBytesTransmitted,
      "cpuUsage": performanceOptimizer.currentCPUUsage,
      "memoryUsage": performanceOptimizer.currentMemoryUsage,
      "gpuUsage": performanceOptimizer.currentGPUUsage,
      "frameProcessingTime": performanceOptimizer.frameProcessingTime,
    ]
  }

  /// 성능 최적화 상태 정보 조회 (UI용)
  public func getPerformanceOptimizationStatus() -> [String: Any] {
    return [
      "cpuUsage": performanceOptimizer.currentCPUUsage,
      "memoryUsage": performanceOptimizer.currentMemoryUsage,
      "gpuUsage": performanceOptimizer.currentGPUUsage,
      "frameProcessingTime": performanceOptimizer.frameProcessingTime * 1000,  // ms로 변환
      "performanceGrade": getPerformanceGrade(),
      "recommendations": getPerformanceRecommendations(),
    ]
  }

  /// 성능 등급 계산
  func getPerformanceGrade() -> String {
    let cpuScore = max(0, 100 - performanceOptimizer.currentCPUUsage)
    let memoryScore = max(0, 100 - (performanceOptimizer.currentMemoryUsage / 10))  // 1000MB = 0점
    let processingScore = max(0, 100 - (performanceOptimizer.frameProcessingTime * 10000))  // 10ms = 0점

    let overallScore = (cpuScore + memoryScore + processingScore) / 3.0

    switch overallScore {
    case 80...100: return "우수 (A)"
    case 60...79: return "양호 (B)"
    case 40...59: return "보통 (C)"
    case 20...39: return "개선 필요 (D)"
    default: return "성능 문제 (F)"
    }
  }

  /// 성능 개선 권장사항
  func getPerformanceRecommendations() -> [String] {
    var recommendations: [String] = []

    if performanceOptimizer.currentCPUUsage > 70 {
      recommendations.append("CPU 사용량이 높습니다. 다른 앱을 종료하거나 스트리밍 품질을 낮춰보세요.")
    }

    if performanceOptimizer.currentMemoryUsage > 400 {
      recommendations.append("메모리 사용량이 높습니다. 앱을 재시작하거나 해상도를 낮춰보세요.")
    }

    if performanceOptimizer.frameProcessingTime > 0.033 {  // > 30ms
      recommendations.append("프레임 처리 시간이 깁니다. GPU 가속이 활성화되어 있는지 확인하세요.")
    }

    if recommendations.isEmpty {
      recommendations.append("현재 성능이 양호합니다. 최적의 스트리밍 상태입니다.")
    }

    return recommendations
  }

  /// 🔧 스트리밍 문제 해결 가이드 생성
  public func generateTroubleshootingGuide() async -> String {
    let report = await performComprehensiveStreamingDiagnosis()
    var guide = "🔧 스트리밍 문제 해결 가이드\n\n"

    // 설정 문제
    if !report.configValidation.isValid {
      guide += "1️⃣ 설정 문제 해결:\n"
      for issue in report.configValidation.issues {
        guide += "   • \(issue)\n"
      }
      guide += "\n"
    }

    // 연결 문제
    if !report.rtmpStreamStatus.isValid {
      guide += "2️⃣ RTMP 연결 문제 해결:\n"
      for issue in report.rtmpStreamStatus.issues {
        guide += "   • \(issue)\n"
      }
      guide += "   💡 YouTube Studio에서 '스트리밍 시작' 버튼을 클릭했는지 확인\n\n"
    }

    // 화면 캡처 문제
    if !report.screenCaptureStatus.isValid {
      guide += "3️⃣ 화면 캡처 문제 해결:\n"
      for issue in report.screenCaptureStatus.issues {
        guide += "   • \(issue)\n"
      }
      guide += "   💡 CameraPreviewUIView의 화면 캡처 타이머 상태 확인 필요\n\n"
    }

    // 네트워크 문제
    if !report.networkStatus.isValid {
      guide += "4️⃣ 네트워크 문제 해결:\n"
      for issue in report.networkStatus.issues {
        guide += "   • \(issue)\n"
      }
      guide += "   💡 Wi-Fi 연결 상태와 방화벽 설정을 확인해주세요\n\n"
    }

    // 전반적인 권장사항
    guide += "🎯 일반적인 해결 방법:\n"
    guide += "   1. YouTube Studio에서 라이브 스트리밍 시작\n"
    guide += "   2. 스트림 키가 올바른지 확인\n"
    guide += "   3. 네트워크 연결 상태 점검\n"
    guide += "   4. 다른 스트리밍 프로그램 종료\n"
    guide += "   5. 앱 재시작 후 다시 시도\n"

    return guide
  }

}
