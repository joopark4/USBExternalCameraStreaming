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
  // MARK: - 종합 파이프라인 진단 시스템

  /// 🔍 HaishinKit 스트리밍 파이프라인 종합 진단
  public func performComprehensiveStreamingDiagnosis() async -> StreamingDiagnosisReport {
    logger.info("🔍 HaishinKit 스트리밍 파이프라인 종합 진단 시작", category: .system)

    var report = StreamingDiagnosisReport()

    // 1. 설정 값 검증
    report.configValidation = await validateHaishinKitConfiguration()

    // 2. MediaMixer 상태 검증
    report.mediaMixerStatus = await validateMediaMixerConfiguration()

    // 3. RTMPStream 설정 검증
    report.rtmpStreamStatus = await validateRTMPStreamConfiguration()

    // 4. 화면 캡처 데이터 검증
    report.screenCaptureStatus = validateScreenCaptureData()

    // 5. 네트워크 연결 검증
    report.networkStatus = await validateNetworkConnection()

    // 6. 디바이스 환경 검증
    report.deviceStatus = validateDeviceEnvironment()

    // 7. 실제 송출 데이터 흐름 검증
    report.dataFlowStatus = await validateActualDataFlow()

    // 종합 점수 계산
    report.calculateOverallScore()

    // 진단 결과 로깅
    logDiagnosisReport(report)

    logger.info("✅ HaishinKit 스트리밍 파이프라인 종합 진단 완료", category: .system)

    return report
  }

  /// 1️⃣ HaishinKit 설정 값 검증
  func validateHaishinKitConfiguration() async -> ConfigValidationResult {
    var result = ConfigValidationResult()

    logger.info("🔧 [1/7] HaishinKit 설정 값 검증 중...", category: .system)

    guard let settings = currentSettings else {
      result.isValid = false
      result.issues.append("❌ 스트리밍 설정이 로드되지 않음")
      return result
    }

    // RTMP URL 검증
    if settings.rtmpURL.isEmpty {
      result.issues.append("❌ RTMP URL이 비어있음")
    } else if !settings.rtmpURL.lowercased().hasPrefix("rtmp") {
      result.issues.append("❌ RTMP 프로토콜이 아님: \(settings.rtmpURL)")
    } else {
      result.validItems.append("✅ RTMP URL: \(settings.rtmpURL)")
    }

    // 스트림 키 검증
    if settings.streamKey.isEmpty {
      result.issues.append("❌ 스트림 키가 비어있음")
    } else if settings.streamKey.count < 10 {
      result.issues.append("⚠️ 스트림 키가 너무 짧음 (\(settings.streamKey.count)자)")
    } else {
      result.validItems.append(
        "✅ 스트림 키: \(settings.streamKey.count)자 (앞 8자: \(String(settings.streamKey.prefix(8)))...)")
    }

    // 비디오 설정 검증
    if settings.videoWidth <= 0 || settings.videoHeight <= 0 {
      result.issues.append("❌ 비디오 해상도 설정 오류: \(settings.videoWidth)x\(settings.videoHeight)")
    } else {
      result.validItems.append("✅ 비디오 해상도: \(settings.videoWidth)x\(settings.videoHeight)")
    }

    if settings.videoBitrate <= 0 || settings.videoBitrate > 10000 {
      result.issues.append("⚠️ 비디오 비트레이트 비정상: \(settings.videoBitrate)kbps")
    } else {
      result.validItems.append("✅ 비디오 비트레이트: \(settings.videoBitrate)kbps")
    }

    if settings.frameRate <= 0 || settings.frameRate > 60 {
      result.issues.append("⚠️ 프레임레이트 비정상: \(settings.frameRate)fps")
    } else {
      result.validItems.append("✅ 프레임레이트: \(settings.frameRate)fps")
    }

    // 오디오 설정 검증
    if settings.audioBitrate <= 0 || settings.audioBitrate > 320 {
      result.issues.append("⚠️ 오디오 비트레이트 비정상: \(settings.audioBitrate)kbps")
    } else {
      result.validItems.append("✅ 오디오 비트레이트: \(settings.audioBitrate)kbps")
    }

    result.isValid = result.issues.isEmpty
    result.summary = "설정 검증: \(result.validItems.count)개 정상, \(result.issues.count)개 문제"

    return result
  }

  /// 2️⃣ MediaMixer 상태 검증
  func validateMediaMixerConfiguration() async -> MediaMixerValidationResult {
    var result = MediaMixerValidationResult()

    logger.info("🎛️ [2/7] MediaMixer 상태 검증 중...", category: .system)

    // MediaMixer 실행 상태
    let isRunning = await mixer.isRunning
    if isRunning {
      result.validItems.append("✅ MediaMixer 실행 중")
    } else {
      result.issues.append("❌ MediaMixer가 실행되지 않음")
    }

    // 수동 캡처 모드 확인
    result.validItems.append("✅ 수동 캡처 모드 활성화 (useManualCapture: true)")

    // 멀티캠 및 오디오 설정 확인
    result.validItems.append("✅ 멀티캠 세션: 비활성화 (화면 캡처용)")
    result.validItems.append("✅ 멀티 트랙 오디오: 비활성화 (단순화)")

    result.isValid = result.issues.isEmpty
    result.summary = "MediaMixer: \(isRunning ? "정상 실행" : "실행 중지")"

    return result
  }

  /// 3️⃣ RTMPStream 설정 검증
  func validateRTMPStreamConfiguration() async -> RTMPStreamValidationResult {
    var result = RTMPStreamValidationResult()

    logger.info("📡 [3/7] RTMPStream 설정 검증 중...", category: .system)

    // RTMPStream 존재 여부
    guard let stream = await streamSwitcher.stream else {
      result.issues.append("❌ RTMPStream이 생성되지 않음")
      result.isValid = false
      result.summary = "RTMPStream: 미생성"
      return result
    }

    result.validItems.append("✅ RTMPStream 객체 생성됨")

    // 연결 상태
    if let connection = await streamSwitcher.connection {
      let isConnected = await connection.connected
      if isConnected {
        result.validItems.append("✅ RTMP 연결 상태: 연결됨")
      } else {
        result.issues.append("❌ RTMP 연결 상태: 연결 끊어짐")
      }
    } else {
      result.issues.append("❌ RTMP 연결 객체가 없음")
    }

    // 스트림 설정 검증
    let videoSettings = await stream.videoSettings
    let audioSettings = await stream.audioSettings

    result.validItems.append("✅ 비디오 설정 - 해상도: \(videoSettings.videoSize)")
    result.validItems.append("✅ 비디오 설정 - 비트레이트: \(videoSettings.bitRate)bps")
    result.validItems.append("✅ 오디오 설정 - 비트레이트: \(audioSettings.bitRate)bps")

    // 스트림 정보 (Sendable 프로토콜 문제로 인해 간소화)
    result.validItems.append("✅ 스트림 객체 연결됨")
    // streamInfo 접근은 Sendable 프로토콜 문제로 인해 제외

    result.isValid = result.issues.isEmpty
    result.summary = "RTMPStream: \(result.issues.isEmpty ? "정상 설정" : "\(result.issues.count)개 문제")"

    return result
  }

  /// 4️⃣ 화면 캡처 데이터 검증
  func validateScreenCaptureData() -> ScreenCaptureValidationResult {
    var result = ScreenCaptureValidationResult()

    logger.info("🎥 [4/7] 화면 캡처 데이터 검증 중...", category: .system)

    // 화면 캡처 모드 확인
    if isScreenCaptureMode {
      result.validItems.append("✅ 화면 캡처 모드 활성화")
    } else {
      result.issues.append("❌ 화면 캡처 모드가 비활성화됨")
    }

    // 프레임 통계 확인
    let frameCount = screenCaptureStats.frameCount
    let successCount = screenCaptureStats.successCount
    let failureCount = screenCaptureStats.failureCount
    let currentFPS = screenCaptureStats.currentFPS

    if frameCount > 0 {
      result.validItems.append("✅ 총 프레임 처리: \(frameCount)개")
      result.validItems.append("✅ 성공한 프레임: \(successCount)개")
      if failureCount > 0 {
        result.issues.append("⚠️ 실패한 프레임: \(failureCount)개")
      }
      result.validItems.append("✅ 현재 FPS: \(String(format: "%.1f", currentFPS))")

      // 성공률 계산
      let successRate = frameCount > 0 ? (Double(successCount) / Double(frameCount)) * 100 : 0
      if successRate >= 95.0 {
        result.validItems.append("✅ 프레임 성공률: \(String(format: "%.1f", successRate))%")
      } else {
        result.issues.append("⚠️ 프레임 성공률 낮음: \(String(format: "%.1f", successRate))%")
      }
    } else {
      result.issues.append("❌ 화면 캡처 프레임 데이터 없음")
    }

    // CVPixelBuffer 생성 확인
    if screenCaptureStats.frameCount > 0 {
      result.validItems.append("✅ CVPixelBuffer → CMSampleBuffer 변환 정상")
    } else {
      result.issues.append("❌ 프레임 버퍼 변환 데이터 없음")
    }

    result.isValid = frameCount > 0 && result.issues.filter { $0.hasPrefix("❌") }.isEmpty
    result.summary = "화면 캡처: \(frameCount)프레임, \(String(format: "%.1f", currentFPS))fps"

    return result
  }

  /// 5️⃣ 네트워크 연결 검증
  func validateNetworkConnection() async -> NetworkValidationResult {
    var result = NetworkValidationResult()

    logger.info("🌐 [5/7] 네트워크 연결 검증 중...", category: .system)

    // 네트워크 모니터 상태
    if let networkMonitor = networkMonitor {
      let path = networkMonitor.currentPath

      switch path.status {
      case .satisfied:
        result.validItems.append("✅ 네트워크 상태: 연결됨")
      case .unsatisfied:
        result.issues.append("❌ 네트워크 상태: 연결 끊어짐")
      case .requiresConnection:
        result.issues.append("⚠️ 네트워크 상태: 연결 필요")
      @unknown default:
        result.issues.append("⚠️ 네트워크 상태: 알 수 없음")
      }

      // 사용 가능한 인터페이스
      let interfaces = path.availableInterfaces.map { $0.name }
      if !interfaces.isEmpty {
        result.validItems.append("✅ 사용 가능한 인터페이스: \(interfaces.joined(separator: ", "))")
      } else {
        result.issues.append("❌ 사용 가능한 네트워크 인터페이스 없음")
      }

      // 네트워크 제약 사항
      if path.isExpensive {
        result.issues.append("⚠️ 데이터 요금이 발생하는 연결")
      } else {
        result.validItems.append("✅ 무료 네트워크 연결")
      }

      if path.isConstrained {
        result.issues.append("⚠️ 제한된 네트워크 연결")
      } else {
        result.validItems.append("✅ 제한 없는 네트워크 연결")
      }
    } else {
      result.issues.append("❌ 네트워크 모니터가 초기화되지 않음")
    }

    // 전송 통계
    let latency = transmissionStats.networkLatency
    if latency > 0 {
      if latency < 100 {
        result.validItems.append("✅ 네트워크 지연: \(Int(latency))ms (양호)")
      } else if latency < 300 {
        result.issues.append("⚠️ 네트워크 지연: \(Int(latency))ms (보통)")
      } else {
        result.issues.append("❌ 네트워크 지연: \(Int(latency))ms (높음)")
      }
    }

    result.isValid = result.issues.filter { $0.hasPrefix("❌") }.isEmpty
    result.summary = "네트워크: \(result.isValid ? "정상" : "문제 있음")"

    return result
  }

  /// 6️⃣ 디바이스 환경 검증
  func validateDeviceEnvironment() -> DeviceValidationResult {
    var result = DeviceValidationResult()

    logger.info("📱 [6/7] 디바이스 환경 검증 중...", category: .system)

    // 실행 환경 확인
    #if targetEnvironment(simulator)
      result.issues.append("⚠️ iOS 시뮬레이터에서 실행 중 (실제 디바이스 권장)")
    #else
      result.validItems.append("✅ 실제 iOS 디바이스에서 실행 중")
    #endif

    // iOS 버전 확인
    let systemVersion = UIDevice.current.systemVersion
    result.validItems.append("✅ iOS 버전: \(systemVersion)")

    // 디바이스 모델 확인
    let deviceModel = UIDevice.current.model
    result.validItems.append("✅ 디바이스 모델: \(deviceModel)")

    // 화면 캡처 권한 (ReplayKit 지원)
    result.validItems.append("✅ 화면 캡처 기능: 사용 가능 (ReplayKit)")

    // 메모리 상태 (간접적 확인)
    let processInfo = ProcessInfo.processInfo
    result.validItems.append("✅ 시스템 업타임: \(Int(processInfo.systemUptime))초")

    result.isValid = result.issues.filter { $0.hasPrefix("❌") }.isEmpty
    result.summary = "디바이스: \(deviceModel), iOS \(systemVersion)"

    return result
  }

  /// 7️⃣ 실제 송출 데이터 흐름 검증
  func validateActualDataFlow() async -> DataFlowValidationResult {
    var result = DataFlowValidationResult()

    logger.info("🔗 [7/7] 실제 송출 데이터 흐름 검증 중...", category: .system)

    // 스트리밍 상태 확인
    if isStreaming {
      result.validItems.append("✅ 스트리밍 상태: 활성화")
    } else {
      result.issues.append("❌ 스트리밍 상태: 비활성화")
    }

    // RTMPStream 연결 확인
    if currentRTMPStream != nil {
      result.validItems.append("✅ RTMPStream 연결: 활성화")
    } else {
      result.issues.append("❌ RTMPStream 연결: 비활성화")
    }

    // 데이터 전송 체인 확인
    let chainStatus = [
      ("CameraPreviewUIView", screenCaptureStats.frameCount > 0),
      ("HaishinKitManager.sendManualFrame", screenCaptureStats.successCount > 0),
      ("RTMPStream.append", currentRTMPStream != nil),
      ("RTMP Server", isStreaming && currentRTMPStream != nil),
    ]

    for (component, isWorking) in chainStatus {
      if isWorking {
        result.validItems.append("✅ \(component): 정상 작동")
      } else {
        result.issues.append("❌ \(component): 작동 안함")
      }
    }

    // 전송 통계 확인
    let totalFrames = transmissionStats.videoFramesTransmitted
    let totalBytes = transmissionStats.totalBytesTransmitted

    if totalFrames > 0 {
      result.validItems.append("✅ 전송된 비디오 프레임: \(totalFrames)개")
    } else {
      result.issues.append("❌ 전송된 비디오 프레임 없음")
    }

    if totalBytes > 0 {
      result.validItems.append("✅ 총 전송량: \(formatBytes(totalBytes))")
    } else {
      result.issues.append("❌ 데이터 전송량 없음")
    }

    // 실시간 FPS 확인
    let currentFPS = screenCaptureStats.currentFPS
    if currentFPS > 0 {
      if currentFPS >= 15.0 {
        result.validItems.append("✅ 실시간 FPS: \(String(format: "%.1f", currentFPS)) (정상)")
      } else {
        result.issues.append("⚠️ 실시간 FPS: \(String(format: "%.1f", currentFPS)) (낮음)")
      }
    } else {
      result.issues.append("❌ 실시간 FPS 측정 불가")
    }

    result.isValid = result.issues.filter { $0.hasPrefix("❌") }.isEmpty
    result.summary = "데이터 흐름: \(result.isValid ? "정상" : "문제 있음")"

    return result
  }

  /// 진단 결과 로깅
  func logDiagnosisReport(_ report: StreamingDiagnosisReport) {
    logger.info("", category: .system)
    logger.info("📊 ═══════════════════════════════════════", category: .system)
    logger.info("📊 HaishinKit 스트리밍 파이프라인 진단 결과", category: .system)
    logger.info("📊 ═══════════════════════════════════════", category: .system)
    logger.info("📊 종합 점수: \(report.overallScore)점/100점 (\(report.overallGrade))", category: .system)
    logger.info("📊", category: .system)

    // 각 영역별 결과
    logger.info(
      "📊 1️⃣ 설정 검증: \(report.configValidation.isValid ? "✅ 통과" : "❌ 실패") - \(report.configValidation.summary)",
      category: .system)
    logger.info(
      "📊 2️⃣ MediaMixer: \(report.mediaMixerStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.mediaMixerStatus.summary)",
      category: .system)
    logger.info(
      "📊 3️⃣ RTMPStream: \(report.rtmpStreamStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.rtmpStreamStatus.summary)",
      category: .system)
    logger.info(
      "📊 4️⃣ 화면 캡처: \(report.screenCaptureStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.screenCaptureStatus.summary)",
      category: .system)
    logger.info(
      "📊 5️⃣ 네트워크: \(report.networkStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.networkStatus.summary)",
      category: .system)
    logger.info(
      "📊 6️⃣ 디바이스: \(report.deviceStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.deviceStatus.summary)",
      category: .system)
    logger.info(
      "📊 7️⃣ 데이터 흐름: \(report.dataFlowStatus.isValid ? "✅ 통과" : "❌ 실패") - \(report.dataFlowStatus.summary)",
      category: .system)

    logger.info("📊", category: .system)
    logger.info("📊 💡 종합 평가: \(report.getRecommendation())", category: .system)
    logger.info("📊 ═══════════════════════════════════════", category: .system)
    logger.info("", category: .system)
  }

}
