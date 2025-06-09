//
//  LiveStreamView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import AVFoundation

// MARK: - Live Stream Components

/// 라이브 스트리밍 섹션 View 컴포넌트
/// 라이브 스트리밍 관련 메뉴를 표시하는 독립적인 컴포넌트입니다.
struct LiveStreamSectionView: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
        Section(header: Text(NSLocalizedString("live_streaming_section", comment: "라이브 스트리밍 섹션"))) {
            // 기존 일반 스트리밍 버튼 제거 - 화면 캡처 스트리밍만 사용
            
            // MARK: - Screen Capture Streaming Button
            
            /// 🎬 화면 캡처 스트리밍 시작/중지 토글 버튼
            /// 
            /// **기능:**
            /// - CameraPreviewContainerView의 전체 화면(카메라 + UI)을 실시간 캡처
            /// - 30fps로 HaishinKit을 통해 스트리밍 서버에 전송
            /// - 일반 카메라 스트리밍과 독립적으로 동작
            ///
            /// **UI 상태:**
            /// - 버튼 텍스트: "스트리밍 시작 - 캡처" ↔ "스트리밍 중지 - 캡처"
            /// - 아이콘: camera.metering.partial ↔ stop.circle.fill
            /// - 상태 표시: Live 배지 표시 (스트리밍 중일 때)
            ///
            /// **사용자 경험:**
            /// - 처리 중일 때 "처리 중..." 텍스트 표시
            /// - 스트리밍 중일 때 빨간색 Live 배지로 시각적 피드백
            /// - 버튼 비활성화는 일반 스트리밍 버튼과 연동
            Button {
                logInfo("Streaming button tapped", category: .ui)
                viewModel.liveStreamViewModel.toggleScreenCaptureStreaming()
            } label: {
                HStack {
                    Label(
                        viewModel.liveStreamViewModel.streamingButtonText,
                        systemImage: viewModel.liveStreamViewModel.isScreenCaptureStreaming ? "stop.circle.fill" : "play.circle.fill"
                    )
                    Spacer()
                    
                    // 스트리밍 상태 표시
                    if viewModel.liveStreamViewModel.isScreenCaptureStreaming {
                        Text(NSLocalizedString("live_status", comment: "Live"))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
            }
            .disabled(viewModel.liveStreamViewModel.isLoading)
            .foregroundColor(viewModel.liveStreamViewModel.streamingButtonColor)
            
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
    
    /// 화면 캡처 스트리밍 버튼 텍스트
    /// 
    /// **동적 텍스트 생성:**
    /// 현재 스트리밍 상태와 로딩 상태에 따라 버튼 텍스트를 결정합니다.
    /// 사용자에게 현재 상태와 다음 동작을 명확하게 전달합니다.
    ///
    /// **상태별 텍스트:**
    /// - 로딩 중: "처리 중..." (비활성화 상태 표시)
    /// - 화면 캡처 활성: "스트리밍 중지 - 캡처" (중지 동작 안내)
    /// - 화면 캡처 비활성: "스트리밍 시작 - 캡처" (시작 동작 안내)
    ///
    /// **UX 고려사항:**
    /// "- 캡처" 접미사를 통해 일반 스트리밍과 구분하여
    /// 사용자가 기능을 명확히 인식할 수 있도록 함
    private var screenCaptureButtonText: String {
        if viewModel.liveStreamViewModel.isLoading {
            return NSLocalizedString("processing", comment: "처리 중...")
        } else if viewModel.isScreenCaptureStreaming {
            return NSLocalizedString("stop_streaming_capture", comment: "스트리밍 중지 - 캡처")
        } else {
            return NSLocalizedString("start_streaming_capture", comment: "스트리밍 시작 - 캡처")
        }
    }
} 

// MARK: - Import from ViewModels

struct LiveStreamView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingSettings = false
    @State private var showingConnectionTest = false
    @State private var showingErrorDetails = false
    @State private var showingRecoveryOptions = false
    @State private var showingLogs = false
    @State private var showingDiagnostics = false
    @State private var showingQuickCheck = false
    @State private var connectionTestResult: String = ""
    @State private var diagnosticsReport = ""
    @State private var quickCheckResult = ""
    
    // 실제 배포환경 ViewModel 사용 (MainViewModel에서 전달받음)
    @ObservedObject var viewModel: LiveStreamViewModel
    
    // 로깅 매니저
    @ObservedObject private var logger = StreamingLogger.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 상태 대시보드
                    statusDashboard
                    
                    // 에러 카드 (에러 발생시에만 표시)
                    if case .error = viewModel.status {
                        errorCard
                    }
                    
                    // 카메라 프리뷰 섹션
                    cameraPreviewSection
                    
                    // 제어 버튼들
                    controlButtons
                    
                    // 스트리밍 정보 섹션
                    streamingInfoSection
                }
                .padding()
            }
            .navigationTitle("라이브 스트리밍")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // 로그 뷰어 버튼
                    Button(action: { showingLogs = true }) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.blue)
                    }
                    
                    // 스트리밍 진단 버튼
                    Button(action: { 
                        Task {
                            await performQuickDiagnosis()
                        }
                    }) {
                        Image(systemName: "stethoscope")
                            .foregroundColor(.orange)
                    }
                    
                    // 실제 RTMP 연결 테스트 버튼
                    Button(action: { 
                        Task {
                            await performRealConnectionTest()
                        }
                    }) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.green)
                    }
                }
            }
            .sheet(isPresented: $showingLogs) {
                StreamingLogView()
            }
            .sheet(isPresented: $showingDiagnostics) {
                DiagnosticsReportView(report: diagnosticsReport)
            }
            .alert("스트리밍 진단 결과", isPresented: $showingQuickCheck) {
                Button("종합 진단 실행") {
                    Task {
                        await performFullDiagnostics()
                    }
                }
                Button("확인") { }
            } message: {
                Text(quickCheckResult)
            }
            .alert(NSLocalizedString("connection_test_result", comment: "연결 테스트 결과"), isPresented: $showingConnectionTest) {
                Button("확인") { }
            } message: {
                Text(connectionTestResult)
            }
            .alert("에러 복구 옵션", isPresented: $showingRecoveryOptions) {
                Button("재시도") {
                    Task {
                        if !viewModel.isStreaming {
                            // 화면 캡처 스트리밍 재시도 (카메라 스트리밍 아님)
                            await viewModel.startScreenCaptureStreaming()
                        }
                    }
                }
                Button("설정 확인") {
                    showingSettings = true
                }
                Button("취소", role: .cancel) { }
            } message: {
                if case .error(let error) = viewModel.status {
                    Text(error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Status Dashboard
    
    private var statusDashboard: some View {
        VStack(spacing: 16) {
            HStack {
                Text(NSLocalizedString("streaming_status", comment: "스트리밍 상태"))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                statusIndicator
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(NSLocalizedString("status_label", comment: "상태:"))
                        .foregroundColor(.secondary)
                    
                                    Text(statusText)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                }
                
                if viewModel.isScreenCaptureStreaming {
                    HStack {
                        Text(NSLocalizedString("duration_label", comment: "지속 시간:"))
                            .foregroundColor(.secondary)
                        
                        Text("00:00")
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .scaleEffect(viewModel.isScreenCaptureStreaming ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: viewModel.isScreenCaptureStreaming)
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(statusColor)
        }
    }
    
    // MARK: - Error Card
    
    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text(NSLocalizedString("error_occurred", comment: "오류 발생"))
                    .font(.headline)
                    .foregroundColor(.red)
                
                Spacer()
                
                Button("복구 옵션") {
                    showingRecoveryOptions = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if case .error(let error) = viewModel.status {
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Camera Preview Section
    
    private var cameraPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("camera_preview", comment: "카메라 프리뷰"))
                .font(.headline)
            
            Rectangle()
                .fill(Color.black)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text(NSLocalizedString("camera_preview", comment: "카메라 프리뷰"))
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption)
                    }
                )
                .cornerRadius(12)
        }
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        VStack(spacing: 16) {
            // 메인 제어 버튼
            Button(action: toggleStreaming) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: viewModel.isScreenCaptureStreaming ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                    
                    Text(streamingButtonText)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(streamingButtonColor)
                .foregroundColor(.white)
                .cornerRadius(25)
                .disabled(viewModel.isLoading)
            }
            
            // 보조 버튼들 (첫 번째 줄)
            HStack(spacing: 12) {
                // 연결 테스트 버튼
                Button(action: testConnection) {
                    HStack {
                        Image(systemName: "network")
                        Text(NSLocalizedString("connection_test", comment: "연결 테스트"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    .font(.system(size: 14, weight: .medium))
                }
                .disabled(viewModel.isLoading || viewModel.isScreenCaptureStreaming)
                
                // 빠른 진단 버튼
                Button(action: performQuickCheck) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text(NSLocalizedString("quick_diagnosis", comment: "빠른 진단"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    .font(.system(size: 14, weight: .medium))
                }
            }
            
            // 보조 버튼들 (두 번째 줄)
            HStack(spacing: 12) {
                // 전체 진단 버튼
                Button(action: {
                    Task {
                        await performFullDiagnostics()
                    }
                }) {
                    HStack {
                        Image(systemName: "stethoscope")
                        Text(NSLocalizedString("full_diagnosis", comment: "전체 진단"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    .font(.system(size: 14, weight: .medium))
                }
                
                // 설정 버튼
                NavigationLink(destination: LiveStreamSettingsView(viewModel: LiveStreamViewModel(modelContext: modelContext))) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text(NSLocalizedString("settings", comment: "설정"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    .font(.system(size: 14, weight: .medium))
                }
            }
        }
    }
    
    // MARK: - Streaming Info Section
    
    private var streamingInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("streaming_info", comment: "스트리밍 정보"))
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                
                // 비디오 품질
                InfoCard(
                    icon: "video.fill",
                    title: "비디오 품질",
                    value: "\(viewModel.settings.videoWidth)×\(viewModel.settings.videoHeight)",
                    color: .blue
                )
                
                // 네트워크 상태  
                InfoCard(
                    icon: "wifi",
                    title: "네트워크 상태",
                    value: viewModel.networkQuality.displayName,
                    color: Color(viewModel.networkQuality.color)
                )
                
                // 비트레이트
                InfoCard(
                    icon: "speedometer",
                    title: "비트레이트",
                    value: "\(viewModel.settings.videoBitrate) kbps",
                    color: .green
                )
                
                // 해상도
                InfoCard(
                    icon: "rectangle.fill",
                    title: "해상도",
                    value: resolutionText,
                    color: .purple
                )
            }
            

            
            // 실시간 송출 데이터 섹션 (스트리밍 중일 때만 표시)
            if viewModel.isScreenCaptureStreaming {
                realTimeTransmissionSection
            }
        }
    }
    
    // MARK: - RTMP Debugging Section
    
    private var rtmpDebuggingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network.badge.shield.half.filled")
                    .foregroundColor(.orange)
                Text(NSLocalizedString("rtmp_connection_debug", comment: "RTMP 연결 디버깅"))
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Spacer()
                
                // RTMP 연결 테스트 버튼
                Button(action: {
                    Task {
                        await testRTMPConnection()
                    }
                }) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(NSLocalizedString("test_connection", comment: "연결 테스트"))
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            
            VStack(spacing: 8) {
                // 기본 설정 정보
                rtmpSettingsCard
                
                // 실시간 연결 상태 (스트리밍 중일 때만)
                if viewModel.isScreenCaptureStreaming {
                    rtmpStatusCard
                }
                
                // 상세 디버그 정보 (스트리밍 중일 때만)
                if viewModel.isScreenCaptureStreaming {
                    rtmpDebugCard
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var rtmpSettingsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.blue)
                Text("RTMP 설정")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Group {
                HStack {
                    Text("URL:")
                        .fontWeight(.medium)
                        .frame(width: 60, alignment: .leading)
                    Text(viewModel.settings.rtmpURL.isEmpty ? "설정되지 않음" : viewModel.settings.rtmpURL)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(viewModel.settings.rtmpURL.isEmpty ? .red : .primary)
                }
                
                HStack {
                    Text("스트림 키:")
                        .fontWeight(.medium)
                        .frame(width: 60, alignment: .leading)
                    Text(viewModel.settings.streamKey.isEmpty ? "설정되지 않음" : "\(viewModel.settings.streamKey.count)자 (\(String(viewModel.settings.streamKey.prefix(8)))...)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(viewModel.settings.streamKey.isEmpty ? .red : .primary)
                }
                
                HStack {
                    Text("유효성:")
                        .fontWeight(.medium)
                        .frame(width: 60, alignment: .leading)
                    
                    if viewModel.validateRTMPURL(viewModel.settings.rtmpURL) && viewModel.validateStreamKey(viewModel.settings.streamKey) {
                        Label("설정 완료", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("설정 필요", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var rtmpStatusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.green)
                Text(NSLocalizedString("connection_status", comment: "연결 상태"))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // HaishinKitManager에서 연결 상태 가져오기
            if let haishinKitManager = viewModel.liveStreamService as? HaishinKitManager {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("상태:")
                            .fontWeight(.medium)
                            .frame(width: 60, alignment: .leading)
                        Text(haishinKitManager.connectionStatus)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Text("송출:")
                            .fontWeight(.medium)
                            .frame(width: 60, alignment: .leading)
                        Text("화면 캡처 스트리밍 중")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }
            } else {
                Text("스트리밍 매니저가 초기화되지 않음")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var rtmpDebugCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "ladybug")
                    .foregroundColor(.purple)
                Text("디버그 정보")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            // HaishinKitManager에서 디버그 정보 가져오기
            if viewModel.liveStreamService is HaishinKitManager {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text("화면 캡처 스트리밍 활성화됨")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 4)
                }
            } else {
                Text("디버그 정보를 사용할 수 없음")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(8)
    }
    
    // MARK: - Real-time Transmission Section
    
    private var realTimeTransmissionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("realtime_transmission_data", comment: "📡 실시간 송출 데이터"))
                    .font(.headline)
                
                Spacer()
                
                // Live 인디케이터
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseAnimation ? 1.3 : 0.7)
                        .animation(.easeInOut(duration: 1.0).repeatForever(), value: pulseAnimation)
                        .onAppear {
                            pulseAnimation = true
                        }
                    
                    Text(NSLocalizedString("live_status", comment: "LIVE"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                
                // 비디오 프레임 전송량
                TransmissionInfoCard(
                    icon: "video.fill",
                    title: "비디오 프레임",
                    value: formatFrameCount(viewModel.transmissionStats.videoFramesTransmitted),
                    subtitle: "frames sent",
                    color: .blue
                )
                
                // 현재 프레임율
                TransmissionInfoCard(
                    icon: "speedometer",
                    title: "프레임율",
                    value: String(format: "%.1f fps", viewModel.transmissionStats.averageFrameRate),
                    subtitle: "target: 30fps",
                    color: .green
                )
                
                // 총 전송 데이터량
                TransmissionInfoCard(
                    icon: "icloud.and.arrow.up.fill",
                    title: "전송량",
                    value: formatDataSize(viewModel.transmissionStats.totalBytesTransmitted),
                    subtitle: "total sent",
                    color: .purple
                )
                
                // 네트워크 지연시간
                TransmissionInfoCard(
                    icon: "wifi",
                    title: "지연시간",
                    value: String(format: "%.0fms", viewModel.transmissionStats.networkLatency * 1000),
                    subtitle: networkLatencyStatus,
                    color: networkLatencyColor
                )
                
                // 실제 비트레이트
                TransmissionInfoCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "비트레이트",
                    value: String(format: "%.0f kbps", viewModel.transmissionStats.currentVideoBitrate),
                    subtitle: "video stream",
                    color: .orange
                )
                
                // 드롭된 프레임
                TransmissionInfoCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "드롭 프레임",
                    value: "\(viewModel.transmissionStats.droppedFrames)",
                    subtitle: droppedFramesStatus,
                    color: droppedFramesColor
                )
            }
        }
        .padding()
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
    }
    
    @State private var pulseAnimation = false
    
    // MARK: - Helper Methods for Real-time Data
    
    private func formatFrameCount(_ count: Int64) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
    
    private func formatDataSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private var networkLatencyStatus: String {
        let latency = viewModel.transmissionStats.networkLatency * 1000
        if latency < 50 {
            return "excellent"
        } else if latency < 100 {
            return "good"
        } else if latency < 200 {
            return "fair"
        } else {
            return "poor"
        }
    }

    
    private var droppedFramesColor: Color {
        let dropped = viewModel.transmissionStats.droppedFrames
        if dropped == 0 {
            return .green
        } else if dropped < 10 {
            return .yellow
        } else if dropped < 50 {
            return .orange
        } else {
            return .red
        }
    }

    
    // MARK: - Helper Properties for Transmission Data
    
    private var networkLatencyColor: Color {
        let latency = viewModel.transmissionStats.networkLatency * 1000
        if latency < 50 {
            return .green
        } else if latency < 100 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var droppedFramesStatus: String {
        let dropped = viewModel.transmissionStats.droppedFrames
        if dropped == 0 {
            return "정상"
        } else if dropped < 10 {
            return "경미함"
        } else {
            return "심각함"
        }
    }
    
    // MARK: - Helper Methods for Data Formatting
    
    private func formatFrameCount(_ count: Int) -> String {
        if count > 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Alert Buttons
    
    @ViewBuilder
    private var alertButtons: some View {
        Button("확인") {
            connectionTestResult = ""
        }
        
        if !connectionTestResult.isEmpty && connectionTestResult.contains("실패") {
            Button("설정 확인") {
                // 설정 화면으로 이동하는 로직 추가 가능
            }
        }
    }
    
    @ViewBuilder
    private var recoveryActionButtons: some View {
        Button("재시도") {
            Task {
                await performRealConnectionTest()
            }
        }
        
        Button("설정 확인") {
            // 설정 화면으로 이동
        }
        
        Button("취소", role: .cancel) { }
    }
    
    // MARK: - Helper Methods
    
    private func toggleStreaming() {
        Task {
            // 화면 캡처 스트리밍 토글
            viewModel.toggleScreenCaptureStreaming()
        }
    }
    
    private func testConnection() {
        Task {
            await viewModel.testConnection()
            connectionTestResult = viewModel.connectionTestResult
            showingConnectionTest = true
        }
    }

    
    private var streamingButtonText: String {
        if viewModel.isLoading {
            return "처리 중..."
        }
        return viewModel.streamingButtonText
    }
    
    private var streamingButtonColor: Color {
        if viewModel.isLoading {
            return .gray
        }
        return viewModel.streamingButtonColor
    }
    
    private var resolutionText: String {
        return "\(viewModel.settings.videoWidth)×\(viewModel.settings.videoHeight)"
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    

    

    
    /// 실제 HaishinKit을 사용한 RTMP 연결 테스트
    private func performRealConnectionTest() async {
        logger.info("🧪 실제 RTMP 연결 테스트 시작", category: .connection)
        
        // HaishinKitManager 인스턴스 생성
        let haishinKitManager = HaishinKitManager()
        
        // 현재 설정 사용
        let settings = viewModel.settings
        
        // 설정 정보 로그
        logger.info("🔧 테스트 설정:", category: .connection)
        logger.info("📍 RTMP URL: \(settings.rtmpURL)", category: .connection)
        logger.info("🔑 Stream Key: [보안상 로그에 출력하지 않음]", category: .connection)
        logger.info("🎥 Video: \(settings.videoWidth)x\(settings.videoHeight) @ \(settings.videoBitrate)kbps", category: .connection)
        logger.info("🎵 Audio: \(settings.audioBitrate)kbps", category: .connection)
        
        // 실제 연결 테스트 수행
        let result = await haishinKitManager.testConnection(to: settings)
        
        // 결과 로그
        if result.isSuccessful {
            logger.info("✅ 실제 RTMP 연결 테스트 성공", category: .connection)
            logger.info("⏱️ 응답 시간: \(result.latency)ms", category: .performance)
            logger.info("📶 네트워크 품질: \(result.networkQuality.displayName)", category: .network)
        } else {
            logger.error("❌ 실제 RTMP 연결 테스트 실패", category: .connection)
            logger.error("💬 오류 메시지: \(result.message)", category: .connection)
        }
        
        // UI에 결과 표시
        await MainActor.run {
            connectionTestResult = result.message
            showingConnectionTest = true
        }
    }
    
    /// 빠른 연결 상태 확인
    private func performQuickCheck() {
        logger.info("⚡ 빠른 연결 상태 확인 시작", category: .connection)
        
        // 현재 viewModel 사용해서 빠른 진단 수행
        let result = viewModel.quickConnectionCheck()
        
        quickCheckResult = result
        showingQuickCheck = true
        
        logger.info("⚡ 빠른 진단 완료", category: .connection)
    }
    
    /// RTMP 연결 테스트 (HaishinKit 매니저 사용)
    private func testRTMPConnection() async {
        logger.info("🧪 [RTMP] HaishinKit RTMP 연결 테스트 시작", category: .connection)
        
        guard let haishinKitManager = viewModel.liveStreamService as? HaishinKitManager else {
            connectionTestResult = "❌ HaishinKit 매니저가 초기화되지 않았습니다."
            await MainActor.run {
                showingConnectionTest = true
            }
            logger.error("❌ [RTMP] HaishinKit 매니저 없음", category: .connection)
            return
        }
        
        // HaishinKit 매니저의 연결 테스트 실행
        await viewModel.testConnection()
        let result = viewModel.connectionTestResult
        
        logger.info("🧪 [RTMP] 테스트 결과: \(result)", category: .connection)
        
        await MainActor.run {
            connectionTestResult = result
            showingConnectionTest = true
        }
    }
    

    
    /// 🩺 빠른 스트리밍 진단 (새로운 메서드)
    private func performQuickDiagnosis() async {
        logger.info("🩺 빠른 스트리밍 진단 시작", category: .connection)
        
        // HaishinKitManager의 진단 기능 사용
        if let haishinKitManager = viewModel.liveStreamService as? HaishinKitManager {
            let (score, status, issues) = haishinKitManager.quickHealthCheck()
            
            var result = "🩺 빠른 진단 결과\n\n"
            result += "📊 종합 점수: \(score)점 (상태: \(status))\n\n"
            
            if issues.isEmpty {
                result += "✅ 발견된 문제 없음\n"
                result += "스트리밍 환경이 정상입니다."
            } else {
                result += "⚠️ 발견된 문제들:\n"
                for issue in issues {
                    result += "• \(issue)\n"
                }
                
                result += "\n💡 권장사항:\n"
                if issues.contains(where: { $0.contains("스트리밍이 시작되지 않음") }) {
                    result += "• YouTube Studio에서 라이브 스트리밍을 시작하세요\n"
                }
                if issues.contains(where: { $0.contains("RTMP 연결") }) {
                    result += "• 스트림 키와 RTMP URL을 확인하세요\n"
                }
                if issues.contains(where: { $0.contains("화면 캡처") }) {
                    result += "• 화면 캡처 모드가 활성화되었는지 확인하세요\n"
                }
                if issues.contains(where: { $0.contains("재연결") }) {
                    result += "• 잠시 후 다시 시도하거나 수동으로 재시작하세요\n"
                }
            }
            
            await MainActor.run {
                quickCheckResult = result
                showingQuickCheck = true
            }
        } else {
            await MainActor.run {
                quickCheckResult = "❌ HaishinKitManager를 찾을 수 없습니다."
                showingQuickCheck = true
            }
        }
        
        logger.info("🩺 빠른 스트리밍 진단 완료", category: .connection)
    }
    
    /// 🔍 종합 스트리밍 진단 (새로운 메서드)
    private func performFullDiagnostics() async {
        logger.info("🔍 종합 스트리밍 진단 시작", category: .connection)
        
        // HaishinKitManager의 종합 진단 기능 사용
        if let haishinKitManager = viewModel.liveStreamService as? HaishinKitManager {
            // 종합 진단 실행
            let report = await haishinKitManager.performComprehensiveStreamingDiagnosis()
            
            // 사용자 친화적인 보고서 생성
            var userFriendlyReport = """
            🔍 HaishinKit 스트리밍 종합 진단 결과
            
            📊 종합 점수: \(report.overallScore)점/100점 (등급: \(report.overallGrade))
            
            💡 평가: \(report.getRecommendation())
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            📋 세부 진단 결과:
            
            1️⃣ 설정 검증: \(report.configValidation.isValid ? "✅ 통과" : "❌ 실패")
            \(report.configValidation.summary)
            
            2️⃣ MediaMixer: \(report.mediaMixerStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.mediaMixerStatus.summary)
            
            3️⃣ RTMPStream: \(report.rtmpStreamStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.rtmpStreamStatus.summary)
            
            4️⃣ 화면 캡처: \(report.screenCaptureStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.screenCaptureStatus.summary)
            
            5️⃣ 네트워크: \(report.networkStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.networkStatus.summary)
            
            6️⃣ 디바이스: \(report.deviceStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.deviceStatus.summary)
            
            7️⃣ 데이터 흐름: \(report.dataFlowStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.dataFlowStatus.summary)
            
            """
            
            // 문제가 있는 항목들의 상세 정보 추가
            let allIssues = [
                report.configValidation.issues,
                report.mediaMixerStatus.issues,
                report.rtmpStreamStatus.issues,
                report.screenCaptureStatus.issues,
                report.networkStatus.issues,
                report.deviceStatus.issues,
                report.dataFlowStatus.issues
            ].flatMap { $0 }
            
            if !allIssues.isEmpty {
                userFriendlyReport += "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                userFriendlyReport += "\n⚠️ 발견된 문제점들:\n"
                for issue in allIssues {
                    userFriendlyReport += "• \(issue)\n"
                }
            }
            
            // 해결 가이드 추가
            let troubleshootingGuide = await haishinKitManager.generateTroubleshootingGuide()
            userFriendlyReport += "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            userFriendlyReport += "\n\(troubleshootingGuide)"
            
            await MainActor.run {
                diagnosticsReport = userFriendlyReport
                showingDiagnostics = true
            }
        } else {
            await MainActor.run {
                diagnosticsReport = "❌ HaishinKitManager를 찾을 수 없습니다."
                showingDiagnostics = true
            }
        }
        
        logger.info("🔍 종합 스트리밍 진단 완료", category: .connection)
    }
    
    // MARK: - Helper Properties
    
    private var statusColor: Color {
        if viewModel.isScreenCaptureStreaming {
            return .green
        }
        
        switch viewModel.status {
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
    
    private var statusText: String {
        if viewModel.isScreenCaptureStreaming {
            return "화면 캡처 스트리밍 중"
        }
        
        // HaishinKitManager의 연결 상태 메시지 표시
        if let haishinKitManager = viewModel.liveStreamService as? HaishinKitManager {
            return viewModel.statusMessage.isEmpty ? haishinKitManager.connectionStatus : viewModel.statusMessage
        }
        return viewModel.statusMessage.isEmpty ? "준비됨" : viewModel.statusMessage
    }
}

// MARK: - Info Card Component

struct InfoCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Transmission Info Card Component

struct TransmissionInfoCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
                
                // 실시간 업데이트 표시
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulseAnimation ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 1.0).repeatForever(), value: pulseAnimation)
                    .onAppear {
                        pulseAnimation = true
                    }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Text(value)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
    
    @State private var pulseAnimation = false
}

// MARK: - Preview

#Preview {
    // Preview는 실제 ModelContext를 생성하기 어려우므로 주석 처리
    ContentView()
        .preferredColorScheme(.light)
}

// MARK: - Diagnostics Report View

/// 진단 보고서를 표시하는 시트 뷰
struct DiagnosticsReportView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(report)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("진단 보고서")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("공유") {
                        shareReport()
                    }
                }
            }
        }
    }
    
    private func shareReport() {
        let activityController = UIActivityViewController(
            activityItems: [report],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
    }
} 
