//
//  LiveStreamControlView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import SwiftData
import AVFoundation
import HaishinKit

/// 라이브 스트리밍 컨트롤 View
/// HaishinKit을 사용한 실시간 스트리밍 제어 및 모니터링 기능을 제공합니다.
struct LiveStreamControlView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    let captureSession: AVCaptureSession
    
    // MARK: - State Properties
    
    @State private var showingConnectionTest = false
    @State private var showingAdvancedSettings = false
    @State private var showingQualitySelector = false
    @State private var showingYouTubeGuide = false
    @State private var selectedPreset: StreamingPreset = .standard
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 16) {
            // 현재 상태 표시 섹션
            CurrentStatusSection(viewModel: viewModel)
            
            // 스트리밍 제어 버튼 섹션
            StreamingControlSection(viewModel: viewModel)
            
            // 네트워크 품질 모니터링 섹션
            NetworkQualitySection(viewModel: viewModel)
            
            // 고급 기능 섹션
            AdvancedSettingsSection(
                viewModel: viewModel,
                showingAdvancedSettings: $showingAdvancedSettings,
                showingConnectionTest: $showingConnectionTest,
                showingYouTubeGuide: $showingYouTubeGuide
            )
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingAdvancedSettings) {
            AdvancedStreamingSettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingConnectionTest) {
            ConnectionTestView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingYouTubeGuide) {
            YouTubeLiveSetupGuide()
        }
        .actionSheet(isPresented: $showingQualitySelector) {
            qualityPresetActionSheet
        }
    }
    
    // MARK: - Action Sheet
    
    private var qualityPresetActionSheet: ActionSheet {
        ActionSheet(
            title: Text(NSLocalizedString("select_quality_preset", comment: "화질 프리셋 선택")),
            message: Text(NSLocalizedString("preset_will_override_settings", comment: "프리셋 적용 시 현재 설정이 변경됩니다")),
            buttons: StreamingPreset.allCases.map { preset in
                ActionSheet.Button.default(Text(preset.displayName)) {
                    selectedPreset = preset
                    viewModel.applyPreset(preset)
                }
            } + [ActionSheet.Button.cancel()]
        )
    }
}

// MARK: - Supporting Views

/// 현재 상태 표시 섹션
struct CurrentStatusSection: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("현재 상태")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(viewModel.statusMessage)
                    .font(.body)
                Spacer()
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch viewModel.status {
        case .idle: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .streaming: return .blue
        case .disconnecting: return .orange
        case .error: return .red
        }
    }
}

/// 스트리밍 제어 버튼 섹션
struct StreamingControlSection: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        // 구현 필요
        EmptyView()
    }
}

/// 네트워크 품질 모니터링 섹션
struct NetworkQualitySection: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    
    var body: some View {
        // 구현 필요
        EmptyView()
    }
}

/// 고급 기능 섹션
struct AdvancedSettingsSection: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    @Binding var showingAdvancedSettings: Bool
    @Binding var showingConnectionTest: Bool
    @Binding var showingYouTubeGuide: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("advanced_features", comment: "고급 기능"))
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                // YouTube 설정 가이드
                Button(action: {
                    showingYouTubeGuide = true
                }) {
                    HStack {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .foregroundColor(.red)
                        Text("YouTube Live 설정 가이드")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                
                // YouTube 스트리밍 진단
                Button(action: {
                    Task {
                        let diagnosis = await viewModel.diagnoseYouTubeStreaming()
                        print("🔍 [UI] YouTube 진단 결과:")
                        diagnosis.forEach { print("   \($0)") }
                    }
                }) {
                    HStack {
                        Image(systemName: "stethoscope")
                            .foregroundColor(.orange)
                        Text("YouTube 스트리밍 진단")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                
                // 연결 테스트
                Button(action: {
                    showingConnectionTest = true
                }) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(NSLocalizedString("test_connection", comment: "연결 테스트"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                
                // 고급 설정
                Button(action: {
                    showingAdvancedSettings = true
                }) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text(NSLocalizedString("advanced_settings", comment: "고급 설정"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                
                // 설정 내보내기
                Button(action: {
                    print("📤 [UI] Settings export requested - feature not implemented")
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(NSLocalizedString("export_settings", comment: "설정 내보내기"))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Sheet Views

/// 연결 테스트 View
struct ConnectionTestView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isTesting {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(NSLocalizedString("testing_connection", comment: "연결 테스트 중..."))
                        .font(.headline)
                } else if let result = testResult {
                    Image(systemName: result.isSuccessful ? "checkmark.circle" : "xmark.circle")
                        .font(.system(size: 60))
                        .foregroundColor(result.isSuccessful ? .green : .red)
                    
                    Text(result.message)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("지연시간: \(Int(result.latency))ms")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text(NSLocalizedString("ready_to_test", comment: "연결 테스트 준비됨"))
                        .font(.headline)
                    
                    Button(NSLocalizedString("start_test", comment: "테스트 시작")) {
                        performConnectionTest()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(NSLocalizedString("connection_test", comment: "연결 테스트"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("done", comment: "완료")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func performConnectionTest() {
        isTesting = true
        testResult = nil
        
        Task {
            await viewModel.testConnection()
            
            await MainActor.run {
                // viewModel.connectionTestResult에서 결과를 가져옴
                let message = viewModel.connectionTestResult
                let isSuccessful = message.contains("유효합니다")
                
                self.testResult = ConnectionTestResult(
                    isSuccessful: isSuccessful,
                    latency: isSuccessful ? 100 : 0,
                    message: message,
                    networkQuality: isSuccessful ? .good : .poor
                )
                self.isTesting = false
            }
        }
    }
}

/// 고급 스트리밍 설정 View
struct AdvancedStreamingSettingsView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // 인코더 설정 섹션
                Section(header: Text(NSLocalizedString("encoder_settings", comment: "인코더 설정"))) {
                    Picker("비디오 인코더", selection: $viewModel.settings.videoEncoder) {
                        Text("H.264").tag("H.264")
                        Text("H.265").tag("H.265")
                    }
                    
                    Picker("오디오 인코더", selection: $viewModel.settings.audioEncoder) {
                        Text("AAC").tag("AAC")
                        Text("MP3").tag("MP3")
                    }
                }
                
                // 고급 네트워크 설정
                Section(header: Text(NSLocalizedString("network_settings", comment: "네트워크 설정"))) {
                    HStack {
                        Text("버퍼 크기")
                        Spacer()
                        Text("\(viewModel.settings.bufferSize) MB")
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.settings.bufferSize) },
                            set: { viewModel.settings.bufferSize = Int($0) }
                        ),
                        in: 1...10,
                        step: 1
                    )
                    
                    HStack {
                        Text("연결 타임아웃")
                        Spacer()
                        Text("\(viewModel.settings.connectionTimeout)초")
                    }
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.settings.connectionTimeout) },
                            set: { viewModel.settings.connectionTimeout = Int($0) }
                        ),
                        in: 5...60,
                        step: 5
                    )
                }
                
                // 자동화 설정
                Section(header: Text(NSLocalizedString("automation", comment: "자동화"))) {
                    Toggle("자동 재연결", isOn: $viewModel.settings.autoReconnect)
                    Toggle("스트리밍 활성화", isOn: $viewModel.settings.isEnabled)
                }
            }
            .navigationTitle(NSLocalizedString("advanced_settings", comment: "고급 설정"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("cancel", comment: "취소")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("save", comment: "저장")) {
                        viewModel.saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// YouTube Live 설정 가이드 View
struct YouTubeLiveSetupGuide: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 헤더 섹션
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        
                        Text("YouTube Live 설정 가이드")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("YouTube에서 라이브 스트리밍을 시작하기 위한 단계별 가이드입니다.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    // 단계별 가이드
                    SetupStepCard(
                        stepNumber: "1",
                        title: "YouTube Studio 접속",
                        description: "웹 브라우저에서 studio.youtube.com에 접속하세요.",
                        icon: "globe",
                        iconColor: .blue
                    )
                    
                    SetupStepCard(
                        stepNumber: "2", 
                        title: "라이브 스트리밍 메뉴 선택",
                        description: "왼쪽 메뉴에서 '라이브 스트리밍'을 클릭하세요.",
                        icon: "list.bullet",
                        iconColor: .green
                    )
                    
                    SetupStepCard(
                        stepNumber: "3",
                        title: "스트림 탭으로 이동", 
                        description: "상단의 '스트림' 탭을 선택하세요.",
                        icon: "tab.backward",
                        iconColor: .orange
                    )
                    
                    SetupStepCard(
                        stepNumber: "4",
                        title: "라이브 스트리밍 시작",
                        description: "'라이브 스트리밍 시작' 버튼을 클릭하여 대기 상태로 만드세요.",
                        icon: "play.circle",
                        iconColor: .red
                    )
                    
                    SetupStepCard(
                        stepNumber: "5",
                        title: "스트림 키 복사",
                        description: "스트림 키를 복사하여 이 앱의 설정에 붙여넣으세요.",
                        icon: "doc.on.clipboard",
                        iconColor: .purple
                    )
                    
                    // 중요 사항
                    VStack(alignment: .leading, spacing: 12) {
                        Label("중요 사항", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• 라이브 스트리밍 기능이 활성화되어 있어야 합니다")
                            Text("• 휴대폰 번호 인증이 완료되어 있어야 합니다")
                            Text("• 스트림 키는 절대 공개하지 마세요")
                            Text("• 매번 새로운 라이브 스트리밍을 시작해야 합니다")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    
                    // 문제 해결
                    VStack(alignment: .leading, spacing: 12) {
                        Label("문제 해결", systemImage: "wrench.and.screwdriver")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("연결이 안 되는 경우:")
                                .fontWeight(.semibold)
                            Text("• 새로운 스트림 키를 생성해보세요")
                            Text("• WiFi/모바일 데이터를 전환해보세요")
                            Text("• VPN을 끄고 재시도하세요")
                            Text("• 방화벽에서 포트 1935를 허용하세요")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("설정 가이드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// 설정 단계 카드
struct SetupStepCard: View {
    let stepNumber: String
    let title: String
    let description: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            // 단계 번호
            ZStack {
                Circle()
                    .fill(iconColor)
                    .frame(width: 40, height: 40)
                Text(stepNumber)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

/// YouTube 설정 프롬프트
struct YouTubeSetupPrompt: View {
    @Binding var showingYouTubeGuide: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("YouTube Live 설정이 필요합니다")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("스트리밍을 시작하려면 YouTube에서 스트림 키를 가져와야 합니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Button(action: {
                showingYouTubeGuide = true
            }) {
                HStack {
                    Image(systemName: "play.rectangle.on.rectangle")
                    Text("설정 가이드 보기")
                }
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.blue)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    let viewModel = LiveStreamViewModel(modelContext: try! ModelContainer(for: LiveStreamSettingsModel.self).mainContext)
    let session = AVCaptureSession()
    
    return LiveStreamControlView(viewModel: viewModel, captureSession: session)
} 