//
//  DetailView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import LiveStreamingCore
import Combine

// MARK: - Detail View Components

/// 상세 화면 View 컴포넌트
/// 선택된 사이드바 항목에 따라 적절한 콘텐츠를 표시하는 컴포넌트입니다.
struct DetailView: View {
  private let viewModel: MainViewModel
  @StateObject private var detailUIState: DetailUIState
  var onShowSidebar: () -> Void = {}
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  init(viewModel: MainViewModel, onShowSidebar: @escaping () -> Void = {}) {
    self.viewModel = viewModel
    self._detailUIState = StateObject(wrappedValue: DetailUIState(viewModel: viewModel))
    self.onShowSidebar = onShowSidebar
  }

  var body: some View {
    Group {
      switch detailUIState.selectedSidebarItem {
      case .cameras:
        // 카메라 상세 화면
        CameraDetailContentView(
          viewModel: viewModel,
          currentUIState: detailUIState.currentUIState
        )
      case .none:
        // 아무것도 선택되지 않은 상태
        VStack {
          Image(systemName: "sidebar.left")
            .font(.system(size: 50))
            .foregroundColor(.gray)
          Text(NSLocalizedString("select_menu_from_sidebar", comment: "사이드바에서 메뉴를 선택하세요"))
            .font(.title2)
            .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .toolbar {
      if horizontalSizeClass == .compact {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: onShowSidebar) {
            Image(systemName: "sidebar.left")
          }
          .accessibilityLabel(Text("메뉴 열기"))
        }
      }
    }
  }

}

/// 카메라 상세 콘텐츠 View 컴포넌트
/// 현재 UI 상태에 따라 적절한 카메라 관련 화면을 표시합니다.
struct CameraDetailContentView: View {
  let viewModel: MainViewModel
  let currentUIState: UIState

  var body: some View {
    switch currentUIState {
    case .loading:
      // 로딩 상태
      LoadingView()
    case .permissionRequired:
      // 카메라/마이크 권한 미허용 — 권한 안내 화면. 사용자가 안내 화면 안의 버튼을 눌러야만
      // 권한 시트가 열림 (자동으로 sheet 를 띄우지 않음).
      PermissionRequiredView(viewModel: viewModel)
    case .cameraNotSelected:
      // 카메라 미선택 상태
      CameraPlaceholderView(viewModel: viewModel)
    case .cameraActive:
      // 카메라 활성화 상태
      CameraPreviewContainerView(viewModel: viewModel)
    }
  }
}

/// 카메라 프리뷰 컨테이너 View 컴포넌트
/// 실제 카메라 화면과 YouTube Studio를 한 화면에 표시하는 컴포넌트입니다.
/// 16:9 비율로 제한하여 실제 송출되는 영역만 표시합니다.
/// 키보드가 올라와도 레이아웃이 변경되지 않습니다.
struct CameraPreviewContainerView: View {
  @ObservedObject private var cameraViewModel: CameraViewModel
  @StateObject private var liveStreamUIState: CameraPreviewLiveState
  @StateObject private var textOverlayUIState: CameraPreviewTextOverlayState
  @StateObject private var layoutState = CameraPreviewLayoutState()
  private let liveStreamViewModel: LiveStreamViewModel
  private let toggleScreenCaptureStreamingAction: () -> Void
  private let switchToNextCameraAction: () -> Void
  private let toggleTextOverlayAction: () -> Void
  private let showTextSettingsAction: () -> Void
  @State private var isAdvancedPanelExpanded = false

  init(viewModel: MainViewModel) {
    self._cameraViewModel = ObservedObject(wrappedValue: viewModel.cameraViewModel)
    self.liveStreamViewModel = viewModel.liveStreamViewModel
    self.toggleScreenCaptureStreamingAction = { viewModel.toggleScreenCaptureStreaming() }
    self.switchToNextCameraAction = { viewModel.switchToNextCamera() }
    self.toggleTextOverlayAction = { viewModel.toggleTextOverlay() }
    self.showTextSettingsAction = { viewModel.showTextSettings() }
    self._liveStreamUIState = StateObject(
      wrappedValue: CameraPreviewLiveState(viewModel: viewModel.liveStreamViewModel)
    )
    self._textOverlayUIState = StateObject(
      wrappedValue: CameraPreviewTextOverlayState(viewModel: viewModel)
    )
  }

  private var isFocusModeActive: Bool {
    liveStreamUIState.isScreenCaptureStreaming
  }

  private var streamLayoutProfile: StreamLayoutProfile {
    liveStreamUIState.settings.streamLayoutProfile
  }

  private var shouldShowAdvancedPanels: Bool {
    !isFocusModeActive || isAdvancedPanelExpanded
  }

  private var isActionLocked: Bool {
    liveStreamUIState.status == .connecting
      || liveStreamUIState.status == .disconnecting
      || liveStreamUIState.isLoading
  }

  private var selectedCameraTitle: String {
    cameraViewModel.selectedCamera?.name
      ?? NSLocalizedString("select_camera", comment: "카메라 선택")
  }

  private func isCompactDetailWidth(_ containerSize: CGSize) -> Bool {
    containerSize.width < 980
  }

  private func shouldShowTextControls(
    for containerSize: CGSize,
    isHorizontal: Bool
  ) -> Bool {
    guard shouldShowAdvancedPanels else { return false }
    // 수평 레이아웃에서는 메뉴 탭 열림 상태에서도 텍스트 컨트롤이 보이도록
    // 임계값을 낮추고, 레이아웃은 프리뷰 하단 배치로 처리합니다.
    return isHorizontal ? containerSize.width >= 980 : containerSize.width >= 320
  }

  private func verticalPreviewHeightRatio(
    for containerSize: CGSize
  ) -> CGFloat {
    if isCompactDetailWidth(containerSize) {
      return 0.66
    }
    return 0.58
  }

  private func horizontalPreviewTargetWidthRatio() -> CGFloat {
    0.58
  }

  private func widePreviewHeightRatio() -> CGFloat {
    switch liveStreamUIState.settings.streamOrientation {
    case .landscape:
      return 0.84
    case .portrait:
      return 0.84
    }
  }

  private func defaultIsWideScreen(for containerSize: CGSize) -> Bool {
    containerSize.width >= containerSize.height
  }

  private func defaultShowsSupplementaryInfo(for containerSize: CGSize) -> Bool {
    shouldShowAdvancedPanels && defaultIsWideScreen(for: containerSize)
  }

  var body: some View {
    VStack(spacing: 10) {
      focusModeControlBar

      GeometryReader { geometry in
        let containerSize = geometry.size
        let fallbackIsWideScreen = defaultIsWideScreen(for: containerSize)
        let isWideScreen = layoutState.hasResolvedLayout
          ? layoutState.isWideScreen
          : fallbackIsWideScreen
        let showsSupplementaryInfo = layoutState.hasResolvedLayout
          ? layoutState.showsSupplementaryInfo
          : defaultShowsSupplementaryInfo(for: containerSize)

        let rootLayout = isWideScreen
          ? AnyLayout(HStackLayout(spacing: 8))
          : AnyLayout(VStackLayout(spacing: 7))

        rootLayout {
          previewColumn(
            containerSize: containerSize,
            isWideScreen: isWideScreen
          )

          studioSection(
            containerSize: containerSize,
            isWideScreen: isWideScreen,
            showsSupplementaryInfo: showsSupplementaryInfo
          )
        }
        .onAppear {
          layoutState.scheduleUpdate(
            for: containerSize,
            shouldShowAdvancedPanels: shouldShowAdvancedPanels,
            force: true
          )
        }
        .onChange(of: containerSize) { _, newSize in
          layoutState.scheduleUpdate(
            for: newSize,
            shouldShowAdvancedPanels: shouldShowAdvancedPanels
          )
        }
        .onChange(of: shouldShowAdvancedPanels) { _, newValue in
          layoutState.scheduleUpdate(
            for: containerSize,
            shouldShowAdvancedPanels: newValue,
            force: true
          )
        }
      }
    }
    .padding(.horizontal, 12)  // 좌우 패딩은 12픽셀 유지
    .padding(.bottom, 12)  // 하단 패딩은 12픽셀 유지
    .background(Color.black.opacity(0.1))
    .ignoresSafeArea(.keyboard)  // 키보드로 인한 레이아웃 변경 방지
    .ignoresSafeArea(.container, edges: [])  // safe area 무시 제거
    .onTapGesture {
      // 뷰를 탭하면 키보드 숨김
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    .onChange(of: liveStreamUIState.status) { oldStatus, newStatus in
      if newStatus == .streaming, oldStatus != .streaming {
        withAnimation(.easeInOut(duration: 0.2)) {
          isAdvancedPanelExpanded = false
        }
      } else if newStatus == .idle && oldStatus == .disconnecting {
        isAdvancedPanelExpanded = false
      } else if case .error = newStatus {
        isAdvancedPanelExpanded = false
      }
    }
  }

  // MARK: - Layout Methods

  @ViewBuilder
  private var focusModeControlBar: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        Button {
          toggleScreenCaptureStreamingAction()
        } label: {
          Label(
            liveStreamUIState.streamingButtonText,
            systemImage: liveStreamUIState.isScreenCaptureStreaming
              ? "stop.fill" : "play.fill"
          )
          .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(FocusActionButtonStyle(tint: liveStreamUIState.isScreenCaptureStreaming ? .red : .blue))
        .disabled(isActionLocked || !liveStreamUIState.isScreenCaptureButtonEnabled)

        Button {
          switchToNextCameraAction()
        } label: {
          Label(selectedCameraTitle, systemImage: "arrow.triangle.2.circlepath.camera")
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(FocusActionButtonStyle(tint: .indigo))
        .disabled(
          isActionLocked
            || (cameraViewModel.builtInCameras + cameraViewModel.externalCameras).count <= 1
        )
      }

      HStack(spacing: 8) {
        FocusMetricChip(
          title: NSLocalizedString("status", comment: "상태"),
          value: liveStreamUIState.status.description,
          icon: "dot.radiowaves.left.and.right",
          tint: isFocusModeActive ? .red : .gray
        )
        .frame(maxWidth: .infinity)

        Button {
          liveStreamViewModel.toggleMicrophoneMute()
        } label: {
          Label(
            liveStreamUIState.isMicrophoneMuted
              ? NSLocalizedString("microphone_unmute", comment: "마이크 음소거 해제")
              : NSLocalizedString("microphone_mute", comment: "마이크 음소거"),
            systemImage: liveStreamUIState.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill"
          )
          .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(
          FocusActionButtonStyle(
            tint: liveStreamUIState.isMicrophoneMuted ? .orange : .teal))
        .disabled(
          liveStreamUIState.status == .connecting
            || liveStreamUIState.status == .disconnecting
        )

        FocusMetricChip(
          title: NSLocalizedString("video_bitrate", comment: "비디오 비트레이트"),
          value: "\(liveStreamUIState.settings.videoBitrate) kbps",
          icon: "speedometer",
          tint: .blue
        )
        .frame(maxWidth: .infinity)
      }

      if isFocusModeActive {
        HStack {
          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              isAdvancedPanelExpanded.toggle()
            }
          } label: {
            Label(
              NSLocalizedString("advanced_settings", comment: "고급 설정"),
              systemImage: isAdvancedPanelExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill"
            )
            .font(.subheadline.weight(.semibold))
          }
          .buttonStyle(.plain)
          .foregroundColor(.secondary)

          Spacer()
        }
      }
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(Color(UIColor.secondarySystemBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
    )
  }

  @ViewBuilder
  private func previewColumn(
    containerSize: CGSize,
    isWideScreen: Bool
  ) -> some View {
    let showsTextControls = shouldShowTextControls(
      for: containerSize,
      isHorizontal: isWideScreen
    )

    if isWideScreen {
      let previewAvailableHeight = max(1, containerSize.height * widePreviewHeightRatio())
      let previewSlotWidth = containerSize.width * horizontalPreviewTargetWidthRatio()

      VStack(spacing: 8) {
        cameraPreviewSection(
          availableSize: CGSize(
            width: previewSlotWidth,
            height: previewAvailableHeight
          )
        )

        if showsTextControls {
          TextOverlayControlView(
            isTextOverlayVisible: textOverlayUIState.showTextOverlay,
            onToggleTextOverlay: toggleTextOverlayAction,
            onShowTextSettings: showTextSettingsAction
          )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
      .frame(width: previewSlotWidth, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)
    } else {
      let previewHeightRatio = verticalPreviewHeightRatio(for: containerSize)
      let previewAvailableHeight = max(
        120,
        containerSize.height * previewHeightRatio
      )

      VStack(alignment: .trailing, spacing: 8) {
        cameraPreviewSection(
          availableSize: CGSize(
            width: containerSize.width - 12,
            height: previewAvailableHeight
          )
        )

        if showsTextControls {
          TextOverlayControlView(
            isTextOverlayVisible: textOverlayUIState.showTextOverlay,
            onToggleTextOverlay: toggleTextOverlayAction,
            onShowTextSettings: showTextSettingsAction
          )
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
      .layoutPriority(0)
    }
  }

  @ViewBuilder
  private func studioSection(
    containerSize: CGSize,
    isWideScreen: Bool,
    showsSupplementaryInfo: Bool
  ) -> some View {
    YouTubeStudioAccessView(
      streamingStatusDescription: liveStreamUIState.status.description,
      isStreaming: liveStreamUIState.status == .streaming,
      isValidStreamKey: liveStreamUIState.isValidStreamKey,
      showsSupplementaryInfo: showsSupplementaryInfo
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .layoutPriority(isWideScreen ? 0 : 1)
  }

  @ViewBuilder
  private func cameraPreviewSection(availableSize: CGSize) -> some View {
    let liveStreamSettings = liveStreamUIState.settings
    let aspectRatio = streamLayoutProfile.aspectRatio
    let audioMeterHeight: CGFloat = 40
    let maxWidth = availableSize.width
    let maxHeight = max(120, availableSize.height - audioMeterHeight)  // 하단 오디오 피크 영역 확보

    // Aspect Fit 방식으로 16:9 프레임 계산
    let previewSize: CGSize = {
      if maxWidth / maxHeight > aspectRatio {
        // 세로가 기준: 높이에 맞춰서 너비 계산
        let width = maxHeight * aspectRatio
        return CGSize(width: width, height: maxHeight)
      } else {
        // 가로가 기준: 너비에 맞춰서 높이 계산
        let height = maxWidth / aspectRatio
        return CGSize(width: maxWidth, height: height)
      }
    }()
    VStack(spacing: 6) {
      // 16:9 프리뷰 영역 (프리뷰 정보 텍스트 제거하여 간격 최소화)
      ZStack {
        // 카메라 프리뷰
        CameraPreviewView(
          session: cameraViewModel.captureSession,
          cameraViewModel: cameraViewModel,
          streamingSettings: liveStreamSettings,
          haishinKitManager: liveStreamViewModel.streamingService as? HaishinKitManager,
          showTextOverlay: textOverlayUIState.showTextOverlay,
          overlayText: textOverlayUIState.currentOverlayText
        )
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(width: previewSize.width, height: previewSize.height)
        .background(Color.black)
        .cornerRadius(8)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
          // HaishinKitManager에 텍스트 오버레이 정보 전달
          if let haishinKitManager = liveStreamViewModel.streamingService
            as? HaishinKitManager
          {
            haishinKitManager.updateTextOverlay(
              show: textOverlayUIState.showTextOverlay,
              settings: textOverlayUIState.settings
            )
          }
        }
        .onChange(of: textOverlayUIState.settings) { _, newSettings in
          // 텍스트 설정 변경 시 HaishinKitManager 업데이트
          if let haishinKitManager = liveStreamViewModel.streamingService
            as? HaishinKitManager
          {
            haishinKitManager.updateTextOverlay(
              show: textOverlayUIState.showTextOverlay,
              settings: newSettings
            )
          }
        }
        .onChange(of: textOverlayUIState.showTextOverlay) { _, newValue in
          // 텍스트 표시 상태 변경 시 HaishinKitManager 업데이트
          if let haishinKitManager = liveStreamViewModel.streamingService
            as? HaishinKitManager
          {
            haishinKitManager.updateTextOverlay(
              show: newValue,
              settings: textOverlayUIState.settings
            )
          }
        }

        // 텍스트 오버레이
        if textOverlayUIState.showTextOverlay {
          TextOverlayDisplayView(
            settings: textOverlayUIState.settings,
            previewSize: previewSize
          )
        }

        // 16:9 경계선 표시 (선택적으로 표시)
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.clear)
          .stroke(Color.red.opacity(0.3), lineWidth: 1)
          .frame(width: previewSize.width, height: previewSize.height)
      }

      AudioPeakMeterView(
        viewModel: liveStreamViewModel
      )
      .frame(width: previewSize.width)
    }
    .frame(width: availableSize.width, height: availableSize.height, alignment: .top)
  }

}

@MainActor
private final class CameraPreviewLiveState: ObservableObject {
  @Published private var snapshot: CameraPreviewLiveSnapshot

  private let viewModel: LiveStreamViewModel
  private var cancellables = Set<AnyCancellable>()

  init(viewModel: LiveStreamViewModel) {
    self.viewModel = viewModel
    self.snapshot = CameraPreviewLiveSnapshot(
      settings: viewModel.settings,
      status: viewModel.status,
      isLoading: viewModel.isLoading,
      isMicrophoneMuted: viewModel.isMicrophoneMuted,
      isScreenCaptureStreaming: viewModel.isScreenCaptureStreaming,
      streamingButtonText: viewModel.streamingButtonText,
      isScreenCaptureButtonEnabled: viewModel.isScreenCaptureButtonEnabled,
      isValidStreamKey: Self.makeIsValidStreamKey(from: viewModel.settings)
    )

    bind()
  }

  var settings: LiveStreamSettings { snapshot.settings }
  var status: LiveStreamStatus { snapshot.status }
  var isLoading: Bool { snapshot.isLoading }
  var isMicrophoneMuted: Bool { snapshot.isMicrophoneMuted }
  var isScreenCaptureStreaming: Bool { snapshot.isScreenCaptureStreaming }
  var streamingButtonText: String { snapshot.streamingButtonText }
  var isScreenCaptureButtonEnabled: Bool { snapshot.isScreenCaptureButtonEnabled }
  var isValidStreamKey: Bool { snapshot.isValidStreamKey }

  private func bind() {
    viewModel.$settings
      .removeDuplicates(by: { lhs, rhs in
        lhs.videoWidth == rhs.videoWidth
          && lhs.videoHeight == rhs.videoHeight
          && lhs.videoBitrate == rhs.videoBitrate
          && lhs.frameRate == rhs.frameRate
          && lhs.streamOrientation == rhs.streamOrientation
          && lhs.streamKey == rhs.streamKey
      })
      .sink { [weak self] settings in
        self?.updateSnapshot { snapshot in
          snapshot.settings = settings
          snapshot.isValidStreamKey = Self.makeIsValidStreamKey(from: settings)
          Self.applyDerivedStreamingState(from: self?.viewModel, to: &snapshot)
        }
      }
      .store(in: &cancellables)

    viewModel.$status
      .removeDuplicates()
      .sink { [weak self] status in
        self?.updateSnapshot { snapshot in
          snapshot.status = status
          Self.applyDerivedStreamingState(from: self?.viewModel, to: &snapshot)
        }
      }
      .store(in: &cancellables)

    viewModel.$isLoading
      .removeDuplicates()
      .sink { [weak self] isLoading in
        self?.updateSnapshot { snapshot in
          snapshot.isLoading = isLoading
          Self.applyDerivedStreamingState(from: self?.viewModel, to: &snapshot)
        }
      }
      .store(in: &cancellables)

    viewModel.$isMicrophoneMuted
      .removeDuplicates()
      .sink { [weak self] isMuted in
        self?.updateSnapshot { snapshot in
          snapshot.isMicrophoneMuted = isMuted
        }
      }
      .store(in: &cancellables)

    viewModel.$canStartStreaming
      .removeDuplicates()
      .sink { [weak self] _ in
        self?.updateSnapshot { snapshot in
          Self.applyDerivedStreamingState(from: self?.viewModel, to: &snapshot)
        }
      }
      .store(in: &cancellables)
  }

  private func updateSnapshot(_ mutate: (inout CameraPreviewLiveSnapshot) -> Void) {
    var updatedSnapshot = snapshot
    mutate(&updatedSnapshot)
    guard updatedSnapshot != snapshot else { return }
    snapshot = updatedSnapshot
  }

  private static func applyDerivedStreamingState(
    from viewModel: LiveStreamViewModel?,
    to snapshot: inout CameraPreviewLiveSnapshot
  ) {
    guard let viewModel else { return }
    snapshot.isScreenCaptureStreaming = viewModel.isScreenCaptureStreaming
    snapshot.streamingButtonText = viewModel.streamingButtonText
    snapshot.isScreenCaptureButtonEnabled = viewModel.isScreenCaptureButtonEnabled
  }

  private static func makeIsValidStreamKey(from settings: LiveStreamSettings) -> Bool {
    !settings.streamKey.isEmpty && settings.streamKey != "YOUR_YOUTUBE_STREAM_KEY_HERE"
  }
}

@MainActor
private final class CameraPreviewTextOverlayState: ObservableObject {
  @Published private var snapshot: CameraPreviewTextOverlaySnapshot

  private var cancellables = Set<AnyCancellable>()

  init(viewModel: MainViewModel) {
    self.snapshot = CameraPreviewTextOverlaySnapshot(
      showTextOverlay: viewModel.showTextOverlay,
      settings: viewModel.textOverlaySettings
    )

    viewModel.$showTextOverlay
      .combineLatest(viewModel.$textOverlaySettings)
      .map { showTextOverlay, settings in
        CameraPreviewTextOverlaySnapshot(
          showTextOverlay: showTextOverlay,
          settings: settings
        )
      }
      .removeDuplicates()
      .sink { [weak self] snapshot in
        self?.snapshot = snapshot
      }
      .store(in: &cancellables)
  }

  var showTextOverlay: Bool { snapshot.showTextOverlay }
  var settings: TextOverlaySettings { snapshot.settings }
  var currentOverlayText: String { snapshot.settings.text }
}

@MainActor
private final class DetailUIState: ObservableObject {
  @Published private(set) var selectedSidebarItem: SidebarItem?
  @Published private(set) var currentUIState: UIState

  private var cancellables = Set<AnyCancellable>()

  init(viewModel: MainViewModel) {
    self.selectedSidebarItem = viewModel.selectedSidebarItem
    self.currentUIState = viewModel.currentUIState

    viewModel.$selectedSidebarItem
      .removeDuplicates()
      .sink { [weak self] selectedSidebarItem in
        self?.selectedSidebarItem = selectedSidebarItem
      }
      .store(in: &cancellables)

    viewModel.$currentUIState
      .removeDuplicates()
      .sink { [weak self] currentUIState in
        self?.currentUIState = currentUIState
      }
      .store(in: &cancellables)
  }
}

private struct CameraPreviewLiveSnapshot: Equatable {
  var settings: LiveStreamSettings
  var status: LiveStreamStatus
  var isLoading: Bool
  var isMicrophoneMuted: Bool
  var isScreenCaptureStreaming: Bool
  var streamingButtonText: String
  var isScreenCaptureButtonEnabled: Bool
  var isValidStreamKey: Bool

  static func == (lhs: CameraPreviewLiveSnapshot, rhs: CameraPreviewLiveSnapshot) -> Bool {
    lhs.status == rhs.status
      && lhs.isLoading == rhs.isLoading
      && lhs.isMicrophoneMuted == rhs.isMicrophoneMuted
      && lhs.isScreenCaptureStreaming == rhs.isScreenCaptureStreaming
      && lhs.streamingButtonText == rhs.streamingButtonText
      && lhs.isScreenCaptureButtonEnabled == rhs.isScreenCaptureButtonEnabled
      && lhs.isValidStreamKey == rhs.isValidStreamKey
      && lhs.settings.videoWidth == rhs.settings.videoWidth
      && lhs.settings.videoHeight == rhs.settings.videoHeight
      && lhs.settings.videoBitrate == rhs.settings.videoBitrate
      && lhs.settings.frameRate == rhs.settings.frameRate
      && lhs.settings.streamOrientation == rhs.settings.streamOrientation
      && lhs.settings.streamKey == rhs.settings.streamKey
  }
}

private struct CameraPreviewTextOverlaySnapshot: Equatable {
  var showTextOverlay: Bool
  var settings: TextOverlaySettings
}

@MainActor
private final class CameraPreviewLayoutState: ObservableObject {
  @Published private(set) var hasResolvedLayout = false
  @Published private(set) var isWideScreen = false
  @Published private(set) var showsSupplementaryInfo = true

  private var pendingUpdate: DispatchWorkItem?
  private let debounceInterval: TimeInterval = 0.04

  deinit {
    pendingUpdate?.cancel()
  }

  func scheduleUpdate(
    for containerSize: CGSize,
    shouldShowAdvancedPanels: Bool,
    force: Bool = false
  ) {
    pendingUpdate?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      self?.applyResolvedLayout(
        for: containerSize,
        shouldShowAdvancedPanels: shouldShowAdvancedPanels
      )
    }

    pendingUpdate = workItem
    let delay = force ? 0 : debounceInterval
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func applyResolvedLayout(
    for containerSize: CGSize,
    shouldShowAdvancedPanels: Bool
  ) {
    let resolvedIsWideScreen = makeResolvedWideScreenValue(for: containerSize)
    let resolvedShowsSupplementaryInfo = shouldShowAdvancedPanels && resolvedIsWideScreen

    let layoutChanged =
      !hasResolvedLayout
      || isWideScreen != resolvedIsWideScreen
      || showsSupplementaryInfo != resolvedShowsSupplementaryInfo

    hasResolvedLayout = true
    guard layoutChanged else { return }

    isWideScreen = resolvedIsWideScreen
    showsSupplementaryInfo = resolvedShowsSupplementaryInfo
  }

  private func makeResolvedWideScreenValue(for containerSize: CGSize) -> Bool {
    let aspectRatio = containerSize.width / max(containerSize.height, 1)
    let aspectThreshold: CGFloat = 1.0
    let aspectHysteresis: CGFloat = 0.04

    if !hasResolvedLayout {
      return aspectRatio >= aspectThreshold
    }

    if isWideScreen {
      return aspectRatio >= (aspectThreshold - aspectHysteresis)
    }

    return aspectRatio >= (aspectThreshold + aspectHysteresis)
  }
}

private struct AudioPeakMeterView: View {
  @ObservedObject var viewModel: LiveStreamViewModel

  var body: some View {
    AudioPeakMeterContentView(
      level: viewModel.microphonePeakLevel,
      decibels: viewModel.microphonePeakDecibels,
      isMuted: viewModel.isMicrophoneMuted,
      isStreaming: viewModel.status == .streaming,
      diagnosticMessage: viewModel.audioPeakDiagnosticMessage,
      inputSummary: viewModel.activeMicrophoneDisplaySummary
    )
  }
}

private struct FocusActionButtonStyle: ButtonStyle {
  let tint: Color
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline.weight(.semibold))
      .foregroundColor(.white)
      .padding(.horizontal, 12)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(backgroundColor(isPressed: configuration.isPressed))
      )
      .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }

  private func backgroundColor(isPressed: Bool) -> Color {
    guard isEnabled else { return .gray.opacity(0.45) }
    return isPressed ? tint.opacity(0.82) : tint
  }
}

private struct FocusMetricChip: View {
  let title: String
  let value: String
  let icon: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(.caption2.weight(.bold))
          .foregroundColor(tint)
        Text(title)
          .font(.caption2)
          .foregroundColor(.secondary)
          .lineLimit(1)
      }

      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundColor(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color(UIColor.tertiarySystemBackground))
    )
  }
}

/// 권한 시트로 진입하는 공통 버튼 — `CameraPlaceholderView` / `PermissionRequiredView`
/// 양쪽에서 동일하게 사용. 두 곳의 라벨/스타일이 항상 같이 변경되도록 한 곳으로 묶어둡니다.
private struct PermissionSettingsButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(
        NSLocalizedString("go_to_permission_settings", comment: "권한 설정"),
        systemImage: "lock.shield"
      )
      .font(.headline)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .buttonStyle(.borderedProminent)
    .tint(.blue)
  }
}

/// 카메라 플레이스홀더 View 컴포넌트.
/// 카메라가 선택되지 않은 상태에서 노출되는 안내 화면입니다. 권한 진입 버튼을 함께 둬서
/// 사이드바 gear 외에도 디테일뷰 안에서 바로 권한 설정에 들어갈 수 있게 합니다.
struct CameraPlaceholderView: View {
  let viewModel: MainViewModel

  var body: some View {
    Color.black
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay {
        VStack(spacing: 20) {
          Image(systemName: "camera")
            .font(.system(size: 50))
            .foregroundColor(.gray)
          Text(NSLocalizedString("select_camera", comment: "카메라 선택"))
            .font(.title2)
            .foregroundColor(.gray)

          PermissionSettingsButton {
            viewModel.showPermissionSettings()
          }
        }
        .padding()
      }
  }
}

/// 권한 필요 안내 View 컴포넌트.
/// 카메라/마이크 권한이 모두 허용되지 않았을 때 디테일뷰가 노출하는 안내 화면입니다.
/// 권한 시트를 자동으로 띄우지 않으며, 사용자가 본 화면의 버튼을 눌러야만 시트가 열립니다.
struct PermissionRequiredView: View {
  @ObservedObject var viewModel: MainViewModel

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 50))
        .foregroundColor(.orange)

      Text(NSLocalizedString("permission_settings_needed", comment: "권한 설정 필요"))
        .font(.title2)
        .bold()

      Text(viewModel.permissionViewModel.permissionGuideMessage)
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)
        .padding(.horizontal)

      PermissionSettingsButton {
        viewModel.showPermissionSettings()
      }
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

// YouTube Studio 접근 뷰는 별도 파일로 모듈화됨:
// - YouTubeStudioAccessView.swift 참조
