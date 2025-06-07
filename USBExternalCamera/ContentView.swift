//
//  ContentView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Main View (MVVM Architecture)

/// 앱의 메인 화면 View
/// MVVM 패턴에서 View 역할을 담당하며, UI 렌더링과 사용자 상호작용을 처리합니다.
/// ViewModel을 통해 비즈니스 로직과 분리되어 있어 테스트 가능하고 유지보수가 용이합니다.
struct ContentView: View {
    
    // MARK: - ViewModel Dependencies
    
    /// 메인 화면의 상태와 비즈니스 로직을 관리하는 ViewModel
    /// UI 상태, 사용자 액션, 데이터 바인딩을 담당합니다.
    @StateObject private var mainViewModel: MainViewModel
    
    // MARK: - Initialization
    
    /// ContentView 초기화
    /// 의존성 주입을 통해 필요한 ViewModel들을 생성하고 주입합니다.
    init() {
        // SwiftData ModelContainer 접근
        let container = try! ModelContainer(for: LiveStreamSettingsModel.self)
        
        // 의존성 생성 및 주입
        let cameraViewModel = CameraViewModel()
        let permissionManager = PermissionManager()
        let permissionViewModel = PermissionViewModel(permissionManager: permissionManager)
        let liveStreamViewModel = LiveStreamViewModel(modelContext: container.mainContext)
        
        // MainViewModel 초기화 (의존성 주입)
        _mainViewModel = StateObject(wrappedValue: MainViewModel(
            cameraViewModel: cameraViewModel,
            permissionViewModel: permissionViewModel,
            liveStreamViewModel: liveStreamViewModel
        ))
        
        // 카메라와 스트리밍 연결 설정
        if let haishinKitManager = liveStreamViewModel.streamingService as? HaishinKitManager {
            cameraViewModel.connectToStreaming(haishinKitManager)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationSplitView {
            // 사이드바 영역: 메뉴 네비게이션 담당
            SidebarView(viewModel: mainViewModel)
        } detail: {
            // 상세 화면 영역: 선택된 메뉴에 따른 콘텐츠 표시
            DetailView(viewModel: mainViewModel)
        }
        // 모달 시트들: 설정 화면들
        .sheet(isPresented: $mainViewModel.showingPermissionAlert) {
            PermissionSettingsView(viewModel: mainViewModel.permissionViewModel)
        }
        .sheet(isPresented: $mainViewModel.showingLiveStreamSettings) {
            LiveStreamSettingsView(viewModel: mainViewModel.liveStreamViewModel)
        }
        .sheet(isPresented: $mainViewModel.showingLoggingSettings) {
            LoggingSettingsView()
        }
    }
}

// MARK: - Views Organization
// Views have been refactored into separate files for better code organization:
// - Views/SidebarView.swift: Contains SidebarView and LoadingOverlayView
// - Views/CameraListView.swift: Contains camera-related views (CameraSectionView, CameraListView, CameraRowView, EmptyExternalCameraView)
// - Views/LiveStreamView.swift: Contains live streaming views (LiveStreamSectionView)
// - Views/DetailView.swift: Contains detail view components (DetailView, CameraDetailContentView, etc.)

// MARK: - Preview

#Preview {
    ContentView()
}
