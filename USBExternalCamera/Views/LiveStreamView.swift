//
//  LiveStreamView.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import SwiftUI

// MARK: - Live Stream Components

/// 라이브 스트리밍 섹션 View 컴포넌트
/// 라이브 스트리밍 관련 메뉴를 표시하는 독립적인 컴포넌트입니다.
struct LiveStreamSectionView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        Section(header: Text(NSLocalizedString("live_streaming_section", comment: "라이브 스트리밍 섹션"))) {
            // 스트리밍 시작/중지 토글 메뉴
            Button {
                print("🎮 [UI] Stream button tapped")
                viewModel.liveStreamViewModel.toggleStreaming(with: viewModel.cameraViewModel.captureSession)
            } label: {
                HStack {
                    Label(
                        viewModel.liveStreamViewModel.streamControlButtonText,
                        systemImage: viewModel.liveStreamViewModel.status == .streaming ? "stop.circle.fill" : "play.circle.fill"
                    )
                    Spacer()
                    
                    // 스트리밍 상태 표시
                    if viewModel.liveStreamViewModel.status != .idle {
                        Image(systemName: viewModel.liveStreamViewModel.status.iconName)
                            .foregroundColor(streamingStatusColor)
                            .font(.caption)
                    }
                }
            }
            .disabled(!viewModel.liveStreamViewModel.isStreamControlButtonEnabled)
            .foregroundColor(viewModel.liveStreamViewModel.status == .streaming ? .red : .primary)
            
            // 라이브 스트리밍 설정 메뉴
            Button {
                viewModel.showLiveStreamSettings()
            } label: {
                Label(NSLocalizedString("live_streaming_settings", comment: "라이브 스트리밍 설정"), 
                      systemImage: "gear")
            }
        }
    }
    
    /// 스트리밍 상태에 따른 색상
    private var streamingStatusColor: Color {
        switch viewModel.liveStreamViewModel.status {
        case .idle:
            return .gray
        case .connecting:
            return .orange
        case .connected:
            return .green
        case .streaming:
            return .green
        case .disconnecting:
            return .orange
        case .error:
            return .red
        }
    }
} 