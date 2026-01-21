//
//  StatusColorMapping.swift
//  LiveStreamingCore
//
//  Created by Claude on 2025.
//

import SwiftUI

/// 스트리밍 상태와 색상을 매핑하는 프로토콜
public protocol StatusColorMappable {
    func colorForStatus(_ status: LiveStreamStatus) -> Color
    func systemImageForStatus(_ status: LiveStreamStatus) -> String
}

/// 기본 구현 제공
public extension StatusColorMappable {
    func colorForStatus(_ status: LiveStreamStatus) -> Color {
        switch status {
        case .idle:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .streaming:
            return .blue
        case .disconnecting:
            return .yellow
        case .error:
            return .red
        }
    }

    func systemImageForStatus(_ status: LiveStreamStatus) -> String {
        switch status {
        case .idle:
            return "circle"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "checkmark.circle"
        case .streaming:
            return "dot.radiowaves.left.and.right"
        case .disconnecting:
            return "xmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

/// 스트리밍 버튼 텍스트 관리
public struct StreamingButtonHelper {

    public static func screenCaptureButtonText(for status: LiveStreamStatus) -> String {
        switch status {
        case .idle, .error:
            return NSLocalizedString("streaming_start_capture", comment: "스트리밍 시작 - 캡처")
        case .connecting:
            return NSLocalizedString("screen_capture_connecting_button", comment: "화면 캡처 연결 중")
        case .connected:
            return NSLocalizedString("screen_capture_connected", comment: "화면 캡처 연결됨")
        case .disconnecting:
            return NSLocalizedString("screen_capture_disconnecting", comment: "화면 캡처 중지 중")
        case .streaming:
            return NSLocalizedString("streaming_stop", comment: "스트리밍 중지")
        }
    }

    public static func streamingButtonText(for status: LiveStreamStatus) -> String {
        switch status {
        case .idle, .error:
            return NSLocalizedString("streaming_start_normal", comment: "스트리밍 시작 - 일반")
        case .connecting:
            return NSLocalizedString("connecting_button", comment: "연결 중...")
        case .connected:
            return NSLocalizedString("connected_button", comment: "연결됨")
        case .disconnecting:
            return NSLocalizedString("disconnecting_button", comment: "연결 해제 중...")
        case .streaming:
            return NSLocalizedString("streaming_stop", comment: "스트리밍 중지")
        }
    }

    public static func buttonColor(for status: LiveStreamStatus) -> Color {
        switch status {
        case .idle:
            return .blue
        case .connecting, .disconnecting:
            return .orange
        case .connected:
            return .green
        case .streaming:
            return .red
        case .error:
            return .gray
        }
    }
}