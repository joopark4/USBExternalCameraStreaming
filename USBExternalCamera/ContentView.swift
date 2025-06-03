//
//  ContentView.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import SwiftUI
import SwiftData

/// 앱의 메인 뷰
struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @StateObject private var permissionManager = PermissionManager()
    @State private var showingPermissionAlert = false

    var body: some View {
        NavigationSplitView {
            // 사이드바 (카메라 목록)
            List(viewModel.externalCameras) { camera in
                Button(action: {
                    viewModel.switchToCamera(camera)
                }) {
                    HStack {
                        Text(camera.name)
                        Spacer()
                        if viewModel.selectedCamera?.id == camera.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("카메라 목록")
        } detail: {
            // 메인 영역 (카메라 프리뷰)
            if permissionManager.cameraStatus == .authorized {
                if let selectedCamera = viewModel.selectedCamera {
                    CameraPreviewView(session: viewModel.captureSession)
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
                    
                    Button("권한 요청") {
                        Task {
                            await permissionManager.requestCameraPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("외장 카메라")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingPermissionAlert = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
        .alert("권한 설정", isPresented: $showingPermissionAlert) {
            Button("카메라") {
                Task {
                    await permissionManager.requestCameraPermission()
                }
            }
            Button("마이크") {
                Task {
                    await permissionManager.requestMicrophonePermission()
                }
            }
            Button("사진첩") {
                Task {
                    await permissionManager.requestPhotoLibraryPermission()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            VStack(alignment: .leading, spacing: 10) {
                Text("카메라: \(permissionStatusText(permissionManager.cameraStatus))")
                Text("마이크: \(permissionStatusText(permissionManager.microphoneStatus))")
                Text("사진첩: \(permissionStatusText(permissionManager.photoLibraryStatus))")
            }
        }
    }
    
    /// 권한 상태를 텍스트로 변환
    private func permissionStatusText(_ status: PermissionStatus) -> String {
        switch status {
        case .notDetermined:
            return "확인 안됨"
        case .restricted:
            return "제한됨"
        case .denied:
            return "거부됨"
        case .authorized:
            return "허용됨"
        }
    }
}

#Preview {
    ContentView()
}
