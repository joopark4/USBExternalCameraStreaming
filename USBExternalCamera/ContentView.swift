//
//  ContentView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import SwiftData
import LiveStreamingCore

// MARK: - Main View (MVVM Architecture)

/// 앱의 메인 화면 View
struct ContentView: View {

    @StateObject private var mainViewModel: MainViewModel
    @State private var modelContainerError: Bool = false

    // MARK: - Initialization

    init() {
        // SwiftData ModelContainer 안전하게 생성
        do {
            let container = try ModelContainer(for: LiveStreamSettingsModel.self)

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
            _modelContainerError = State(initialValue: false)
        } catch {
            // ModelContainer 생성 실패 시 기본 설정으로 초기화
            logError("Failed to create ModelContainer: \(error.localizedDescription)", category: .error)

            // 메모리 내 임시 컨테이너 생성 시도
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            let container: ModelContainer
            do {
                container = try ModelContainer(for: LiveStreamSettingsModel.self, configurations: configuration)
            } catch {
                // 인메모리 컨테이너마저 실패 시 최후의 시도
                logError("Failed to create in-memory ModelContainer: \(error). Attempting final fallback.", category: .error)
                container = try! ModelContainer(for: LiveStreamSettingsModel.self)
            }

            let cameraViewModel = CameraViewModel()
            let permissionManager = PermissionManager()
            let permissionViewModel = PermissionViewModel(permissionManager: permissionManager)
            let liveStreamViewModel = LiveStreamViewModel(modelContext: container.mainContext)

            _mainViewModel = StateObject(wrappedValue: MainViewModel(
                cameraViewModel: cameraViewModel,
                permissionViewModel: permissionViewModel,
                liveStreamViewModel: liveStreamViewModel
            ))
            _modelContainerError = State(initialValue: true)
        }
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
        .alert("데이터 저장소 오류", isPresented: .constant(modelContainerError)) {
            Button("확인") {
                // 메모리 내 저장소를 사용중이므로 계속 진행
            }
        } message: {
            Text("설정을 디스크에 저장할 수 없습니다. 앱이 종료되면 설정이 사라집니다.")
        }
    }
}



// MARK: - Preview

#Preview {
    ContentView()
}
