//
//  CameraPreviewView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import Foundation
import HaishinKit
import SwiftUI
import UIKit

/// **실제 HaishinKit RTMP 스트리밍을 위한 카메라 미리보기**
struct CameraPreviewView: UIViewRepresentable {
  let session: AVCaptureSession
  var streamViewModel: LiveStreamViewModel?
  var haishinKitManager: HaishinKitManager?

  // 텍스트 오버레이 관련 프로퍼티
  var showTextOverlay: Bool = false
  var overlayText: String = ""

  init(
    session: AVCaptureSession,
    streamViewModel: LiveStreamViewModel? = nil,
    haishinKitManager: HaishinKitManager? = nil,
    showTextOverlay: Bool = false,
    overlayText: String = ""
  ) {
    self.session = session
    self.streamViewModel = streamViewModel
    self.haishinKitManager = haishinKitManager
    self.showTextOverlay = showTextOverlay
    self.overlayText = overlayText
  }

  func makeUIView(context: Context) -> UIView {
    let view = CameraPreviewUIView()
    view.captureSession = session
    view.haishinKitManager = haishinKitManager
    view.showTextOverlay = showTextOverlay
    view.overlayText = overlayText

    // 여백을 4픽셀로 설정하고 화면에 꽉차게 설정
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: view.superview?.topAnchor ?? view.topAnchor, constant: 4),
      view.bottomAnchor.constraint(
        equalTo: view.superview?.bottomAnchor ?? view.bottomAnchor, constant: -4),
      view.leadingAnchor.constraint(
        equalTo: view.superview?.leadingAnchor ?? view.leadingAnchor, constant: 4),
      view.trailingAnchor.constraint(
        equalTo: view.superview?.trailingAnchor ?? view.trailingAnchor, constant: -4),
    ])

    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    if let previewView = uiView as? CameraPreviewUIView {
      // 세션이나 매니저가 변경된 경우에만 업데이트
      let sessionChanged = previewView.captureSession !== session
      let managerChanged = previewView.haishinKitManager !== haishinKitManager
      let textOverlayChanged =
        previewView.showTextOverlay != showTextOverlay || previewView.overlayText != overlayText

      if sessionChanged {
        logInfo("캡처 세션 변경 감지 - 업데이트", category: .camera)
        previewView.captureSession = session
      }

      if managerChanged {
        logInfo("HaishinKit 매니저 변경 감지 - 업데이트", category: .camera)
        previewView.haishinKitManager = haishinKitManager
      }

      if textOverlayChanged {
        logInfo("텍스트 오버레이 변경 감지 - 업데이트", category: .camera)
        previewView.showTextOverlay = showTextOverlay
        previewView.overlayText = overlayText

        // HaishinKitManager에 텍스트 오버레이 정보 전달
        if let haishinKitManager = haishinKitManager {
          haishinKitManager.updateTextOverlay(show: showTextOverlay, text: overlayText)
        }
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
    logInfo("화면 캡처 중지 요청됨 - HaishinKitManager 사용 권장", category: .streaming)
  }
}
