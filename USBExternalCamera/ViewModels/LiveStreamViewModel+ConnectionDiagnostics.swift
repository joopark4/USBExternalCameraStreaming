import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Public Methods - Connection Diagnostics

  /// **실시간 송출 상태 진단**
  func diagnoseLiveStreamConnection() async -> String {
    logDebug("🔍 [DIAGNOSIS] 실시간 송출 상태 진단 시작", category: .streaming)

    var report = "📊 **실시간 송출 상태 진단 보고서**\n"
    report += String(repeating: "=", count: 50) + "\n\n"

    // 1. 기본 설정 확인
    report += "📋 **1. 기본 설정 상태**\n"
    report += "   • 현재 상태: \(status.description)\n"
    report += "   • RTMP URL: \(settings.rtmpURL.isEmpty ? "❌ 미설정" : "✅ 설정됨")\n"
    report +=
      "   • 스트림 키: \(settings.streamKey.isEmpty ? "❌ 미설정" : "✅ 설정됨 (\(settings.streamKey.count)자)")\n"
    report += "   • 비트레이트: \(settings.videoBitrate) kbps\n"
    report += "   • 해상도: \(settings.videoWidth)x\(settings.videoHeight)\n\n"

    // 2. 권한 상태 확인
    report += "🔐 **2. 권한 상태**\n"
    let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)

    report += "   • 카메라 권한: \(cameraAuth == .authorized ? "✅ 허용됨" : "❌ 거부됨 또는 미결정")\n"
    report += "   • 마이크 권한: \(micAuth == .authorized ? "✅ 허용됨" : "❌ 거부됨 또는 미결정")\n\n"

    // 3. 카메라 장치 확인
    report += "📹 **3. 카메라 장치 상태**\n"
    let cameras = checkAvailableCameras()
    if cameras.isEmpty || cameras.first?.contains("❌") == true {
      report += "   ❌ **문제**: 사용 가능한 카메라 없음\n"
      report += "   💡 **해결책**: USB 카메라 연결 확인 또는 앱 재시작\n"
    } else {
      for camera in cameras {
        report += "   \(camera)\n"
      }
    }
    report += "\n"

    // 4. 네트워크 및 RTMP 설정 확인
    report += "🌐 **4. 네트워크 및 RTMP 설정**\n"
    let rtmpValidation = await validateRTMPSettings()
    report += rtmpValidation
    report += "\n"

    // 5. 스트리밍 서비스 상태
    report += "⚙️ **5. 스트리밍 서비스 상태**\n"
    if let service = liveStreamService {
      report += "   • 서비스 초기화: ✅ 완료\n"
      report += "   • 서비스 스트리밍 상태: \(service.isStreaming ? "🔴 스트리밍 중" : "⚪ 대기 중")\n"
      report += "   • 서비스 상태: \(service.currentStatus.description)\n"
    } else {
      report += "   • 서비스 초기화: ❌ **실패** - 이것이 주요 문제입니다!\n"
      report += "   💡 **해결책**: 앱을 완전히 종료하고 다시 시작하세요\n"
    }
    report += "\n"

    // 6. 진단 결과 및 권장사항
    report += "💡 **6. 진단 결과 및 권장사항**\n"
    let recommendations = await generateRecommendations()
    report += recommendations

    report += "\n" + String(repeating: "=", count: 50) + "\n"
    report += "📅 진단 완료: \(Date().formatted())\n"

    logDebug("🔍 [DIAGNOSIS] 진단 완료", category: .streaming)
    return report
  }

  /// RTMP 설정 유효성 검사
  private func validateRTMPSettings() async -> String {
    var result = ""

    // URL 검증
    if settings.rtmpURL.isEmpty {
      result += "   ❌ **RTMP URL이 설정되지 않음**\n"
      result += "   💡 YouTube의 경우: rtmp://a.rtmp.youtube.com/live2/\n"
    } else if !settings.rtmpURL.lowercased().hasPrefix("rtmp") {
      result += "   ❌ **잘못된 RTMP URL 형식**\n"
      result += "   💡 'rtmp://' 또는 'rtmps://'로 시작해야 합니다\n"
    } else {
      result += "   ✅ RTMP URL 형식이 올바름\n"
    }

    // 스트림 키 검증
    if settings.streamKey.isEmpty {
      result += "   ❌ **스트림 키가 설정되지 않음**\n"
      result += "   💡 YouTube Studio에서 스트림 키를 복사하세요\n"
    } else if settings.streamKey == "YOUR_YOUTUBE_STREAM_KEY_HERE" {
      result += "   ❌ **더미 스트림 키 사용 중**\n"
      result += "   💡 실제 YouTube 스트림 키로 변경하세요\n"
    } else if settings.streamKey.count < Constants.minimumStreamKeyLength {
      result += "   ⚠️ **스트림 키가 너무 짧음** (\(settings.streamKey.count)자)\n"
      result += "   💡 YouTube 스트림 키는 일반적으로 20자 이상입니다\n"
    } else {
      result += "   ✅ 스트림 키가 설정됨 (\(settings.streamKey.count)자)\n"
    }

    // 간단한 연결 테스트
    if let testResult = await liveStreamService?.testConnection(to: settings) {
      if testResult.isSuccessful {
        result += "   ✅ 연결 테스트 성공 (지연시간: \(testResult.latency)ms)\n"
      } else {
        result += "   ❌ **연결 테스트 실패**: \(testResult.message)\n"
      }
    } else {
      result += "   ⚠️ 연결 테스트를 수행할 수 없음\n"
    }

    return result
  }

  /// 권장사항 생성
  private func generateRecommendations() async -> String {
    var recommendations = ""
    var issueCount = 0

    // 권한 문제 확인
    let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)

    if cameraAuth != .authorized {
      issueCount += 1
      recommendations += "   \(issueCount). 📸 **카메라 권한 허용** (설정 > 개인정보 보호 > 카메라)\n"
    }

    if micAuth != .authorized {
      issueCount += 1
      recommendations += "   \(issueCount). 🎤 **마이크 권한 허용** (설정 > 개인정보 보호 > 마이크)\n"
    }

    // 설정 문제 확인
    if settings.streamKey.isEmpty || settings.streamKey == "YOUR_YOUTUBE_STREAM_KEY_HERE" {
      issueCount += 1
      recommendations += "   \(issueCount). 🔑 **YouTube Studio에서 실제 스트림 키 설정**\n"
    }

    if settings.rtmpURL.isEmpty {
      issueCount += 1
      recommendations +=
        "   \(issueCount). 🌐 **RTMP URL 설정** (YouTube: rtmp://a.rtmp.youtube.com/live2/)\n"
    }

    // 카메라 문제 확인
    let cameras = checkAvailableCameras()
    if cameras.isEmpty || cameras.first?.contains("❌") == true {
      issueCount += 1
      recommendations += "   \(issueCount). 📹 **카메라 연결 확인** (USB 카메라 재연결 또는 앱 재시작)\n"
    }

    // YouTube 관련 권장사항
    issueCount += 1
    recommendations += "   \(issueCount). 🎬 **YouTube Studio 확인사항**:\n"
    recommendations += "      • 라이브 스트리밍 기능이 활성화되어 있는지 확인\n"
    recommendations += "      • 휴대폰 번호 인증이 완료되어 있는지 확인\n"
    recommendations += "      • '라이브 스트리밍 시작' 버튼을 눌러 대기 상태로 설정\n"
    recommendations += "      • 스트림이 나타나기까지 10-30초 대기\n"

    if issueCount == 1 {
      recommendations = "   ✅ **대부분의 설정이 정상입니다!**\n" + recommendations
      recommendations += "\n   💡 **추가 팁**: 문제가 지속되면 앱을 완전히 종료하고 재시작해보세요.\n"
    }

    return recommendations
  }

}
