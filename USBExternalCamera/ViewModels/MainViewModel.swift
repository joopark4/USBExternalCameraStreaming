//
//  MainViewModel.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// 메인 화면의 ViewModel
/// MVVM 패턴에서 View와 Model 사이의 중간층 역할을 담당합니다.
/// UI 상태 관리, 사용자 상호작용 처리, 비즈니스 로직 조율을 담당합니다.
@MainActor
final class MainViewModel: ObservableObject {
    
    // MARK: - Published Properties (UI State)
    
    /// 현재 선택된 사이드바 항목
    /// 메인 화면의 상세 내용을 결정합니다.
    @Published var selectedSidebarItem: SidebarItem? = .cameras
    
    /// 권한 설정 시트 표시 여부
    @Published var showingPermissionAlert = false
    
    /// 라이브 스트리밍 설정 시트 표시 여부
    @Published var showingLiveStreamSettings = false
    
    /// 로깅 설정 시트 표시 여부 (개발용)
    @Published var showingLoggingSettings = false
    
    /// 새로고침 진행 상태
    @Published var isRefreshing = false
    
    /// 현재 권한 상태에 따른 UI 상태
    @Published var currentUIState: UIState = .loading
    
    /// 화면 캡처 스트리밍 상태
    @Published var isScreenCaptureStreaming: Bool = false
    
    // MARK: - Text Overlay Properties
    
    /// 텍스트 오버레이 표시 여부
    @Published var showTextOverlay: Bool = false
    
    /// 텍스트 오버레이 설정 팝업 표시 여부
    @Published var showingTextSettings: Bool = false
    
    /// 현재 텍스트 오버레이 설정
    @Published var textOverlaySettings: TextOverlaySettings = TextOverlaySettings()
    
    /// 텍스트 히스토리 목록
    @Published var textHistory: [TextHistoryItem] = []
    
    /// 현재 편집 중인 텍스트 설정 (임시)
    @Published var editingTextSettings: TextOverlaySettings = TextOverlaySettings()
    
    // MARK: - Dependencies
    
    let cameraViewModel: CameraViewModel
    let permissionViewModel: PermissionViewModel
    let liveStreamViewModel: LiveStreamViewModel
    
    // MARK: - Private Properties
    
    /// Combine 구독 관리
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(cameraViewModel: CameraViewModel, permissionViewModel: PermissionViewModel, liveStreamViewModel: LiveStreamViewModel) {
        self.cameraViewModel = cameraViewModel
        self.permissionViewModel = permissionViewModel
        self.liveStreamViewModel = liveStreamViewModel
        
        // CameraViewModel과 HaishinKitManager 연결 설정
        if let haishinKitManager = liveStreamViewModel.streamingService as? HaishinKitManager {
            cameraViewModel.connectToStreaming(haishinKitManager)
            logDebug("🔗 [MainViewModel] CameraViewModel과 HaishinKitManager 연결 완료", category: .ui)
        } else {
            logError("❌ [MainViewModel] HaishinKitManager 연결 실패", category: .ui)
        }
        
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
    func selectSidebarItem(_ item: SidebarItem?) {
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
    
    /// 화면 캡처 스트리밍 토글
    func toggleScreenCaptureStreaming() {
        logDebug("🎮 [MainViewModel] 화면 캡처 스트리밍 토글 요청", category: .ui)
        liveStreamViewModel.toggleScreenCaptureStreaming()
        logDebug("✅ [MainViewModel] 화면 캡처 스트리밍 토글 요청 완료", category: .ui)
    }
    
    // MARK: - Text Overlay Methods
    
    /// 텍스트 오버레이 표시/숨김 토글
    func toggleTextOverlay() {
        showTextOverlay.toggle()
        logDebug("📝 [MainViewModel] 텍스트 오버레이 토글: \(showTextOverlay)", category: .ui)
    }
    
    /// 텍스트 설정 팝업 표시
    func showTextSettings() {
        editingTextSettings = textOverlaySettings
        showingTextSettings = true
        logDebug("⚙️ [MainViewModel] 텍스트 설정 팝업 표시", category: .ui)
    }
    
    /// 텍스트 설정 적용
    func applyTextSettings() {
        // 텍스트가 비어있지 않은 경우 히스토리에 추가
        if !editingTextSettings.text.isEmpty {
            addToTextHistory(editingTextSettings.text)
        }
        
        textOverlaySettings = editingTextSettings
        showingTextSettings = false
        
        // 텍스트가 있으면 오버레이 표시
        if !textOverlaySettings.text.isEmpty {
            showTextOverlay = true
        }
        
        logDebug("✅ [MainViewModel] 텍스트 설정 적용: '\(textOverlaySettings.text)'", category: .ui)
    }
    
    /// 텍스트 설정 취소
    func cancelTextSettings() {
        showingTextSettings = false
        logDebug("❌ [MainViewModel] 텍스트 설정 취소", category: .ui)
    }
    
    /// 텍스트 히스토리에 추가
    private func addToTextHistory(_ text: String) {
        // 중복 제거
        textHistory.removeAll { $0.text == text }
        
        // 새 항목 추가
        textHistory.insert(TextHistoryItem(text: text), at: 0)
        
        // 최대 10개 유지
        if textHistory.count > 10 {
            textHistory = Array(textHistory.prefix(10))
        }
        
        logDebug("📚 [MainViewModel] 텍스트 히스토리 추가: '\(text)'", category: .ui)
    }
    
    /// 히스토리에서 텍스트 선택
    func selectTextFromHistory(_ historyItem: TextHistoryItem) {
        editingTextSettings.text = historyItem.text
        logDebug("📖 [MainViewModel] 히스토리에서 텍스트 선택: '\(historyItem.text)'", category: .ui)
    }
    
    /// 현재 사용 중인 텍스트 (HaishinKitManager에서 사용)
    var currentOverlayText: String {
        return textOverlaySettings.text
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
        
        // 스트리밍 상태 변화 감지 (화면 캡처 스트리밍 상태 업데이트용)
        /// 
        /// **화면 캡처 스트리밍 상태 동기화**
        /// LiveStreamViewModel의 스트리밍 상태가 변경될 때마다
        /// MainViewModel의 isScreenCaptureStreaming을 자동으로 업데이트합니다.
        ///
        /// **상태 매핑:**
        /// - .streaming: 화면 캡처 스트리밍 활성화 (true)
        /// - 기타 상태: 화면 캡처 스트리밍 비활성화 (false)
        ///
        /// **UI 반영:**
        /// 이 바인딩을 통해 사이드바의 "스트리밍 시작 - 캡처" 버튼이
        /// 실시간으로 상태에 맞게 업데이트됩니다.
        liveStreamViewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                // 스트리밍 상태에 따른 화면 캡처 상태 업데이트
                let newScreenCaptureState = (status == .streaming)
                
                // 상태가 실제로 변경된 경우에만 업데이트 (불필요한 UI 갱신 방지)
                if self?.isScreenCaptureStreaming != newScreenCaptureState {
                    self?.isScreenCaptureStreaming = newScreenCaptureState
                    
                    let statusText = newScreenCaptureState ? NSLocalizedString("activated", comment: "활성화") : NSLocalizedString("deactivated", comment: "비활성화")
                    logDebug("🔄 [MainViewModel] 화면 캡처 스트리밍 상태 \(statusText): \(status)", category: .ui)
                }
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
    
    var displayName: String {
        switch self {
        case .cameras:
            return NSLocalizedString("camera", comment: "카메라")
        }
    }
    
    /// 시스템 아이콘 이름
    var iconName: String {
        switch self {
        case .cameras:
            return "camera"
        }
    }
} 
