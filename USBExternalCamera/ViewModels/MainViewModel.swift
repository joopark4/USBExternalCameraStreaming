//
//  MainViewModel.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import Foundation
import SwiftUI
import SwiftData
import Combine
import AVFoundation

/// 메인 화면의 ViewModel
/// MVVM 패턴에서 View와 Model 사이의 중간층 역할을 담당합니다.
/// UI 상태 관리, 사용자 상호작용 처리, 비즈니스 로직 조율을 담당합니다.
@MainActor
final class MainViewModel: ObservableObject {
    
    // MARK: - Published Properties (UI State)
    
    /// 현재 선택된 사이드바 항목
    /// 메인 화면의 상세 내용을 결정합니다.
    @Published var selectedSidebarItem: SidebarItem = .cameras
    
    /// 권한 설정 시트 표시 여부
    /// 카메라/마이크 권한 설정 UI 제어
    @Published var showingPermissionAlert = false
    
    /// 라이브 스트리밍 설정 시트 표시 여부
    /// 라이브 스트리밍 설정 UI 제어
    @Published var showingLiveStreamSettings = false
    
    /// 로깅 설정 시트 표시 여부 (개발용)
    /// 로깅 설정 UI 제어 - 디버그 모드에서만 사용
    @Published var showingLoggingSettings = false
    
    /// 새로고침 진행 상태
    /// 카메라 목록 새로고침 시 로딩 UI 표시
    @Published var isRefreshing = false
    
    /// 현재 권한 상태에 따른 UI 상태
    /// 권한이 있으면 카메라 화면, 없으면 권한 요청 화면 표시
    @Published var currentUIState: UIState = .loading
    
    // MARK: - Dependencies (Models)
    
    /// 카메라 관련 비즈니스 로직을 담당하는 ViewModel
    let cameraViewModel: CameraViewModel
    
    /// 권한 관련 비즈니스 로직을 담당하는 ViewModel
    let permissionViewModel: PermissionViewModel
    
    /// 라이브 스트리밍 관련 비즈니스 로직을 담당하는 ViewModel
    let liveStreamViewModel: LiveStreamViewModel
    
    // MARK: - Private Properties
    
    /// Combine 구독 관리
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// MainViewModel 초기화
    /// 의존성 주입을 통해 각 ViewModel을 받아 초기화합니다.
    /// - Parameters:
    ///   - cameraViewModel: 카메라 기능 관리 ViewModel
    ///   - permissionViewModel: 권한 관리 ViewModel
    ///   - liveStreamViewModel: 라이브 스트리밍 관리 ViewModel
    init(cameraViewModel: CameraViewModel, permissionViewModel: PermissionViewModel, liveStreamViewModel: LiveStreamViewModel) {
        self.cameraViewModel = cameraViewModel
        self.permissionViewModel = permissionViewModel
        self.liveStreamViewModel = liveStreamViewModel
        
        setupBindings()
        
        // 개선: 초기 UI 상태를 즉시 설정하여 로딩 시간 단축
        updateUIState()
        
        // 비동기로 권한 상태를 다시 확인하여 최신 상태로 업데이트
        Task {
            // 백그라운드에서 권한 상태 재확인
            await refreshPermissionStatus()
            await MainActor.run {
                updateUIState()
            }
        }
    }
    
    /// 권한 상태를 백그라운드에서 새로고침 (성능 최적화)
    private func refreshPermissionStatus() async {
        // 현재 권한 상태를 비동기로 재확인
        permissionViewModel.permissionManager.checkPermissions()
    }
    
    // MARK: - Public Methods (User Actions)
    
    /// 사이드바 항목 선택 처리
    /// - Parameter item: 선택된 사이드바 항목
    func selectSidebarItem(_ item: SidebarItem) {
        selectedSidebarItem = item
    }
    
    /// 권한 설정 화면 표시
    func showPermissionSettings() {
        logDebug("🔧 MainViewModel: showPermissionSettings() called", category: .ui)
        showingPermissionAlert = true
        logDebug("🔧 MainViewModel: showingPermissionAlert set to \(showingPermissionAlert)", category: .ui)
    }
    
    /// 라이브 스트리밍 설정 화면 표시
    func showLiveStreamSettings() {
        logDebug("📺 MainViewModel: showLiveStreamSettings() called", category: .ui)
        showingLiveStreamSettings = true
        logDebug("📺 MainViewModel: showingLiveStreamSettings set to \(showingLiveStreamSettings)", category: .ui)
    }
    
    /// 로깅 설정 화면 표시 (개발용)
    func showLoggingSettings() {
        logInfo("Showing logging settings", category: .ui)
        showingLoggingSettings = true
    }
    
    /// 카메라 목록 새로고침 실행
    /// 비동기적으로 카메라 목록을 새로고침하고 UI 상태를 업데이트합니다.
    func refreshCameraList() {
        logDebug("🔄 MainViewModel: refreshCameraList() called", category: .ui)
        Task {
            logDebug("🔄 MainViewModel: Starting refresh task", category: .ui)
            isRefreshing = true
            logDebug("🔄 MainViewModel: isRefreshing set to \(isRefreshing)", category: .ui)
            await cameraViewModel.refreshCameraList()
            logDebug("🔄 MainViewModel: Camera list refresh completed", category: .ui)
            isRefreshing = false
            logDebug("🔄 MainViewModel: isRefreshing set to \(isRefreshing)", category: .ui)
        }
    }
    
    /// 카메라 선택 처리
    /// - Parameter camera: 선택할 카메라 디바이스
    func selectCamera(_ camera: CameraDevice) {
        logDebug("🔄 MainViewModel: Selecting camera \(camera.name) (ID: \(camera.id))", category: .ui)
        print("🔄 MainViewModel: Current selected camera: \(cameraViewModel.selectedCamera?.name ?? "None")")
        print("🔄 MainViewModel: Current selected camera ID: \(cameraViewModel.selectedCamera?.id ?? "None")")
        
        // 이미 선택된 카메라인지 확인
        if cameraViewModel.selectedCamera?.id == camera.id {
            logDebug("🔄 MainViewModel: Camera \(camera.name) is already selected, skipping", category: .ui)
            return
        }
        
        // 카메라 전환 실행 - @Published 속성이 자동으로 UI 업데이트
        cameraViewModel.switchToCamera(camera)
        
        // 강제로 UI 상태 업데이트
        updateUIState()
        
        // 디버깅을 위한 상태 확인
        print("🔄 MainViewModel: After selection - New selected camera: \(cameraViewModel.selectedCamera?.name ?? "None")")
        print("🔄 MainViewModel: After selection - New selected camera ID: \(cameraViewModel.selectedCamera?.id ?? "None")")
        logDebug("🔄 MainViewModel: Selection match check: \(cameraViewModel.selectedCamera?.id == camera.id)", category: .ui)
        
        // 약간의 지연 후 다시 한 번 확인 (디버깅용)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🔄 MainViewModel: [Delayed check] Selected camera: \(self.cameraViewModel.selectedCamera?.name ?? "None")")
            print("🔄 MainViewModel: [Delayed check] Selected camera ID: \(self.cameraViewModel.selectedCamera?.id ?? "None")")
        }
    }
    
    // MARK: - Private Methods
    
    /// 반응형 바인딩 설정
    /// ViewModel들 간의 상태 변화를 구독하여 UI 상태를 자동으로 업데이트합니다.
    private func setupBindings() {
        // 권한 상태 변화 감지
        permissionViewModel.$areAllPermissionsGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (areGranted: Bool) in
                self?.updateUIState()
            }
            .store(in: &cancellables)
        
        // 카메라 선택 상태 변화 감지
        cameraViewModel.$selectedCamera
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (camera: CameraDevice?) in
                self?.updateUIState()
            }
            .store(in: &cancellables)
    }
    
    /// 현재 상태에 따른 UI 상태 업데이트
    /// 권한 상태와 카메라 선택 상태에 따라 적절한 UI를 결정합니다.
    private func updateUIState() {
        let newState: UIState
        
        if !permissionViewModel.areAllPermissionsGranted {
            newState = .permissionRequired
        } else if cameraViewModel.selectedCamera == nil {
            newState = .cameraNotSelected
        } else {
            newState = .cameraActive
        }
        
        // 개선: 상태가 실제로 변경된 경우에만 업데이트하여 불필요한 UI 리렌더링 방지
        if currentUIState != newState {
            currentUIState = newState
            logDebug("🔄 UI State changed to: \(newState)", category: .ui)
        }
    }
}

// MARK: - Supporting Types

/// UI 상태를 나타내는 열거형
/// 현재 앱의 상태에 따라 적절한 UI를 결정하는데 사용됩니다.
enum UIState {
    /// 로딩 중
    case loading
    /// 권한 필요
    case permissionRequired
    /// 카메라 미선택
    case cameraNotSelected
    /// 카메라 활성화
    case cameraActive
}

/// 사이드바 항목을 나타내는 열거형
/// 앱의 주요 기능 영역을 구분합니다.
enum SidebarItem: String, CaseIterable {
    case cameras = "cameras_tab"
    case liveStream = "live_stream_tab"
    
    var displayName: String {
        switch self {
        case .cameras:
            return NSLocalizedString("camera", comment: "카메라")
        case .liveStream:
            return NSLocalizedString("live_streaming", comment: "라이브 스트리밍")
        }
    }
    
    /// 시스템 아이콘 이름
    var iconName: String {
        switch self {
        case .cameras:
            return "camera"
        case .liveStream:
            return "dot.radiowaves.left.and.right"
        }
    }
} 
