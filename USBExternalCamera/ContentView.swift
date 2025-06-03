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
    
    init() {
        let manager = PermissionManager()
        _permissionViewModel = StateObject(wrappedValue: PermissionViewModel(permissionManager: manager))
    }

    var body: some View {
        NavigationSplitView {
            // 사이드바 (카메라 목록)
            CameraListView(
                builtInCameras: cameraViewModel.builtInCameras,
                externalCameras: cameraViewModel.externalCameras,
                selectedCamera: cameraViewModel.selectedCamera,
                onCameraSelected: { camera in
                    cameraViewModel.switchToCamera(camera)
                },
                onSettingsTapped: {
                    showingPermissionAlert = true
                },
                onRefreshTapped: {
                    Task {
                        isRefreshing = true
                        await cameraViewModel.refreshCameraList()
                        isRefreshing = false
                    }
                },
                isRefreshing: isRefreshing
            )
        } detail: {
            // 메인 영역 (카메라 프리뷰 또는 권한 안내)
            if permissionViewModel.areAllPermissionsGranted {
                if let selectedCamera = cameraViewModel.selectedCamera {
                    CameraPreviewView(session: cameraViewModel.captureSession)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(30)
                        .background(Color.black)
                } else {
                    Color.black
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("권한 설정이 필요합니다")
                        .font(.title2)
                        .bold()
                    
                    Text(permissionViewModel.permissionGuideMessage)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    Button("권한 설정하기") {
                        showingPermissionAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .navigationTitle("카메라")
        .sheet(isPresented: $showingPermissionAlert) {
            PermissionSettingsView(viewModel: permissionViewModel)
        }
    }
}

/// 카메라 목록 뷰
struct CameraListView: View {
    let builtInCameras: [CameraDevice]
    let externalCameras: [CameraDevice]
    let selectedCamera: CameraDevice?
    let onCameraSelected: (CameraDevice) -> Void
    let onSettingsTapped: () -> Void
    let onRefreshTapped: () -> Void
    let isRefreshing: Bool
    
    var body: some View {
        List {
            // 내장 카메라 섹션
            if !builtInCameras.isEmpty {
                Section("내장 카메라") {
                    ForEach(builtInCameras) { camera in
                        CameraRow(
                            camera: camera,
                            isSelected: selectedCamera?.id == camera.id,
                            onSelect: { onCameraSelected(camera) }
                        )
                    }
                }
            }
            
            // 외장 카메라 섹션 (항상 표시)
            Section("외장 카메라") {
                if externalCameras.isEmpty {
                    Text("연결된 외장 카메라가 없습니다")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(externalCameras) { camera in
                        CameraRow(
                            camera: camera,
                            isSelected: selectedCamera?.id == camera.id,
                            onSelect: { onCameraSelected(camera) }
                        )
                    }
                }
            }
        }
        .navigationTitle("카메라 목록")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: onRefreshTapped) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                    
                    Button(action: onSettingsTapped) {
                        Image(systemName: "gear")
                    }
                }
            }
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
}

/// 카메라 프리뷰 컨테이너 뷰
struct CameraPreviewContainerView: View {
    let cameraStatus: PermissionStatus
    let selectedCamera: CameraDevice?
    let captureSession: AVCaptureSession
    let onPermissionRequest: () -> Void
    
    var body: some View {
        if cameraStatus == .authorized {
            if let selectedCamera = selectedCamera {
                CameraPreviewView(session: captureSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                Text("연결된 카메라가 없습니다")
                    .font(.title)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 20) {
                Text("카메라 접근 권한이 필요합니다")
                    .font(.title2)
                
                Button("권한 요청", action: onPermissionRequest)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
