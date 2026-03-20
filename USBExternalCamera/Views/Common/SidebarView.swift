//
//  SidebarView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import LiveStreamingCore

// MARK: - Sidebar Components

/// 사이드바 View 컴포넌트
/// 메뉴 네비게이션과 카메라 목록을 담당하는 독립적인 View 컴포넌트입니다.
struct SidebarView: View {
    /// MainViewModel 참조 (ObservedObject로 상태 변화 감지)
    @ObservedObject var viewModel: MainViewModel
    let onPrimarySelection: () -> Void
    let onShowLiveStreamSettings: () -> Void

    init(
        viewModel: MainViewModel,
        onPrimarySelection: @escaping () -> Void = {},
        onShowLiveStreamSettings: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onPrimarySelection = onPrimarySelection
        self.onShowLiveStreamSettings = onShowLiveStreamSettings
    }
    
    var body: some View {
        List {
            // 카메라 섹션: 카메라 관련 메뉴와 디바이스 목록
            CameraSectionView(
                viewModel: viewModel,
                onPrimarySelection: onPrimarySelection
            )
            
            // 라이브 스트리밍 섹션: 라이브 스트리밍 관련 메뉴
            LiveStreamSectionView(
                viewModel: viewModel.liveStreamViewModel,
                onShowSettings: onShowLiveStreamSettings
            )
        }
        .navigationTitle(NSLocalizedString("menu", comment: "메뉴"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // 새로고침 버튼
                    Button {
                        logDebug("🔄 RefreshButton: Button tapped", category: .ui)
                        viewModel.refreshCameraList()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRefreshing)
                    
                    // 로깅 설정 버튼 (디버그 모드에서만 표시)
                    if LoggingManager.shared.isDebugMode {
                        Button {
                            viewModel.showLoggingSettings()
                        } label: {
                            Image(systemName: "doc.text.magnifyingglass")
                        }
                        .foregroundColor(.orange)
                    }
                    
                    // 권한 설정 버튼
                    Button {
                        logDebug("🔧 PermissionButton: Button tapped", category: .ui)
                        viewModel.showPermissionSettings()
                    } label: {
                        Image(systemName: "gear")
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        // 로딩 오버레이: 새로고침 시 표시
        .overlay {
            if viewModel.isRefreshing {
                LoadingOverlayView()
            }
        }
    }
}

// MARK: - Common UI Components

/// 로딩 오버레이 View 컴포넌트
/// 새로고침이나 로딩 상태를 표시하는 재사용 가능한 컴포넌트입니다.
struct LoadingOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text(NSLocalizedString("refreshing", comment: "새로고침 중..."))
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.7))
            )
        }
    }
} 
