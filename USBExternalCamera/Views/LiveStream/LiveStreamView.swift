//
//  LiveStreamView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//
import SwiftUI
import AVFoundation
import LiveStreamingCore
// MARK: - Import from ViewModels
struct LiveStreamView: View {
    @Environment(\.modelContext) var modelContext
    @State var showingSettings = false
    @State var showingConnectionTest = false
    @State var showingErrorDetails = false
    @State var showingRecoveryOptions = false
    @State var showingLogs = false
    @State var showingDiagnostics = false
    @State var showingQuickCheck = false
    @State var connectionTestResult: String = ""
    @State var diagnosticsReport = ""
    @State var quickCheckResult = ""
    @State var pulseAnimation = false
    // 실제 배포환경 ViewModel 사용 (MainViewModel에서 전달받음)
    @ObservedObject var viewModel: LiveStreamViewModel
    // 로깅 매니저
    @ObservedObject var logger = StreamingLogger.shared
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
}
