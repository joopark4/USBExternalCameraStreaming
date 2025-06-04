//
//  ContentView.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import SwiftUI
import SwiftData
import AVFoundation

/// 앱의 메인 뷰
struct ContentView: View {
    @StateObject private var cameraViewModel = CameraViewModel()
    @StateObject private var permissionViewModel: PermissionViewModel
    @State private var showingPermissionAlert = false
    @State private var isRefreshing = false
    @State private var selectedSidebarItem: SidebarItem = .cameras
    @State private var showingLiveStreamSettings = false
    
    init() {
        let manager = PermissionManager()
        _permissionViewModel = StateObject(wrappedValue: PermissionViewModel(permissionManager: manager))
    }
    
    var body: some View {
        NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .sheet(isPresented: $showingPermissionAlert) {
            PermissionSettingsView(viewModel: permissionViewModel)
        }
        .sheet(isPresented: $showingLiveStreamSettings) {
            LiveStreamPlaceholderSettingsView()
        }
    }
    
    @ViewBuilder
    private var sidebarView: some View {
        List {
            cameraSection
            liveStreamSection
        }
        .navigationTitle(NSLocalizedString("menu", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .topTrailing) {
            HStack {
                refreshButton
                settingsButton
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
        .overlay {
            if isRefreshing {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
        }
    }
    
    @ViewBuilder
    private var cameraSection: some View {
        Section(header: Text(NSLocalizedString("camera_section", comment: ""))) {
            NavigationLink(value: SidebarItem.cameras) {
                Label(NSLocalizedString("camera", comment: ""), systemImage: "camera")
            }
            
            if selectedSidebarItem == .cameras {
                cameraListView
            }
        }
    }
    
    @ViewBuilder
    private var cameraListView: some View {
        ForEach(cameraViewModel.builtInCameras) { camera in
            cameraRowView(camera: camera)
        }
        
        ForEach(cameraViewModel.externalCameras) { camera in
            cameraRowView(camera: camera)
        }
        
        if cameraViewModel.externalCameras.isEmpty {
            Text(NSLocalizedString("no_external_camera", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
                .padding(.leading, 20)
        }
    }
    
    @ViewBuilder
    private func cameraRowView(camera: CameraDevice) -> some View {
        CameraRow(
            camera: camera,
            isSelected: cameraViewModel.selectedCamera?.id == camera.id,
            onSelect: { cameraViewModel.switchToCamera(camera) }
        )
        .padding(.leading, 20)
    }
    
    @ViewBuilder
    private var liveStreamSection: some View {
        Section(header: Text(NSLocalizedString("live_streaming_section", comment: ""))) {
            Button {
                showingLiveStreamSettings = true
            } label: {
                Label(NSLocalizedString("live_streaming", comment: ""), systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }
    
    @ViewBuilder
    private var refreshButton: some View {
        Button {
            Task {
                isRefreshing = true
                await cameraViewModel.refreshCameraList()
                isRefreshing = false
            }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(isRefreshing)
    }
    
    @ViewBuilder
    private var settingsButton: some View {
        Button {
            showingPermissionAlert = true
        } label: {
            Image(systemName: "gear")
        }
    }
    
    @ViewBuilder
    private var detailView: some View {
        switch selectedSidebarItem {
        case .cameras:
            cameraDetailContent
        case .liveStream:
            LiveStreamPlaceholderView()
        }
    }
    
    @ViewBuilder
    private var cameraDetailContent: some View {
        if permissionViewModel.areAllPermissionsGranted {
            if cameraViewModel.selectedCamera != nil {
                CameraPreviewView(session: cameraViewModel.captureSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(30)
                    .background(Color.black)
            } else {
                cameraPlaceholder
            }
        } else {
            permissionRequiredView
        }
    }
    
    @ViewBuilder
    private var cameraPlaceholder: some View {
        Color.black
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                VStack {
                    Image(systemName: "camera")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text(NSLocalizedString("select_camera", comment: ""))
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
    }
    
    @ViewBuilder
    private var permissionRequiredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(NSLocalizedString("permission_settings_needed", comment: ""))
                .font(.title2)
                .bold()
            
            Text(permissionViewModel.permissionGuideMessage)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button(NSLocalizedString("go_to_permission_settings", comment: "")) {
                showingPermissionAlert = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// 사이드바 아이템 열거형
enum SidebarItem: String, CaseIterable {
    case cameras = "카메라"
    case liveStream = "라이브 스트리밍"
    
    var title: String {
        switch self {
        case .cameras:
            return NSLocalizedString("camera", comment: "")
        case .liveStream:
            return NSLocalizedString("live_streaming", comment: "")
        }
    }
    
    var iconName: String {
        switch self {
        case .cameras:
            return "camera"
        case .liveStream:
            return "dot.radiowaves.left.and.right"
        }
    }
}

/// 카메라 디테일 뷰
struct CameraDetailView: View {
    @ObservedObject var permissionViewModel: PermissionViewModel
    @ObservedObject var cameraViewModel: CameraViewModel
    @Binding var showingPermissionAlert: Bool
    
    var body: some View {
        if permissionViewModel.areAllPermissionsGranted {
            if cameraViewModel.selectedCamera != nil {
                CameraPreviewView(session: cameraViewModel.captureSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(30)
                    .background(Color.black)
            } else {
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        VStack {
                            Image(systemName: "camera")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text(NSLocalizedString("select_camera", comment: ""))
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                    }
            }
        } else {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                
                Text(NSLocalizedString("permission_settings_needed", comment: ""))
                    .font(.title2)
                    .bold()
                
                Text(permissionViewModel.permissionGuideMessage)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Button(NSLocalizedString("go_to_permission_settings", comment: "")) {
                    showingPermissionAlert = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

/// 라이브 스트리밍 임시 플레이스홀더 뷰
struct LiveStreamPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text(NSLocalizedString("youtube_live_streaming", comment: ""))
                .font(.title)
                .bold()
            
            Text(NSLocalizedString("haishinkit_integration_message", comment: ""))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("youtube_step1", comment: ""))
                }
                
                HStack {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("youtube_step2", comment: ""))
                }
                
                HStack {
                    Image(systemName: "3.circle.fill")
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("youtube_step3", comment: ""))
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
    }
}

/// 라이브 스트리밍 설정 임시 뷰
struct LiveStreamPlaceholderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "gear")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text(NSLocalizedString("live_streaming_settings", comment: ""))
                    .font(.title)
                    .bold()
                
                Text(NSLocalizedString("haishinkit_settings_message", comment: ""))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("live_settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 카메라 목록의 각 행을 표시하는 뷰
struct CameraRow: View {
    let camera: CameraDevice
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(camera.name)
                    .font(.caption)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
