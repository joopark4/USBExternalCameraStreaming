//
//  DetailView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI

// MARK: - Detail View Components

/// 상세 화면 View 컴포넌트
/// 선택된 사이드바 항목에 따라 적절한 콘텐츠를 표시하는 컴포넌트입니다.
struct DetailView: View {
  @ObservedObject var viewModel: MainViewModel

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

  var body: some View {
    GeometryReader { geometry in
      let containerSize = geometry.size
      let isWideScreen = containerSize.width > containerSize.height * 1.3  // 가로가 긴 화면 판단

      if isWideScreen {
        // 가로로 긴 화면 (iPad, Mac): 수평 분할
        horizontalLayout(containerSize: containerSize)
      } else {
        // 세로로 긴 화면 (iPhone): 수직 분할
        verticalLayout(containerSize: containerSize)
      }
    }
    .padding(.top, 0)  // 상단 패딩 제거
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
  }

  // MARK: - Layout Methods

  @ViewBuilder
  private func horizontalLayout(containerSize: CGSize) -> some View {
    HStack(spacing: 16) {  // 간격 줄임
      // 왼쪽: 카메라 프리뷰 + 텍스트 컨트롤 영역
      HStack(spacing: 12) {
        // 카메라 프리뷰
        cameraPreviewSection(
          availableSize: CGSize(
            width: containerSize.width * 0.35,  // 35%로 줄임 (텍스트 컨트롤 공간 확보)
            height: containerSize.height - 40
          )
        )

        // 텍스트 컨트롤 영역 (프리뷰 오른쪽에 세로 배치)
        VStack(spacing: 0) {
          TextOverlayControlView(viewModel: viewModel)
          Spacer()
        }
        .frame(width: 120)  // 고정 너비
      }
      .frame(maxWidth: containerSize.width * 0.45)

      // 오른쪽: YouTube Studio 영역 (더 크게)
      VStack(spacing: 0) {
        YouTubeStudioAccessView(viewModel: viewModel)
          .frame(maxHeight: .infinity)
      }
      .frame(maxWidth: containerSize.width * 0.55)  // 55%로 증가
    }
  }

  @ViewBuilder
  private func verticalLayout(containerSize: CGSize) -> some View {
    VStack(spacing: 7) {  // 간격을 4에서 7픽셀로 조정
      // 위쪽: 카메라 프리뷰 + 텍스트 컨트롤 영역 (고정 크기)
      // 상단 safe area 높이만큼 음수 오프셋 적용하여 인디케이터 영역으로 이동
      HStack(alignment: .top, spacing: 12) {  // alignment .top으로 변경하여 상단 정렬
        // 카메라 프리뷰
        cameraPreviewSection(
          availableSize: CGSize(
            width: containerSize.width - 140,  // 텍스트 컨트롤 공간 확보
            height: containerSize.height * 0.32  // 수정 전 크기로 되돌림
          )
        )

        // 텍스트 컨트롤 영역 (프리뷰 오른쪽에 세로 배치)
        VStack(spacing: 0) {
          TextOverlayControlView(viewModel: viewModel)
          Spacer()
        }
        .frame(width: 120)  // 고정 너비
      }
      .layoutPriority(0)  // 낮은 우선순위로 설정
      .offset(y: -20)  // 상단으로 20픽셀 이동하여 인디케이터와 같은 레벨로 이동

      // 아래쪽: YouTube Studio 영역 (남은 공간 모두 차지)
      YouTubeStudioAccessView(viewModel: viewModel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // 남은 공간 모두 차지
        .layoutPriority(1)  // 높은 우선순위로 확장
    }
  }

  @ViewBuilder
  private func cameraPreviewSection(availableSize: CGSize) -> some View {
    // 16:9 비율 계산 (유튜브 라이브 표준)
    let aspectRatio: CGFloat = 16.0 / 9.0
    let maxWidth = availableSize.width
    let maxHeight = availableSize.height  // 텍스트 영역 제거되어 60픽셀 빼기 불필요

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

    // 16:9 프리뷰 영역 (프리뷰 정보 텍스트 제거하여 간격 최소화)
    ZStack {
      // 카메라 프리뷰
      CameraPreviewView(
        session: viewModel.cameraViewModel.captureSession,
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
