//
//  CameraPreviewView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import HaishinKit
import SwiftUI
import UIKit
import Foundation

/// **실제 HaishinKit RTMP 스트리밍을 위한 카메라 미리보기**
struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession
  var streamViewModel: LiveStreamViewModel?
  var haishinKitManager: HaishinKitManager?

  init(
    session: AVCaptureSession, streamViewModel: LiveStreamViewModel? = nil,
    haishinKitManager: HaishinKitManager? = nil
  ) {
    self.session = session
    self.streamViewModel = streamViewModel
    self.haishinKitManager = haishinKitManager
  }

  func makeUIView(context: Context) -> UIView {
    // 항상 AVCaptureVideoPreviewLayer 사용하여 카메라 미리보기 유지
    // HaishinKit은 백그라운드에서 스트리밍만 처리
    let view = CameraPreviewUIView()
    view.captureSession = session
    view.haishinKitManager = haishinKitManager
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    if let previewView = uiView as? CameraPreviewUIView {
      // 세션이나 매니저가 변경된 경우에만 업데이트
      let sessionChanged = previewView.captureSession !== session
      let managerChanged = previewView.haishinKitManager !== haishinKitManager

      if sessionChanged {
        logInfo("캡처 세션 변경 감지 - 업데이트", category: .camera)
        previewView.captureSession = session
      }

      if managerChanged {
        logInfo("HaishinKit 매니저 변경 감지 - 업데이트", category: .camera)
        previewView.haishinKitManager = haishinKitManager
      }

      // 프리뷰 새로고침은 하지 않음 (안정성 향상)
      logInfo("업데이트 완료 - 프리뷰 새로고침 건너뜀", category: .camera)
    }
  }

  // MARK: - Screen Capture Control Methods

  /// 화면 캡처 송출 시작 (외부에서 호출 가능)
  func startScreenCapture() {
    // UIViewRepresentable에서 UIView에 접근하는 방법이 제한적이므로
    // HaishinKitManager를 통해 제어하는 것을 권장
    logInfo("화면 캡처 요청됨 - HaishinKitManager 사용 권장", category: .streaming)
  }

  /// 화면 캡처 송출 중지 (외부에서 호출 가능)
  func stopScreenCapture() {
    logInfo("화면 캡처 중지 요청됨", category: .streaming)

    // 화면 캡처 중지 알림 전송
    DispatchQueue.main.async {
      NotificationCenter.default.post(name: .stopScreenCapture, object: nil)
    }
  }
} 