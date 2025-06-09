//
//  CameraIndicatorViews.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import HaishinKit
import SwiftUI
import UIKit
import Foundation

/// 포커스 인디케이터 뷰
final class FocusIndicatorView: UIView {

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    backgroundColor = .clear
    layer.borderColor = UIColor.yellow.cgColor
    layer.borderWidth = 2
    alpha = 0
  }

  func animate(completion: @escaping () -> Void) {
    UIView.animate(
      withDuration: 0.2,
      animations: {
        self.alpha = 1.0
        self.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
      }
    ) { _ in
      UIView.animate(
        withDuration: 0.3,
        animations: {
          self.alpha = 0.8
          self.transform = CGAffineTransform.identity
        }
      ) { _ in
        UIView.animate(
          withDuration: 1.0,
          animations: {
            self.alpha = 0
          },
          completion: { _ in
            completion()
          })
      }
    }
  }
}

/// 노출 인디케이터 뷰
final class ExposureIndicatorView: UIView {

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    backgroundColor = .clear
    layer.borderColor = UIColor.orange.cgColor
    layer.borderWidth = 2
    layer.cornerRadius = 30
    alpha = 0

    let sunIcon = UILabel()
    sunIcon.text = "☀️"
    sunIcon.font = .systemFont(ofSize: 24)
    sunIcon.textAlignment = .center
    sunIcon.translatesAutoresizingMaskIntoConstraints = false
    addSubview(sunIcon)

    NSLayoutConstraint.activate([
      sunIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
      sunIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  func animate(completion: @escaping () -> Void) {
    UIView.animate(
      withDuration: 0.2,
      animations: {
        self.alpha = 1.0
        self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
      }
    ) { _ in
      UIView.animate(
        withDuration: 0.3,
        animations: {
          self.alpha = 0.8
          self.transform = CGAffineTransform.identity
        }
      ) { _ in
        UIView.animate(
          withDuration: 1.0,
          animations: {
            self.alpha = 0
          },
          completion: { _ in
            completion()
          })
      }
    }
  }
} 