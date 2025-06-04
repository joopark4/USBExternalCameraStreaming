//
//  MainViewModel.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import Foundation
import SwiftUI
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
    
    // MARK: - Private Properties
    
    /// Combine 구독 관리
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// MainViewModel 초기화
    /// 의존성 주입을 통해 각 ViewModel을 받아 초기화합니다.
    /// - Parameters:
    ///   - cameraViewModel: 카메라 기능 관리 ViewModel
    ///   - permissionViewModel: 권한 관리 ViewModel
    init(cameraViewModel: CameraViewModel, permissionViewModel: PermissionViewModel) {
        self.cameraViewModel = cameraViewModel
        self.permissionViewModel = permissionViewModel
        
        setupBindings()
        updateUIState()
    }
    
    // MARK: - Public Methods (User Actions)
    
    /// 사이드바 항목 선택 처리
    /// - Parameter item: 선택된 사이드바 항목
    func selectSidebarItem(_ item: SidebarItem) {
        selectedSidebarItem = item
    }
    
    /// 권한 설정 화면 표시
    func showPermissionSettings() {
        print("🔧 MainViewModel: showPermissionSettings() called")
        showingPermissionAlert = true
        print("🔧 MainViewModel: showingPermissionAlert set to \(showingPermissionAlert)")
    }
    
    /// 라이브 스트리밍 설정 화면 표시
    func showLiveStreamSettings() {
        print("📺 MainViewModel: showLiveStreamSettings() called")
        showingLiveStreamSettings = true
        print("📺 MainViewModel: showingLiveStreamSettings set to \(showingLiveStreamSettings)")
    }
    
    /// 카메라 목록 새로고침 실행
    /// 비동기적으로 카메라 목록을 새로고침하고 UI 상태를 업데이트합니다.
    func refreshCameraList() {
        print("🔄 MainViewModel: refreshCameraList() called")
        Task {
            print("🔄 MainViewModel: Starting refresh task")
            isRefreshing = true
            print("🔄 MainViewModel: isRefreshing set to \(isRefreshing)")
            await cameraViewModel.refreshCameraList()
            print("🔄 MainViewModel: Camera list refresh completed")
            isRefreshing = false
            print("🔄 MainViewModel: isRefreshing set to \(isRefreshing)")
        }
    }
    
    /// 카메라 선택 처리
    /// - Parameter camera: 선택할 카메라 디바이스
    func selectCamera(_ camera: CameraDevice) {
        cameraViewModel.switchToCamera(camera)
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
        if !permissionViewModel.areAllPermissionsGranted {
            currentUIState = .permissionRequired
        } else if cameraViewModel.selectedCamera == nil {
            currentUIState = .cameraNotSelected
        } else {
            currentUIState = .cameraActive
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
    case cameras = "카메라"
    case liveStream = "라이브 스트리밍"
    
    /// 로컬라이즈된 제목
    var title: String {
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