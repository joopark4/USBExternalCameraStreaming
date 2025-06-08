//
//  DetailView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI

// MARK: - Notification Names

extension NSNotification.Name {
    static let startScreenCapture = NSNotification.Name("startScreenCapture")
    static let stopScreenCapture = NSNotification.Name("stopScreenCapture")
}

// MARK: - Detail View Components

/// 상세 화면 View 컴포넌트
/// 선택된 사이드바 항목에 따라 적절한 콘텐츠를 표시하는 컴포넌트입니다.
struct DetailView: View {
    @ObservedObject var viewModel: MainViewModel
    
    // 화면 캡처 테스트 관련 상태
    @State private var screenCaptureEnabled = false
    @State private var testMessage: String?
    @State private var screenCaptureStats: String?
    @State private var statsTimer: Timer?
    
    var body: some View {
        Group {
            switch viewModel.selectedSidebarItem {
            case .cameras:
                // 카메라 상세 화면
                CameraDetailContentView(viewModel: viewModel)
            case .none:
                // 아무것도 선택되지 않은 상태
                VStack {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text(NSLocalizedString("select_menu_from_sidebar", comment: "사이드바에서 메뉴를 선택하세요"))
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // 화면 캡처 관련 메서드들
    private func toggleScreenCapture() {
        guard let cameraView = getCameraPreviewView() else { return }
        
        if screenCaptureEnabled {
            cameraView.stopScreenCapture()
            stopStatsTimer()
            screenCaptureStats = nil
        } else {
            cameraView.startScreenCapture()
            startStatsTimer()
        }
        screenCaptureEnabled.toggle()
    }
    
    private func getCameraPreviewView() -> CameraPreviewUIView? {
        // UIViewRepresentable에서 실제 UIView에 접근하는 방법
        // 이 부분은 CameraPreviewView의 구조에 따라 수정이 필요할 수 있음
        return nil // TODO: 실제 구현 필요
    }
    
    private func startStatsTimer() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateScreenCaptureStats()
        }
    }
    
    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    private func updateScreenCaptureStats() {
        guard let cameraView = getCameraPreviewView() else { return }
        let status = cameraView.getScreenCaptureStatus()
        
        if let stats = status.stats {
            screenCaptureStats = stats
        }
    }
}

/// 카메라 상세 콘텐츠 View 컴포넌트
/// 현재 UI 상태에 따라 적절한 카메라 관련 화면을 표시합니다.
struct CameraDetailContentView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        switch viewModel.currentUIState {
        case .loading:
            // 로딩 상태
            LoadingView()
        case .permissionRequired:
            // 권한 필요 상태
            PermissionRequiredView(viewModel: viewModel)
        case .cameraNotSelected:
            // 카메라 미선택 상태
            CameraPlaceholderView()
        case .cameraActive:
            // 카메라 활성화 상태
            CameraPreviewContainerView(viewModel: viewModel)
        }
    }
}

/// 카메라 프리뷰 컨테이너 View 컴포넌트
/// 실제 카메라 화면을 표시하는 컴포넌트입니다.
/// 16:9 비율로 제한하여 실제 송출되는 영역만 표시합니다.
struct CameraPreviewContainerView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size
            
            // 16:9 비율 계산 (유튜브 라이브 표준)
            let aspectRatio: CGFloat = 16.0 / 9.0
            let maxWidth = containerSize.width - 60 // padding 고려
            let maxHeight = containerSize.height - 60 // padding 고려
            
            // Aspect Fit 방식으로 16:9 프레임 계산
            let previewSize: CGSize = {
                if maxWidth / maxHeight > aspectRatio {
                    // 세로가 기준: 높이에 맞춰서 너비 계산
                    let width = maxHeight * aspectRatio
                    return CGSize(width: width, height: maxHeight)
                } else {
                    // 가로가 기준: 너비에 맞춰서 높이 계산
                    let height = maxWidth / aspectRatio
                    return CGSize(width: maxWidth, height: height)
                }
            }()
            
            VStack {
                // 16:9 비율 카메라 프리뷰
                CameraPreviewView(
                    session: viewModel.cameraViewModel.captureSession,
                    streamViewModel: viewModel.liveStreamViewModel,
                    haishinKitManager: viewModel.liveStreamViewModel.streamingService as? HaishinKitManager
                )
                .frame(width: previewSize.width, height: previewSize.height)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                
                // 송출 영역 안내 텍스트
                Text("📺 실제 송출 영역 (16:9)")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 8)
                
                // 프리뷰 크기 정보
                Text("\(Int(previewSize.width)) × \(Int(previewSize.height))")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(30)
        .background(Color.black.opacity(0.1))
    }
}

/// 카메라 플레이스홀더 View 컴포넌트
/// 카메라가 선택되지 않았을 때 표시되는 안내 화면입니다.
struct CameraPlaceholderView: View {
    var body: some View {
        Color.black
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                VStack {
                    Image(systemName: "camera")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text(NSLocalizedString("select_camera", comment: "카메라 선택"))
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
    }
}

/// 권한 필요 안내 View 컴포넌트
/// 카메라/마이크 권한이 필요할 때 표시되는 안내 화면입니다.
struct PermissionRequiredView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            // 경고 아이콘
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            // 제목
            Text(NSLocalizedString("permission_settings_needed", comment: "권한 설정 필요"))
                .font(.title2)
                .bold()
            
            // 안내 메시지
            Text(viewModel.permissionViewModel.permissionGuideMessage)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            // 권한 설정 버튼
            Button(NSLocalizedString("go_to_permission_settings", comment: "권한 설정으로 이동")) {
                viewModel.showPermissionSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// 로딩 View 컴포넌트
/// 초기 로딩 상태를 표시하는 컴포넌트입니다.
struct LoadingView: View {
    var body: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text(NSLocalizedString("loading", comment: "로딩 중"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

 
