//
//  CameraListView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import LiveStreamingCore

// MARK: - Camera List Components

/// 카메라 섹션 View 컴포넌트
/// 카메라 메뉴와 디바이스 목록을 표시하는 재사용 가능한 컴포넌트입니다.
struct CameraSectionView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        Section(header: Text(NSLocalizedString("camera_section", comment: "카메라 섹션"))) {
            // 카메라 메인 메뉴 아이템
            Button {
                viewModel.selectSidebarItem(.cameras)
            } label: {
                Label(NSLocalizedString("camera", comment: "카메라"), systemImage: "camera")
            }
            
            // 카메라가 선택된 경우 디바이스 목록 표시
            if viewModel.selectedSidebarItem == .cameras {
                CameraListView(viewModel: viewModel)
            }
        }
    }
}

/// 카메라 디바이스 목록 View 컴포넌트
/// 내장 카메라와 외장 카메라 목록을 표시하고 선택 기능을 제공합니다.
struct CameraListView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        // 디버깅을 위한 카메라 목록 상태 로깅
        let builtInCount = viewModel.cameraViewModel.builtInCameras.count
        let externalCount = viewModel.cameraViewModel.externalCameras.count
        let selectedCamera = viewModel.cameraViewModel.selectedCamera
        let selectedCameraId = selectedCamera?.id
        let selectedCameraName = selectedCamera?.name
        
        VStack(alignment: .leading, spacing: 4) {
            // 실시간 상태 표시를 위한 헤더
            if let selectedCamera = selectedCamera {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text(NSLocalizedString("selected_camera", comment: "선택됨: ") + "\(selectedCamera.name)")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                .padding(.leading, 20)
                .padding(.vertical, 2)
            }
            
            // 카메라 목록 상태 표시 (디버깅용)
            Text(String.localizedStringWithFormat(NSLocalizedString("camera_count_status", comment: "내장: %d개, 외장: %d개"), builtInCount, externalCount))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 20)
            
            // 내장 카메라 목록
            ForEach(viewModel.cameraViewModel.builtInCameras) { camera in
                CameraRowView(
                    camera: camera,
                    isSelected: selectedCameraId == camera.id,
                    onSelect: { 
                                  logDebug("=== BUILT-IN CAMERA SELECTION ===", category: .camera)
          logDebug("Target camera: \(camera.name)", category: .camera)
          logDebug("Target ID: \(camera.id)", category: .camera)
          logDebug("Target type: \(camera.deviceType)", category: .camera)
          logDebug("Target position: \(camera.position)", category: .camera)
          logDebug("Current selected: \(selectedCameraName ?? "None")", category: .camera)
          logDebug("Current selected ID: \(selectedCameraId ?? "None")", category: .camera)
          logDebug("Is already selected: \(selectedCameraId == camera.id)", category: .camera)
          logDebug("=====================================", category: .camera)
                        
                        if selectedCameraId != camera.id {
                            logDebug("Proceeding with built-in camera selection...", category: .camera)
                            viewModel.selectCamera(camera)
                            
                            // 강제 UI 갱신을 위한 추가 작업
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                let newSelectedId = viewModel.cameraViewModel.selectedCamera?.id
                                                            logDebug("[Post-Selection Built-in] Selected ID: \(newSelectedId ?? "None")", category: .camera)
                            logDebug("[Post-Selection Built-in] Target ID: \(camera.id)", category: .camera)
                            logDebug("[Post-Selection Built-in] Match: \(newSelectedId == camera.id)", category: .camera)
                                
                                // UI 강제 새로고침
                                viewModel.objectWillChange.send()
                            }
                        } else {
                            logDebug("Skipping selection - built-in camera already selected", category: .camera)
                        }
                    }
                )
            }
            
            // 외장 카메라 목록
            ForEach(viewModel.cameraViewModel.externalCameras) { camera in
                CameraRowView(
                    camera: camera,
                    isSelected: selectedCameraId == camera.id,
                    onSelect: { 
                                  logDebug("=== EXTERNAL CAMERA SELECTION ===", category: .camera)
          logDebug("Target camera: \(camera.name)", category: .camera)
          logDebug("Target ID: \(camera.id)", category: .camera)
          logDebug("Target type: \(camera.deviceType)", category: .camera)
          logDebug("Target position: \(camera.position)", category: .camera)
          logDebug("Current selected: \(selectedCameraName ?? "None")", category: .camera)
          logDebug("Current selected ID: \(selectedCameraId ?? "None")", category: .camera)
          logDebug("Is already selected: \(selectedCameraId == camera.id)", category: .camera)
          logDebug("=====================================", category: .camera)
                        
                        if selectedCameraId != camera.id {
                            logDebug("Proceeding with external camera selection...", category: .camera)
                            viewModel.selectCamera(camera)
                            
                            // 강제 UI 갱신을 위한 추가 작업
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                let newSelectedId = viewModel.cameraViewModel.selectedCamera?.id
                                                            logDebug("[Post-Selection External] Selected ID: \(newSelectedId ?? "None")", category: .camera)
                            logDebug("[Post-Selection External] Target ID: \(camera.id)", category: .camera)
                            logDebug("[Post-Selection External] Match: \(newSelectedId == camera.id)", category: .camera)
                                
                                // UI 강제 새로고침
                                viewModel.objectWillChange.send()
                            }
                        } else {
                            logDebug("Skipping selection - external camera already selected", category: .camera)
                        }
                    }
                )
            }
            
            // 외장 카메라가 없는 경우 안내 메시지
            if viewModel.cameraViewModel.externalCameras.isEmpty {
                EmptyExternalCameraView()
            }
            
            // 카메라가 전혀 없는 경우 안내 메시지
            if builtInCount == 0 && externalCount == 0 {
                Text(NSLocalizedString("no_camera_found", comment: "카메라를 찾을 수 없습니다"))
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading, 20)
            }
        }
        .onAppear {
                    logDebug("View appeared", category: .camera)
        logDebug("Built-in cameras: \(builtInCount)", category: .camera)
        logDebug("External cameras: \(externalCount)", category: .camera)
        logDebug("Selected camera: \(selectedCameraName ?? "None") (ID: \(selectedCameraId ?? "None"))", category: .camera)
        }
    }
}

/// 개별 카메라 행 View 컴포넌트
/// 각 카메라 디바이스를 표시하고 선택 기능을 제공하는 재사용 가능한 컴포넌트입니다.
struct CameraRowView: View {
    let camera: CameraDevice
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(camera.name)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            Spacer()
            // 선택된 카메라 표시 - 더 명확한 체크표시
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                    .font(.body)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
                    .font(.body)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue : Color.clear)
        )
        .contentShape(Rectangle()) // 전체 영역을 터치 가능하게 만듦
        .onTapGesture {
                    logDebug("=== TAP GESTURE ===", category: .camera)
        logDebug("Camera: \(camera.name)", category: .camera)
        logDebug("ID: \(camera.id)", category: .camera)
        logDebug("Type: \(camera.deviceType)", category: .camera)
        logDebug("Position: \(camera.position)", category: .camera)
        logDebug("isSelected: \(isSelected)", category: .camera)
        logDebug("===================", category: .camera)
            
            // 햅틱 피드백 추가
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            onSelect()
            
            logDebug("onSelect() called for \(camera.name)", category: .camera)
        }
        .onAppear {
            logDebug("\(camera.name) appeared - ID: \(camera.id), isSelected: \(isSelected)", category: .camera)
        }
        .onChange(of: isSelected) { oldValue, newValue in
            logDebug("\(camera.name) (ID: \(camera.id)) isSelected changed from \(oldValue) to: \(newValue)", category: .camera)
            if newValue {
                logDebug("✅ \(camera.name) is now SELECTED", category: .camera)
            } else {
                logDebug("❌ \(camera.name) is now DESELECTED", category: .camera)
            }
        }
    }
}

/// 외장 카메라 없음 안내 View 컴포넌트
/// 외장 카메라가 연결되지 않았을 때 표시되는 안내 메시지입니다.
struct EmptyExternalCameraView: View {
    var body: some View {
        Text(NSLocalizedString("no_external_camera", comment: "외장 카메라 없음"))
            .font(.caption)
            .foregroundColor(.secondary)
            .italic()
            .padding(.leading, 20)
    }
} 