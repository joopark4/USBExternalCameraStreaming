import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Private Methods - Diagnostics

  private func checkPermissionIssues() -> (issues: [String], solutions: [String]) {
    var issues: [String] = []
    var solutions: [String] = []

    let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    if cameraStatus != .authorized {
      issues.append("❌ 카메라 권한이 거부되었습니다")
      solutions.append("💡 설정 > 개인정보 보호 > 카메라에서 앱 권한을 허용하세요")
    }

    if micStatus != .authorized {
      issues.append("❌ 마이크 권한이 거부되었습니다")
      solutions.append("💡 설정 > 개인정보 보호 > 마이크에서 앱 권한을 허용하세요")
    }

    return (issues, solutions)
  }

  private func checkDeviceIssues() -> (issues: [String], solutions: [String]) {
    var issues: [String] = []
    var solutions: [String] = []

    let cameras = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .external],
      mediaType: .video,
      position: .unspecified
    ).devices

    if cameras.isEmpty {
      issues.append("❌ 사용 가능한 카메라가 없습니다")
      solutions.append("💡 USB 카메라 연결을 확인하거나 내장 카메라를 사용하세요")
    }

    return (issues, solutions)
  }

  private func checkSettingsIssues() -> (issues: [String], solutions: [String]) {
    var issues: [String] = []
    var solutions: [String] = []

    if settings.streamKey == "YOUR_YOUTUBE_STREAM_KEY_HERE" || settings.streamKey.isEmpty {
      issues.append("❌ YouTube 스트림 키가 설정되지 않았습니다")
      solutions.append("💡 YouTube Studio에서 실제 스트림 키를 복사하여 설정하세요")
    } else if settings.streamKey.count < Constants.minimumStreamKeyLength {
      issues.append("⚠️ 스트림 키가 너무 짧습니다 (\(settings.streamKey.count)자)")
      solutions.append("💡 YouTube 스트림 키는 일반적으로 20자 이상입니다")
    }

    return (issues, solutions)
  }

  private func checkStreamingIssues() async -> (issues: [String], solutions: [String]) {
    var issues: [String] = []
    var solutions: [String] = []

    if status == .streaming {
      // getCurrentTransmissionStatus 메서드가 아직 구현되지 않음
      issues.append("ℹ️ 스트리밍 상태 확인 기능은 구현 중입니다")
      solutions.append("💡 YouTube Studio에서 직접 스트림 상태를 확인하세요")
    } else {
      issues.append("❌ 현재 스트리밍 상태가 아닙니다 (상태: \(status))")
      solutions.append("💡 먼저 스트리밍을 시작하세요")
    }

    return (issues, solutions)
  }

  private func compileDiagnosticResults(
    permissionIssues: (issues: [String], solutions: [String]),
    deviceIssues: (issues: [String], solutions: [String]),
    settingsIssues: (issues: [String], solutions: [String]),
    streamingIssues: (issues: [String], solutions: [String])
  ) -> [String] {

    let allIssues =
      permissionIssues.issues + deviceIssues.issues + settingsIssues.issues + streamingIssues.issues
    let allSolutions =
      permissionIssues.solutions + deviceIssues.solutions + settingsIssues.solutions
      + streamingIssues.solutions

    var results: [String] = []

    if allIssues.isEmpty {
      results.append("✅ 모든 설정이 정상입니다")
      results.append("🔍 YouTube Studio에서 스트림 상태를 확인하세요")
      results.append("⏱️ 스트림이 나타나기까지 10-30초 정도 걸릴 수 있습니다")
    } else {
      results.append("🔍 발견된 문제:")
      results.append(contentsOf: allIssues)
      results.append("")
      results.append("💡 해결 방법:")
      results.append(contentsOf: allSolutions)
    }

    results.append("")
    results.append("📋 YouTube Studio 체크리스트:")
    results.append(contentsOf: getYouTubeChecklist())

    return results
  }

  private func getYouTubeChecklist() -> [String] {
    return [
      "YouTube Studio (studio.youtube.com)에서 '라이브 스트리밍' 메뉴를 확인하세요",
      "'스트림' 탭에서 '라이브 스트리밍 시작' 버튼을 눌렀는지 확인하세요",
      NSLocalizedString("youtube_check_stream_waiting", comment: "스트림이 '대기 중' 상태인지 확인하세요"),
      NSLocalizedString("youtube_check_live_enabled", comment: "채널에서 라이브 스트리밍 기능이 활성화되어 있는지 확인하세요"),
      NSLocalizedString("youtube_check_phone_verified", comment: "휴대폰 번호 인증이 완료되어 있는지 확인하세요"),
    ]
  }

}
