//
//  DetailView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import LiveStreamingCore

// MARK: - Detail View Components

/// 상세 화면 View 컴포넌트
/// 선택된 사이드바 항목에 따라 적절한 콘텐츠를 표시하는 컴포넌트입니다.
struct DetailView: View {
  @ObservedObject var viewModel: MainViewModel
  var onShowSidebar: () -> Void = {}
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    Group {
      switch viewModel.selectedSidebarItem {
      case .cameras:
        // 카메라 상세 화면
        CameraDetailContentView(viewModel: viewModel)
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
/// 실제 카메라 화면과 YouTube Studio를 한 화면에 표시하는 컴포넌트입니다.
/// 16:9 비율로 제한하여 실제 송출되는 영역만 표시합니다.
/// 키보드가 올라와도 레이아웃이 변경되지 않습니다.
struct CameraPreviewContainerView: View {
  @ObservedObject var viewModel: MainViewModel
  @State private var isAdvancedPanelExpanded = false

  private var isFocusModeActive: Bool {
    viewModel.liveStreamViewModel.isScreenCaptureStreaming
  }

  private var shouldShowAdvancedPanels: Bool {
    !isFocusModeActive || isAdvancedPanelExpanded
  }

  private var isActionLocked: Bool {
    viewModel.liveStreamViewModel.status == .connecting
      || viewModel.liveStreamViewModel.status == .disconnecting
      || viewModel.liveStreamViewModel.isLoading
  }

  private var selectedCameraTitle: String {
    viewModel.cameraViewModel.selectedCamera?.name
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
    for containerSize: CGSize,
    showsTextControls: Bool
  ) -> CGFloat {
    if isCompactDetailWidth(containerSize) {
      return showsTextControls ? 0.40 : 0.46
    }
    return showsTextControls ? 0.34 : 0.40
  }

  var body: some View {
    VStack(spacing: 10) {
      focusModeControlBar

      GeometryReader { geometry in
        let containerSize = geometry.size
        let isWideScreen = containerSize.width >= 980
          && containerSize.width > containerSize.height * 1.15  // 가로가 긴 화면 판단

        if isWideScreen {
          // 가로로 긴 화면 (iPad, Mac): 수평 분할
          horizontalLayout(containerSize: containerSize)
        } else {
          // 세로로 긴 화면 (iPhone): 수직 분할
          verticalLayout(containerSize: containerSize)
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
    .onChange(of: viewModel.liveStreamViewModel.status) { oldStatus, newStatus in
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
          viewModel.toggleScreenCaptureStreaming()
        } label: {
          Label(
            viewModel.liveStreamViewModel.streamingButtonText,
            systemImage: viewModel.liveStreamViewModel.isScreenCaptureStreaming
              ? "stop.fill" : "play.fill"
          )
          .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(FocusActionButtonStyle(tint: viewModel.liveStreamViewModel.isScreenCaptureStreaming ? .red : .blue))
        .disabled(isActionLocked || !viewModel.liveStreamViewModel.isScreenCaptureButtonEnabled)

        Button {
          viewModel.switchToNextCamera()
        } label: {
          Label(selectedCameraTitle, systemImage: "arrow.triangle.2.circlepath.camera")
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(FocusActionButtonStyle(tint: .indigo))
        .disabled(isActionLocked || !viewModel.canSwitchCameraQuickly)
      }

      HStack(spacing: 8) {
        FocusMetricChip(
          title: NSLocalizedString("status", comment: "상태"),
          value: viewModel.liveStreamViewModel.status.description,
          icon: "dot.radiowaves.left.and.right",
          tint: isFocusModeActive ? .red : .gray
        )
        .frame(maxWidth: .infinity)

        Button {
          // 음소거 기능 안정화 전까지 비활성화
        } label: {
          Label(
            viewModel.liveStreamViewModel.isMicrophoneMuted
              ? NSLocalizedString("microphone_unmute", comment: "마이크 음소거 해제")
              : NSLocalizedString("microphone_mute", comment: "마이크 음소거"),
            systemImage: viewModel.liveStreamViewModel.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill"
          )
          .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(
          FocusActionButtonStyle(
            tint: viewModel.liveStreamViewModel.isMicrophoneMuted ? .orange : .teal))
        .disabled(true)

        FocusMetricChip(
          title: NSLocalizedString("video_bitrate", comment: "비디오 비트레이트"),
          value: "\(viewModel.liveStreamViewModel.settings.videoBitrate) kbps",
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
  private func horizontalLayout(containerSize: CGSize) -> some View {
    let showsTextControls = shouldShowTextControls(for: containerSize, isHorizontal: true)
    let previewAspect: CGFloat = 16.0 / 9.0
    let controlsReservedHeight: CGFloat = showsTextControls ? 136 : 0
    let previewAvailableHeight = max(1, containerSize.height - 40 - controlsReservedHeight)
    let previewMaxWidthByHeight = previewAvailableHeight * previewAspect
    let targetLeftWidth = showsTextControls ? containerSize.width * 0.64 : containerSize.width * 0.72
    let previewWidth = min(targetLeftWidth, previewMaxWidthByHeight)
    let leftColumnWidth = previewWidth
    let columnSpacing: CGFloat = 8

    HStack(spacing: columnSpacing) {
      // 왼쪽: 카메라 프리뷰 + 텍스트 컨트롤 영역
      VStack(spacing: 8) {
        // 카메라 프리뷰
        cameraPreviewSection(
          availableSize: CGSize(
            width: previewWidth,
            height: previewAvailableHeight
          )
        )

        if showsTextControls {
          // 메뉴 접힘 상태에서도 프리뷰를 가리지 않도록 하단에 배치
          TextOverlayControlView(viewModel: viewModel)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
      .frame(width: leftColumnWidth, alignment: .leading)
      .frame(maxHeight: .infinity, alignment: .topLeading)

      // 오른쪽: YouTube Studio 영역 (더 크게)
      VStack(spacing: 0) {
        YouTubeStudioAccessView(
          viewModel: viewModel,
          showsSupplementaryInfo: shouldShowAdvancedPanels && !isCompactDetailWidth(containerSize)
        )
          .frame(maxHeight: .infinity)
      }
      .frame(maxWidth: .infinity)
    }
  }

  @ViewBuilder
  private func verticalLayout(containerSize: CGSize) -> some View {
    let showsTextControls = shouldShowTextControls(for: containerSize, isHorizontal: false)
    let previewHeightRatio = verticalPreviewHeightRatio(
      for: containerSize,
      showsTextControls: showsTextControls
    )
    let controlsReservedHeight: CGFloat = showsTextControls ? 136 : 0
    let previewAvailableHeight = max(120, containerSize.height * previewHeightRatio - controlsReservedHeight)

    VStack(spacing: 7) {  // 간격을 4에서 7픽셀로 조정
      // 위쪽: 카메라 프리뷰 + 텍스트 컨트롤 영역 (iPhone 포함 하단 배치)
      VStack(alignment: .trailing, spacing: 8) {
        cameraPreviewSection(
          availableSize: CGSize(
            width: containerSize.width - 12,
            height: previewAvailableHeight
          )
        )

        if showsTextControls {
          TextOverlayControlView(viewModel: viewModel)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
      .layoutPriority(0)  // 낮은 우선순위로 설정

      // 아래쪽: YouTube Studio 영역 (남은 공간 모두 차지)
      YouTubeStudioAccessView(
        viewModel: viewModel,
        showsSupplementaryInfo: shouldShowAdvancedPanels && !isCompactDetailWidth(containerSize)
      )
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // 남은 공간 모두 차지
        .layoutPriority(1)  // 높은 우선순위로 확장
    }
  }

  @ViewBuilder
  private func cameraPreviewSection(availableSize: CGSize) -> some View {
    // 16:9 비율 계산 (유튜브 라이브 표준)
    let aspectRatio: CGFloat = 16.0 / 9.0
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
          session: viewModel.cameraViewModel.captureSession,
          cameraViewModel: viewModel.cameraViewModel,
          streamViewModel: viewModel.liveStreamViewModel,
          haishinKitManager: viewModel.liveStreamViewModel.streamingService as? HaishinKitManager,
          showTextOverlay: viewModel.showTextOverlay,
          overlayText: viewModel.currentOverlayText
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
          if let haishinKitManager = viewModel.liveStreamViewModel.streamingService
            as? HaishinKitManager
          {
            haishinKitManager.updateTextOverlay(
              show: viewModel.showTextOverlay, settings: viewModel.textOverlaySettings)
          }
        }
        .onChange(of: viewModel.textOverlaySettings) { _, newSettings in
          // 텍스트 설정 변경 시 HaishinKitManager 업데이트
          if let haishinKitManager = viewModel.liveStreamViewModel.streamingService
            as? HaishinKitManager
          {
            haishinKitManager.updateTextOverlay(
              show: viewModel.showTextOverlay, settings: newSettings)
          }
        }
        .onChange(of: viewModel.showTextOverlay) { _, newValue in
          // 텍스트 표시 상태 변경 시 HaishinKitManager 업데이트
          if let haishinKitManager = viewModel.liveStreamViewModel.streamingService
            as? HaishinKitManager
          {
            haishinKitManager.updateTextOverlay(
              show: newValue, settings: viewModel.textOverlaySettings)
          }
        }

        // 텍스트 오버레이
        if viewModel.showTextOverlay {
          TextOverlayDisplayView(
            settings: viewModel.textOverlaySettings,
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
        level: viewModel.liveStreamViewModel.microphonePeakLevel,
        decibels: viewModel.liveStreamViewModel.microphonePeakDecibels,
        isMuted: viewModel.liveStreamViewModel.isMicrophoneMuted,
        isStreaming: viewModel.liveStreamViewModel.status == .streaming,
        diagnosticMessage: viewModel.liveStreamViewModel.audioPeakDiagnosticMessage,
        inputSummary: viewModel.liveStreamViewModel.activeMicrophoneDisplaySummary
      )
      .frame(width: previewSize.width)
    }
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

// YouTube Studio 접근 뷰는 별도 파일로 모듈화됨:
// - YouTubeStudioAccessView.swift 참조
