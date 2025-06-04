//
//  ContentView.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
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
        // 의존성 생성 및 주입
        let cameraViewModel = CameraViewModel()
        let permissionManager = PermissionManager()
        let permissionViewModel = PermissionViewModel(permissionManager: permissionManager)
        
        // MainViewModel 초기화 (의존성 주입)
        _mainViewModel = StateObject(wrappedValue: MainViewModel(
            cameraViewModel: cameraViewModel,
            permissionViewModel: permissionViewModel
        ))
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
            LiveStreamPlaceholderSettingsView()
        }
    }
}

// MARK: - Sidebar Components

/// 사이드바 View 컴포넌트
/// 메뉴 네비게이션과 카메라 목록을 담당하는 독립적인 View 컴포넌트입니다.
struct SidebarView: View {
    /// MainViewModel 참조 (ObservedObject로 상태 변화 감지)
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        List {
            // 카메라 섹션: 카메라 관련 메뉴와 디바이스 목록
            CameraSectionView(viewModel: viewModel)
            
            // 라이브 스트리밍 섹션: 라이브 스트리밍 관련 메뉴
            LiveStreamSectionView(viewModel: viewModel)
        }
        .navigationTitle(NSLocalizedString("menu", comment: "메뉴"))
        .navigationBarTitleDisplayMode(.inline)
        // 툴바에 버튼들 배치
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    // 새로고침 버튼
                    Button {
                        print("🔄 RefreshButton: Button tapped")
                        viewModel.refreshCameraList()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isRefreshing)
                    
                    // 설정 버튼
                    Button {
                        print("🔧 SettingsButton: Button tapped")
                        viewModel.showPermissionSettings()
                    } label: {
                        Image(systemName: "gear")
                    }
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

/// 카메라 섹션 View 컴포넌트
/// 카메라 메뉴와 디바이스 목록을 표시하는 재사용 가능한 컴포넌트입니다.
struct CameraSectionView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        Section(header: Text(NSLocalizedString("camera_section", comment: "카메라 섹션"))) {
            // 카메라 메인 메뉴 아이템
            NavigationLink(value: SidebarItem.cameras) {
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
        // 내장 카메라 목록
        ForEach(viewModel.cameraViewModel.builtInCameras) { camera in
            CameraRowView(
                camera: camera,
                isSelected: viewModel.cameraViewModel.selectedCamera?.id == camera.id,
                onSelect: { viewModel.selectCamera(camera) }
            )
        }
        
        // 외장 카메라 목록
        ForEach(viewModel.cameraViewModel.externalCameras) { camera in
            CameraRowView(
                camera: camera,
                isSelected: viewModel.cameraViewModel.selectedCamera?.id == camera.id,
                onSelect: { viewModel.selectCamera(camera) }
            )
        }
        
        // 외장 카메라가 없는 경우 안내 메시지
        if viewModel.cameraViewModel.externalCameras.isEmpty {
            EmptyExternalCameraView()
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
        Button(action: onSelect) {
            HStack {
                Text(camera.name)
                    .font(.caption)
                Spacer()
                // 선택된 카메라 표시
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
        }
        .padding(.leading, 20)
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

/// 라이브 스트리밍 섹션 View 컴포넌트
/// 라이브 스트리밍 관련 메뉴를 표시하는 독립적인 컴포넌트입니다.
struct LiveStreamSectionView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        Section(header: Text(NSLocalizedString("live_streaming_section", comment: "라이브 스트리밍 섹션"))) {
            Button {
                viewModel.showLiveStreamSettings()
            } label: {
                Label(NSLocalizedString("live_streaming", comment: "라이브 스트리밍"), 
                      systemImage: "dot.radiowaves.left.and.right")
            }
        }
    }
}

/// 로딩 오버레이 View 컴포넌트
/// 새로고침 등의 비동기 작업 중에 표시되는 로딩 인디케이터입니다.
struct LoadingOverlayView: View {
    var body: some View {
        ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.2))
    }
}

// MARK: - Detail View Components

/// 상세 화면 View 컴포넌트
/// 선택된 사이드바 항목에 따라 적절한 콘텐츠를 표시하는 컴포넌트입니다.
struct DetailView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        switch viewModel.selectedSidebarItem {
        case .cameras:
            // 카메라 상세 화면
            CameraDetailContentView(viewModel: viewModel)
        case .liveStream:
            // 라이브 스트리밍 상세 화면
            LiveStreamPlaceholderView()
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
struct CameraPreviewContainerView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        CameraPreviewView(session: viewModel.cameraViewModel.captureSession)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
            .background(Color.black)
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

// MARK: - Live Streaming Components

/// 라이브 스트리밍 플레이스홀더 View 컴포넌트
/// 라이브 스트리밍 기능의 임시 화면을 표시합니다.
struct LiveStreamPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            // 라이브 스트리밍 아이콘
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            // 제목
            Text(NSLocalizedString("youtube_live_streaming", comment: "유튜브 라이브 스트리밍"))
                .font(.title)
                .bold()
            
            // 안내 메시지
            Text(NSLocalizedString("haishinkit_integration_message", comment: "HaishinKit 통합 메시지"))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            // 설정 단계 안내
            LiveStreamStepsView()
        }
        .padding()
    }
}

/// 라이브 스트리밍 설정 단계 안내 View 컴포넌트
/// 라이브 스트리밍 설정 방법을 단계별로 안내하는 컴포넌트입니다.
struct LiveStreamStepsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiveStreamStepRow(
                stepNumber: "1",
                stepText: NSLocalizedString("youtube_step1", comment: "1단계")
            )
            
            LiveStreamStepRow(
                stepNumber: "2",
                stepText: NSLocalizedString("youtube_step2", comment: "2단계")
            )
            
            LiveStreamStepRow(
                stepNumber: "3",
                stepText: NSLocalizedString("youtube_step3", comment: "3단계")
            )
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

/// 라이브 스트리밍 단계 행 View 컴포넌트
/// 각 설정 단계를 표시하는 재사용 가능한 컴포넌트입니다.
struct LiveStreamStepRow: View {
    let stepNumber: String
    let stepText: String
    
    var body: some View {
        HStack {
            Image(systemName: "\(stepNumber).circle.fill")
                .foregroundColor(.blue)
            Text(stepText)
        }
    }
}

/// 라이브 스트리밍 설정 플레이스홀더 View 컴포넌트
/// 라이브 스트리밍 설정 화면의 임시 구현입니다.
struct LiveStreamPlaceholderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 설정 아이콘
                Image(systemName: "gear")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                // 제목
                Text(NSLocalizedString("live_streaming_settings", comment: "라이브 스트리밍 설정"))
                    .font(.title)
                    .bold()
                
                // 안내 메시지
                Text(NSLocalizedString("haishinkit_settings_message", comment: "HaishinKit 설정 메시지"))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("live_settings", comment: "라이브 설정"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("done", comment: "완료")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Legacy Components (Backward Compatibility)

/// 레거시 카메라 상세 View (하위 호환성)
/// 기존 코드와의 호환성을 위한 레거시 컴포넌트입니다.
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
                            Text(NSLocalizedString("select_camera", comment: "카메라 선택"))
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
                
                Text(NSLocalizedString("permission_settings_needed", comment: "권한 설정 필요"))
                    .font(.title2)
                    .bold()
                
                Text(permissionViewModel.permissionGuideMessage)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Button(NSLocalizedString("go_to_permission_settings", comment: "권한 설정으로 이동")) {
                    showingPermissionAlert = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

/// 레거시 카메라 행 컴포넌트 (하위 호환성)
/// 기존 코드와의 호환성을 위한 레거시 컴포넌트입니다.
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

// MARK: - Preview

#Preview {
    ContentView()
}
