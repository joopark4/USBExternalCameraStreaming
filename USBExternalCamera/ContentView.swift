//
//  ContentView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import SwiftData

// MARK: - Main View (MVVM Architecture)

/// 앱의 메인 화면 View
struct ContentView: View {
    
    @StateObject private var mainViewModel: MainViewModel
    
    // MARK: - Initialization
    
    init() {
        // SwiftData ModelContainer 접근
        let container = try! ModelContainer(for: LiveStreamSettingsModel.self)
        
        // 의존성 생성 및 주입
        let cameraViewModel = CameraViewModel()
        let permissionManager = PermissionManager()
        let permissionViewModel = PermissionViewModel(permissionManager: permissionManager)
        let liveStreamViewModel = LiveStreamViewModel(modelContext: container.mainContext)
        
        _mainViewModel = StateObject(wrappedValue: MainViewModel(
            cameraViewModel: cameraViewModel,
            permissionViewModel: permissionViewModel,
            liveStreamViewModel: liveStreamViewModel
        ))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: mainViewModel)
        } detail: {
            DetailView(viewModel: mainViewModel)
        }
        .sheet(isPresented: $mainViewModel.showingPermissionAlert) {
            PermissionSettingsView(viewModel: mainViewModel.permissionViewModel)
        }
        .sheet(isPresented: $mainViewModel.showingLiveStreamSettings) {
            LiveStreamSettingsView(viewModel: mainViewModel.liveStreamViewModel)
        }
        .sheet(isPresented: $mainViewModel.showingLoggingSettings) {
            LoggingSettingsView()
        }
        .sheet(isPresented: $mainViewModel.showingTextSettings) {
            TextOverlaySettingsView(viewModel: mainViewModel)
        }
    }
}



// MARK: - Preview

#Preview {
    ContentView()
}
