//
//  CameraControlViews.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import AVFoundation
import HaishinKit
import SwiftUI
import UIKit
import Foundation

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

/// 스트리밍 상태 표시 뷰
final class StreamingStatusView: UIView {

  private lazy var containerView: UIView = {
    let view = UIView()
    view.backgroundColor = UIColor.red.withAlphaComponent(0.8)
    view.layer.cornerRadius = 8
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  private lazy var liveLabel: UILabel = {
    let label = UILabel()
    label.text = "🔴 LIVE"
    label.textColor = .white
    label.font = .boldSystemFont(ofSize: 14)
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var statsLabel: UILabel = {
    let label = UILabel()
    label.textColor = .white
    label.font = .systemFont(ofSize: 12)
    label.numberOfLines = 2
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupView()
  }

  private func setupView() {
    addSubview(containerView)
    containerView.addSubview(liveLabel)
    containerView.addSubview(statsLabel)

    NSLayoutConstraint.activate([
      containerView.topAnchor.constraint(equalTo: topAnchor),
      containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

      liveLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
      liveLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
      liveLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),

      statsLabel.topAnchor.constraint(equalTo: liveLabel.bottomAnchor, constant: 4),
      statsLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
      statsLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
      statsLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
    ])
  }

  func updateStatus(_ status: String) {
    liveLabel.text = status
  }

  /// 재연결 상태 업데이트
  func updateReconnectingStatus(_ attempt: Int, _ maxAttempts: Int, _ delay: Int) {
    liveLabel.text = NSLocalizedString("reconnecting_attempt", comment: "🔄 재연결 중")
    statsLabel.text = String(format: NSLocalizedString("attempt_retry_format", comment: "시도: %d/%d\n%d초 후 재시도"), attempt, maxAttempts, delay)

    // 재연결 중일 때 배경색을 주황색으로 변경
    containerView.backgroundColor = UIColor.orange.withAlphaComponent(0.8)
  }

  /// 연결 실패 상태 업데이트
  func updateFailedStatus(_ message: String) {
    liveLabel.text = NSLocalizedString("connection_failed", comment: "❌ 연결 실패")
    statsLabel.text = message

    // 실패 시 배경색을 빨간색으로 변경
    containerView.backgroundColor = UIColor.red.withAlphaComponent(0.8)
  }

  /// 정상 스트리밍 상태로 복원
  func updateStreamingStatus() {
    liveLabel.text = "🔴 LIVE"

    // 정상 상태로 배경색 복원
    containerView.backgroundColor = UIColor.red.withAlphaComponent(0.8)
  }

  func updateStats(_ stats: StreamStats) {
    let duration = formatDuration(Int(stats.duration))
    statsLabel.text = "\(duration)\n\(Int(stats.videoBitrate))kbps"
  }

  private func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
      return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    } else {
      return String(format: "%02d:%02d", minutes, secs)
    }
  }
} 