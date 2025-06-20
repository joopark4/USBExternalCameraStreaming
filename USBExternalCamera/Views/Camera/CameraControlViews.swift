//
//  CameraControlViews.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Supporting Views

/// 카메라 컨트롤 오버레이
protocol CameraControlOverlayDelegate: AnyObject {
  func didTapRecord()
}

final class CameraControlOverlay: UIView {
  weak var delegate: CameraControlOverlayDelegate?

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    // 버튼들을 제거했으므로 빈 뷰로 설정
  }
}
