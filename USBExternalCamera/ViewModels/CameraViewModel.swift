import AVFoundation
import Combine
import Foundation
import SwiftUI
import LiveStreamingCore

/// 카메라 관련 기능을 관리하는 뷰모델
/// - @MainActor: UI 관련 작업은 메인 스레드에서 실행
/// - ObservableObject: SwiftUI 뷰와 데이터 바인딩을 위한 프로토콜
@MainActor
final class CameraViewModel: NSObject, ObservableObject {
    /// 연결된 외장 카메라 디바이스 목록
    /// - @Published: 변경 시 SwiftUI 뷰에 자동으로 알림
    /// - private(set): 외부에서 읽기만 가능하고 수정은 불가능
    @Published private(set) var externalCameras: [CameraDevice] = []
    
    /// 연결된 내장 카메라 디바이스 목록
    /// - @Published: 변경 시 SwiftUI 뷰에 자동으로 알림
    /// - private(set): 외부에서 읽기만 가능하고 수정은 불가능
    @Published private(set) var builtInCameras: [CameraDevice] = []
    
    /// 현재 선택된 카메라 디바이스
    /// - @Published: 변경 시 SwiftUI 뷰에 자동으로 알림
    /// - 선택된 카메라가 변경될 때마다 UI가 자동으로 업데이트
    @Published var selectedCamera: CameraDevice?
    
    /// 카메라 세션 매니저
    /// - 카메라 세션 관리 및 카메라 전환 처리
    private let sessionManager: CameraSessionManager
    
    /// 스트리밍 매니저 (카메라 프레임 수신용)
    private var streamingManager: HaishinKitManager?
    
    /// 카메라 세션 접근자
    /// - 현재 카메라 세션에 대한 읽기 전용 접근 제공
    var captureSession: AVCaptureSession {
        sessionManager.captureSession
    }

    /// 초기화
    /// - 카메라 세션 매니저 생성
    /// - 외장 카메라 검색
    /// - 첫 번째 카메라 자동 선택
    override init() {
        self.sessionManager = CameraSessionManager()
        super.init()
        
        logInfo("CameraViewModel initializing...", category: .camera)
        
        // 카메라 초기화 - 단순화된 접근법
        Task {
            logDebug("Starting camera initialization task...", category: .camera)
            
            // 전체 카메라 목록 검색
            await discoverCameras()
            
            // 첫 번째 사용 가능한 카메라 선택
            await MainActor.run {
                let allCameras = self.builtInCameras + self.externalCameras
                logInfo("Total cameras found: \(allCameras.count)", category: .camera)
                
                if let firstCamera = allCameras.first {
                    logInfo("Selecting first available camera: \(firstCamera.name)", category: .camera)
                    self.switchToCamera(firstCamera)
                } else {
                    logWarning("No cameras found!", category: .camera)
                }
            }
        }
        
        // 외장 카메라 연결 상태 모니터링
        setupDeviceNotifications()
        logInfo("CameraViewModel initialization completed", category: .camera)
    }

    /// 기본 카메라를 빠르게 가져오기 (성능 최적화)
    private func getDefaultCamera() async -> CameraDevice? {
        // 가장 일반적인 내장 카메라를 먼저 확인하여 빠른 초기화
        if let defaultDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return CameraDevice(device: defaultDevice)
        }
        return nil
    }

    /// 외장 카메라 연결 상태 모니터링 설정
    private func setupDeviceNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnected),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceDisconnected),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }
    
    /// 외장 카메라 연결 시 호출
    @objc private func handleDeviceConnected(_ notification: Notification) {
        Task {
            await discoverCameras()
        }
    }
    
    /// 외장 카메라 연결 해제 시 호출
    @objc private func handleDeviceDisconnected(_ notification: Notification) {
        Task {
            // 현재 선택된 카메라가 외장 카메라인지 확인
            if let selectedCamera = selectedCamera,
               externalCameras.contains(where: { $0.id == selectedCamera.id }) {
                // 외장 카메라가 연결 해제된 경우 기본 카메라로 전환
                await discoverCameras()
                if let firstBuiltInCamera = builtInCameras.first {
                    switchToCamera(firstBuiltInCamera)
                } else {
                    self.selectedCamera = nil
                }
            } else {
                // 선택된 카메라가 외장 카메라가 아닌 경우 목록만 업데이트
                await discoverCameras()
            }
        }
    }

    /// 카메라 디바이스 검색
    /// - AVCaptureDevice.DiscoverySession을 사용하여 외장 및 내장 카메라 검색
    /// - 검색된 카메라를 CameraDevice 모델로 변환하여 저장
    private func discoverCameras() async {
        logInfo("Starting camera discovery...", category: .camera)
        
        // 내장 카메라 검색
        let builtInDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        // 외장 카메라 검색
        let externalDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )

        let discoveredBuiltInDevices = builtInDiscoverySession.devices
        let discoveredExternalDevices = externalDiscoverySession.devices
        
        logInfo("Found \(discoveredBuiltInDevices.count) built-in cameras", category: .camera)
        logInfo("Found \(discoveredExternalDevices.count) external cameras", category: .camera)
        
        // 발견된 카메라들 로깅
        for (index, device) in discoveredBuiltInDevices.enumerated() {
            logInfo("Built-in camera \(index): \(device.localizedName) (ID: \(device.uniqueID))", category: .camera)
        }
        
        for (index, device) in discoveredExternalDevices.enumerated() {
            logInfo("External camera \(index): \(device.localizedName) (ID: \(device.uniqueID))", category: .camera)
        }

        // 메인 스레드에서 UI 업데이트
        await MainActor.run {
            let newBuiltInCameras = discoveredBuiltInDevices.map { CameraDevice(device: $0) }
            let newExternalCameras = discoveredExternalDevices.map { CameraDevice(device: $0) }
            
            logInfo("Updating camera lists...", category: .camera)
            logInfo("Previous built-in count: \(self.builtInCameras.count)", category: .camera)
            logInfo("Previous external count: \(self.externalCameras.count)", category: .camera)
            
            self.builtInCameras = newBuiltInCameras
            self.externalCameras = newExternalCameras
            
            logInfo("New built-in count: \(self.builtInCameras.count)", category: .camera)
            logInfo("New external count: \(self.externalCameras.count)", category: .camera)
            logInfo("Camera discovery completed", category: .camera)
        }
    }

    /// 선택된 카메라로 전환
    /// - sessionManager를 통해 카메라 전환 처리
    /// - 선택된 카메라 상태 업데이트
    /// - Parameter camera: 전환할 카메라 디바이스
    /// - Parameter skipSessionUpdate: 세션 업데이트를 건너뛸지 여부 (새로고침 시 사용)
    func switchToCamera(_ camera: CameraDevice, skipSessionUpdate: Bool = false) {
        logInfo("Switching to camera \(camera.name) (ID: \(camera.id))", category: .camera)
        logDebug("📹 CameraViewModel: Previous selected camera: \(selectedCamera?.name ?? "None") (ID: \(selectedCamera?.id ?? "None"))", category: .camera)
        logInfo("Skip session update: \(skipSessionUpdate)", category: .camera)
        
        // 이미 선택된 카메라인지 확인 - ID와 객체 모두 비교
        if let currentSelected = selectedCamera {
            if currentSelected.id == camera.id {
                logInfo("Camera \(camera.name) is already selected (same ID)", category: .camera)
                return
            }
            
            // 추가 안전 검사: 같은 디바이스인지 확인
            if currentSelected.device.uniqueID == camera.device.uniqueID {
                logInfo("Camera \(camera.name) is already selected (same device)", category: .camera)
                return
            }
        }
        
        logInfo("Proceeding with camera switch...", category: .camera)
        logInfo("- Target camera: \(camera.name)", category: .camera)
        logInfo("- Target ID: \(camera.id)", category: .camera)
        logInfo("- Target device type: \(camera.deviceType)", category: .camera)
        logInfo("- Target position: \(camera.position)", category: .camera)
        
        // 이전 선택 해제 로깅
        if let previousCamera = selectedCamera {
            logInfo("Deselecting previous camera: \(previousCamera.name) (ID: \(previousCamera.id))", category: .camera)
        }
        
        // @Published 속성 직접 업데이트 - SwiftUI가 자동으로 UI 업데이트
        selectedCamera = camera
        
        logDebug("📹 CameraViewModel: Selected camera updated to: \(selectedCamera?.name ?? "None")", category: .camera)
        logDebug("📹 CameraViewModel: Selected camera ID: \(selectedCamera?.id ?? "None")", category: .camera)
        
        // 세션 업데이트를 건너뛰지 않는 경우에만 세션 매니저를 통해 실제 카메라 전환 처리
        if !skipSessionUpdate {
            sessionManager.switchToCamera(camera)
            logInfo("Session manager updated for \(camera.name)", category: .camera)
        } else {
            logInfo("Skipped session update for \(camera.name) (maintaining current session)", category: .camera)
        }
        
        logInfo("Camera switch completed for \(camera.name)", category: .camera)

        // @Published 속성(selectedCamera)이 변경되면 자동으로 UI가 업데이트됩니다.
        // 수동 objectWillChange.send() 호출은 불필요하며 성능 저하를 유발할 수 있습니다.

        #if DEBUG
        // 선택 상태 검증 (디버그 모드에서만)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let currentSelected = self.selectedCamera {
                logDebug("[Verification] Currently selected: \(currentSelected.name) (ID: \(currentSelected.id))", category: .camera)
            }
        }
        #endif
    }

    /// 카메라 세션 중지
    /// - @MainActor: 메인 스레드에서 실행
    /// - sessionManager를 통해 세션 안전하게 중지
    @MainActor
    func stopSession() async {
        await sessionManager.stopSession()
    }
    
    /// 카메라 리스트 새로고침
    /// 현재 선택된 카메라를 유지하면서 카메라 목록만 갱신합니다.
    func refreshCameraList() async {
        logInfo("=== REFRESH CAMERA LIST START ===", category: .camera)
        
        // 현재 선택된 카메라 정보 저장 (더 상세한 정보 저장)
        let currentSelectedCamera = selectedCamera
        let currentSelectedId = currentSelectedCamera?.id
        let currentSelectedDeviceId = currentSelectedCamera?.device.uniqueID
        let currentSelectedName = currentSelectedCamera?.name
        
        logInfo("Current selected camera before refresh:", category: .camera)
        logDebug("📹 CameraViewModel: - Name: \(currentSelectedName ?? "None")", category: .camera)
        logDebug("📹 CameraViewModel: - ID: \(currentSelectedId ?? "None")", category: .camera)
        logDebug("📹 CameraViewModel: - Device ID: \(currentSelectedDeviceId ?? "None")", category: .camera)
        
        // 카메라 목록 새로고침
        await discoverCameras()
        logInfo("Camera discovery completed during refresh", category: .camera)
        
        // 현재 선택된 카메라를 새로운 목록에서 찾아서 유지
        if let selectedId = currentSelectedId, let selectedDeviceId = currentSelectedDeviceId {
            logInfo("Attempting to restore selected camera...", category: .camera)
            
            // 1차: ID로 정확히 매칭되는 카메라 찾기
            var restoredCamera: CameraDevice? = nil
            
            // 내장 카메라에서 찾기
            if let matchedCamera = builtInCameras.first(where: { $0.id == selectedId }) {
                restoredCamera = matchedCamera
                logInfo("Found matching built-in camera by ID: \(matchedCamera.name)", category: .camera)
            }
            // 외장 카메라에서 찾기
            else if let matchedCamera = externalCameras.first(where: { $0.id == selectedId }) {
                restoredCamera = matchedCamera
                logInfo("Found matching external camera by ID: \(matchedCamera.name)", category: .camera)
            }
            // 2차: Device uniqueID로 매칭 (ID 생성 방식이 변경된 경우 대비)
            else if let matchedCamera = builtInCameras.first(where: { $0.device.uniqueID == selectedDeviceId }) {
                restoredCamera = matchedCamera
                logInfo("Found matching built-in camera by device ID: \(matchedCamera.name)", category: .camera)
            }
            else if let matchedCamera = externalCameras.first(where: { $0.device.uniqueID == selectedDeviceId }) {
                restoredCamera = matchedCamera
                logInfo("Found matching external camera by device ID: \(matchedCamera.name)", category: .camera)
            }
            
            if let camera = restoredCamera {
                logInfo("Restoring selected camera: \(camera.name) (ID: \(camera.id))", category: .camera)

                // 세션을 중지하지 않고 선택된 카메라만 업데이트
                // @Published 속성 변경으로 UI가 자동 업데이트됨
                await MainActor.run {
                    self.selectedCamera = camera
                    logInfo("Selected camera restored successfully", category: .camera)
                }
            } else {
                logInfo("Could not find previously selected camera, selecting fallback", category: .camera)
                await selectFallbackCamera()
            }
        } else {
            logInfo("No previously selected camera, selecting default", category: .camera)
            await selectFallbackCamera()
        }
        
        logInfo("=== REFRESH CAMERA LIST END ===", category: .camera)
        logDebug("📹 CameraViewModel: Final selected camera: \(selectedCamera?.name ?? "None") (ID: \(selectedCamera?.id ?? "None"))", category: .camera)
    }
    
    /// 기본 카메라 선택 (이전 선택이 복원되지 않은 경우)
    private func selectFallbackCamera() async {
        await MainActor.run {
            if let firstBuiltInCamera = self.builtInCameras.first {
                logInfo("Selecting first built-in camera as fallback: \(firstBuiltInCamera.name)", category: .camera)
                // 새로고침 중에는 세션을 업데이트하지 않음
                self.switchToCamera(firstBuiltInCamera, skipSessionUpdate: true)
            } else if let firstExternalCamera = self.externalCameras.first {
                logInfo("Selecting first external camera as fallback: \(firstExternalCamera.name)", category: .camera)
                // 새로고침 중에는 세션을 업데이트하지 않음
                self.switchToCamera(firstExternalCamera, skipSessionUpdate: true)
            } else {
                logInfo("No cameras available, clearing selection", category: .camera)
                self.selectedCamera = nil
            }
        }
    }
    
    /// 카메라와 스트리밍 연결 설정 (화면 캡처용)
    /// - Parameters:
    ///   - streamingManager: 스트리밍 매니저 인스턴스
    func connectToStreaming(_ streamingManager: HaishinKitManager) {
        self.streamingManager = streamingManager
        sessionManager.frameDelegate = streamingManager
        // 화면 캡처 모드에서는 카메라 전환 델리게이트가 불필요
        logInfo("🔗 카메라와 스트리밍 매니저가 연결되었습니다 (프레임 델리게이트만)", category: .camera)
    }

    /// 스트리밍 시작 전 카메라 세션 하드웨어 최적화를 요청
    ///
    /// 화면 캡처/일반 스트리밍에서 선택된 해상도와 프레임률로
    /// 카메라 캡처 파라미터를 맞춰 블러/스케일/프레임 이슈를 줄입니다.
    func applyStreamingSettings(_ settings: LiveStreamSettings) {
        sessionManager.optimizeForStreamingSettings(settings)
    }
    
    /// 소멸자
    /// - 세션 정리는 명시적으로 호출해야 함
    /// - 비동기 작업이 포함되어 있어 deinit에서 직접 호출 불가
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 
