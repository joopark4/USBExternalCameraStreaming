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
                print("🎬 [UI] Screen capture stream button tapped")
                viewModel.toggleScreenCaptureStreaming()
            } label: {
                HStack {
                    Label(
                        screenCaptureButtonText,
                        systemImage: viewModel.isScreenCaptureStreaming ? "stop.circle.fill" : "camera.metering.partial"
                    )
                    Spacer()
                    
                    // 화면 캡처 스트리밍 상태 표시
                    /// 
                    /// **상태 배지:**
                    /// 화면 캡처 스트리밍이 활성화되어 있을 때
                    /// 빨간색 "Live" 배지를 표시하여 사용자에게 명확한 시각적 피드백 제공
                    if viewModel.isScreenCaptureStreaming {
                        Text("Live")
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
            .disabled(!viewModel.liveStreamViewModel.isStreamControlButtonEnabled)
            .foregroundColor(viewModel.isScreenCaptureStreaming ? .red : .primary)
            
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
            return "처리 중..."
        } else if viewModel.isScreenCaptureStreaming {
            return "스트리밍 중지 - 캡처"
        } else {
            return "스트리밍 시작 - 캡처"
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
            .alert("빠른 연결 상태 확인", isPresented: $showingQuickCheck) {
                Button("전체 진단 실행") {
                    Task {
                        await performFullDiagnostics()
                    }
                }
                Button("확인") { }
            } message: {
                Text(quickCheckResult)
            }
            .alert("연결 테스트 결과", isPresented: $showingConnectionTest) {
                Button("확인") { }
            } message: {
                Text(connectionTestResult)
            }
            .alert("에러 복구 옵션", isPresented: $showingRecoveryOptions) {
                Button("재시도") {
                    Task {
                        if !viewModel.isStreaming {
                            let captureSession = AVCaptureSession()
                            await viewModel.startStreaming(with: captureSession)
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
                Text("스트리밍 상태")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                statusIndicator
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("상태:")
                        .foregroundColor(.secondary)
                    
                                    Text(statusText)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                }
                
                if viewModel.isStreaming {
                    HStack {
                        Text("지속 시간:")
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
                .scaleEffect(viewModel.isStreaming ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: viewModel.isStreaming)
            
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
                
                Text("오류 발생")
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
            Text("카메라 프리뷰")
                .font(.headline)
            
            Rectangle()
                .fill(Color.black)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("카메라 프리뷰")
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
                        Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "play.circle.fill")
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
                        Text("연결 테스트")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(22)
                    .font(.system(size: 14, weight: .medium))
                }
                .disabled(viewModel.isLoading || viewModel.isStreaming)
                
                // 빠른 진단 버튼
                Button(action: performQuickCheck) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("빠른 진단")
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
                        Text("전체 진단")
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
                        Text("설정")
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
            Text("스트리밍 정보")
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
            if viewModel.isStreaming {
                realTimeTransmissionSection
            }
        }
    }
    
    // MARK: - Real-time Transmission Section
    
    private var realTimeTransmissionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("📡 실시간 송출 데이터")
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
                    
                    Text("LIVE")
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
            if viewModel.isStreaming {
                await viewModel.stopStreaming()
            } else {
                let captureSession = AVCaptureSession()
                await viewModel.startStreaming(with: captureSession)
            }
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
            return viewModel.isStreaming ? "중지 중..." : "시작 중..."
        }
        return viewModel.isStreaming ? "스트리밍 중지" : "스트리밍 시작"
    }
    
    private var streamingButtonColor: Color {
        if viewModel.isLoading {
            return .gray
        }
        return viewModel.isStreaming ? .red : .green
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
        logger.info("🔑 Stream Key: \(settings.streamKey.prefix(8))...", category: .connection)
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
    
    /// 전체 진단 수행
    private func performFullDiagnostics() async {
        logger.info("🔍 전체 진단 시작", category: .connection)
        
        // 현재 viewModel 사용해서 전체 진단 수행
        let report = await viewModel.diagnoseLiveStreamConnection()
        
        await MainActor.run {
            diagnosticsReport = report
            showingDiagnostics = true
        }
        
        logger.info("🔍 전체 진단 완료", category: .connection)
    }
    
    // MARK: - Helper Properties
    
    private var statusColor: Color {
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
        switch viewModel.status {
        case .idle:
            return "대기"
        case .connecting:
            return "연결 중"
        case .connected:
            return "연결됨"
        case .streaming:
            return "스트리밍"
        case .disconnecting:
            return "해제 중"
        case .error:
            return "오류"
        }
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

struct LiveStreamView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview를 위한 더미 ViewModel
        let dummyViewModel = LiveStreamViewModelStub()
        return AnyView(Text("LiveStreamView Preview"))
    }
}

// MARK: - Diagnostics Report View

/// 진단 보고서를 표시하는 뷰
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
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("송출 상태 진단")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: shareReport) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
    
    private func shareReport() {
        let activityVC = UIActivityViewController(
            activityItems: [report],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
} 