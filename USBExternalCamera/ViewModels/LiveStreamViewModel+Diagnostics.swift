import AVFoundation
import Combine
import Foundation
import SwiftData
import SwiftUI

extension LiveStreamViewModel {
  // MARK: - Public Methods - Diagnostics

  /// YouTube 스트리밍 문제 진단
  /// - Returns: 진단 결과 목록
  func diagnoseYouTubeStreaming() async -> [String] {
    logDebug("🔍 [YOUTUBE DIAGNOSIS] Starting diagnosis...", category: .streaming)

    let permissionIssues = checkPermissionIssues()
    let deviceIssues = checkDeviceIssues()
    let settingsIssues = checkSettingsIssues()
    let streamingIssues = await checkStreamingIssues()

    return compileDiagnosticResults(
      permissionIssues: permissionIssues,
      deviceIssues: deviceIssues,
      settingsIssues: settingsIssues,
      streamingIssues: streamingIssues
    )
  }

  /// 카메라 권한 요청
  /// - Returns: 권한 허용 여부
  func requestCameraPermission() async -> Bool {
    logDebug("📸 [PERMISSION] Requesting camera permission...", category: .streaming)
    let status = await AVCaptureDevice.requestAccess(for: .video)
    print(status ? "✅ [PERMISSION] Camera allowed" : "❌ [PERMISSION] Camera denied")
    return status
  }

  /// 마이크 권한 요청
  /// - Returns: 권한 허용 여부
  func requestMicrophonePermission() async -> Bool {
    logDebug("🎤 [PERMISSION] Requesting microphone permission...", category: .streaming)
    let status = await AVCaptureDevice.requestAccess(for: .audio)
    print(status ? "✅ [PERMISSION] Microphone allowed" : "❌ [PERMISSION] Microphone denied")
    return status
  }

  /// 카메라 디바이스 목록 확인
  /// - Returns: 카메라 목록
  func checkAvailableCameras() -> [String] {
    logDebug("📹 [CAMERAS] Checking available cameras...", category: .streaming)

    let cameras = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInWideAngleCamera, .builtInTelephotoCamera, .builtInUltraWideCamera, .external,
      ],
      mediaType: .video,
      position: .unspecified
    ).devices

    return cameras.isEmpty
      ? ["❌ 사용 가능한 카메라가 없습니다"] : cameras.map { "📹 \($0.localizedName) (\($0.deviceType.rawValue))" }
  }

  /// 전체 시스템 진단
  /// - Returns: 진단 보고서
  func performFullSystemDiagnosis() async -> String {
    logDebug("🔍 [FULL DIAGNOSIS] Starting full system diagnosis...", category: .streaming)

    var report = "📊 USBExternalCamera 시스템 진단 보고서\n"
    report += "================================\n\n"

    report += generateBasicInfoSection()
    report += generatePermissionSection()
    report += generateDeviceSection()
    report += await generateYouTubeSection()
    report += generateRecommendationsSection()

    report += "================================\n"
    report += "📅 진단 완료: \(Date())\n"

    logDebug("🔍 [FULL DIAGNOSIS] Diagnosis complete", category: .streaming)
    return report
  }

}
