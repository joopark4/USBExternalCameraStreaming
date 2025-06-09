//
//  LiveStreamTypes.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation
import SwiftUI

// MARK: - Live Stream Error

/// 라이브 스트리밍 에러
public enum LiveStreamError: Error, LocalizedError, Equatable {
    case initializationFailed(String)
    case deviceNotFound(String)
    case networkError(String)
    case authenticationFailed(String)
    case streamingFailed(String)
    case configurationError(String)
    case permissionDenied(String)
    case incompatibleSettings(String)
    case connectionTimeout
    case serverError(Int, String)
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return String(format: NSLocalizedString("initialization_failed_detailed", comment: "초기화 실패: %@"), message)
        case .deviceNotFound(let device):
            return String(format: NSLocalizedString("device_not_found_detailed", comment: "%@을(를) 찾을 수 없습니다"), device)
        case .networkError(let message):
            return String(format: NSLocalizedString("network_error_detailed", comment: "네트워크 오류: %@"), message)
        case .authenticationFailed(let message):
            return String(format: NSLocalizedString("authentication_failed_detailed", comment: "인증 실패: %@"), message)
        case .streamingFailed(let message):
            return String(format: NSLocalizedString("streaming_error_detailed", comment: "스트리밍 오류: %@"), message)
        case .configurationError(let message):
            return String(format: NSLocalizedString("initialization_failed_detailed", comment: "초기화 실패: %@"), message)
        case .permissionDenied(let permission):
            return String(format: NSLocalizedString("device_not_found_detailed", comment: "%@을(를) 찾을 수 없습니다"), permission)
        case .incompatibleSettings(let message):
            return String(format: NSLocalizedString("initialization_failed_detailed", comment: "초기화 실패: %@"), message)
        case .connectionTimeout:
            return NSLocalizedString("timeout_message", comment: "연결 시간이 초과되었습니다")
        case .serverError(let code, let message):
            return String(format: NSLocalizedString("server_error_message", comment: "서버 오류가 발생했습니다. (코드: %d)"), code) + ": \(message)"
        case .unknown(let message):
            return String(format: NSLocalizedString("unknown_error_message", comment: "알 수 없는 오류가 발생했습니다"), message)
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .networkError:
            return NSLocalizedString("check_internet_connection", comment: "인터넷 연결을 확인해주세요")
        case .permissionDenied:
            return NSLocalizedString("allow_permission_in_settings", comment: "설정에서 권한을 허용해주세요")
        case .connectionTimeout:
            return NSLocalizedString("check_network_and_retry", comment: "네트워크 상태를 확인하고 다시 시도해주세요")
        case .serverError:
            return NSLocalizedString("try_again_later", comment: "잠시 후 다시 시도해주세요")
        default:
            return nil
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .deviceNotFound:
            return NSLocalizedString("check_camera_microphone_connection", comment: "카메라나 마이크가 연결되어 있는지 확인해주세요")
        case .networkError, .connectionTimeout:
            return NSLocalizedString("check_wifi_cellular_connection", comment: "WiFi 또는 셀룰러 데이터 연결을 확인해주세요")
        case .permissionDenied:
            return NSLocalizedString("allow_permission_privacy_settings", comment: "설정 > 개인정보 보호에서 권한을 허용해주세요")
        case .authenticationFailed:
            return NSLocalizedString("recheck_rtmp_stream_key", comment: "RTMP URL과 스트림 키를 다시 확인해주세요")
        case .incompatibleSettings:
            return NSLocalizedString("adjust_streaming_settings", comment: "스트리밍 설정을 조정해보세요")
        default:
            return NSLocalizedString("restart_app_if_problem_persists", comment: "문제가 지속되면 앱을 재시작해보세요")
        }
    }
}

// MARK: - Live Stream Status

/// 라이브 스트리밍 상태
public enum LiveStreamStatus: Equatable {
    /// 대기 중
    case idle
    
    /// 연결 중
    case connecting
    
    /// 연결됨
    case connected
    
    /// 스트리밍 중
    case streaming
    
    /// 연결 종료 중
    case disconnecting
    
    /// 오류 발생
    case error(LiveStreamError)
    
    /// 상태에 맞는 아이콘 이름
    public var iconName: String {
        switch self {
        case .idle:
            return "play.circle"
        case .connecting:
            return "circle.dotted"
        case .connected:
            return "checkmark.circle"
        case .streaming:
            return "dot.radiowaves.up.forward"
        case .disconnecting:
            return "stop.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
    
    /// 상태 표시 색상
    public var color: String {
        switch self {
        case .idle:
            return "gray"
        case .connecting:
            return "orange"
        case .connected:
            return "green"
        case .streaming:
            return "blue"
        case .disconnecting:
            return "orange"
        case .error:
            return "red"
        }
    }
    
    /// 상태 설명
    public var description: String {
        switch self {
        case .idle:
            return NSLocalizedString("status_idle", comment: "대기 중")
        case .connecting:
            return NSLocalizedString("status_connecting", comment: "연결 중")
        case .connected:
            return NSLocalizedString("status_connected", comment: "연결됨")
        case .streaming:
            return NSLocalizedString("status_streaming", comment: "스트리밍 중")
        case .disconnecting:
            return NSLocalizedString("status_disconnecting", comment: "연결 해제 중")
        case .error:
            return NSLocalizedString("status_error", comment: "오류")
        }
    }
    
    /// 오류 상태인지 확인
    public var isError: Bool {
        switch self {
        case .error:
            return true
        default:
            return false
        }
    }
    
    /// 표시용 텍스트
    public var displayText: String {
        return description
    }
    
    /// 활성 상태인지 확인 (연결 중이거나 스트리밍 중)
    public var isActive: Bool {
        switch self {
        case .connecting, .streaming:
            return true
        default:
            return false
        }
    }
}

// MARK: - Network Quality

/// 네트워크 품질
public enum NetworkQuality: CaseIterable, Equatable {
    case excellent
    case good
    case fair
    case poor
    case unknown
    
    public var displayName: String {
        switch self {
        case .excellent: return NSLocalizedString("excellent", comment: "우수")
        case .good: return NSLocalizedString("good", comment: "양호")
        case .fair: return NSLocalizedString("fair", comment: "보통")
        case .poor: return NSLocalizedString("poor", comment: "불량")
        case .unknown: return NSLocalizedString("unknown", comment: "알 수 없음")
        }
    }
    
    public var qualityScore: Double {
        switch self {
        case .excellent: return 1.0
        case .good: return 0.8
        case .fair: return 0.6
        case .poor: return 0.4
        case .unknown: return 0.0
        }
    }
    
    public var recommendedBitrate: Int {
        switch self {
        case .excellent: return 4000
        case .good: return 2500
        case .fair: return 1500
        case .poor: return 800
        case .unknown: return 1000
        }
    }
    
    public var color: String {
        switch self {
        case .excellent, .good: return "green"
        case .fair: return "orange"
        case .poor: return "red"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Type Aliases

/// Type aliases for external dependencies (접근 제어 수정)
internal typealias LiveStreamStats = StreamStats
internal typealias LiveConnectionInfo = ConnectionInfo 