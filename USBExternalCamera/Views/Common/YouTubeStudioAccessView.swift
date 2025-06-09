//
//  YouTubeStudioAccessView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import WebKit

// MARK: - YouTube Studio Access Components

/// YouTube Studio 접근 View 컴포넌트
/// 프리뷰 아래에 YouTube Studio 내장 웹뷰를 제공합니다.
/// 
/// **주요 기능:**
/// - YouTube Studio 내장 WebView
/// - 스트리밍 상태 실시간 모니터링
/// - 직접적인 스트림 관리 접근
/// - 네이티브 텍스트 입력 오버레이로 키보드 문제 해결
struct YouTubeStudioAccessView: View {
    @ObservedObject var viewModel: MainViewModel
    @StateObject private var keyboardAccessoryManager = KeyboardAccessoryManager()
    
    var body: some View {
        ZStack {
            // 메인 컨텐츠
            VStack(spacing: 12) {
                // 헤더
                headerSection
                
                // 스트리밍 상태 정보
                streamingStatusCard
                
                // YouTube Studio WebView
                youtubeStudioWebView
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            .ignoresSafeArea(.keyboard) // 키보드로 인한 크기 변경 완전 차단
            
            // 키보드가 실제로 표시될 때만 액세서리 뷰 표시
            if keyboardAccessoryManager.isKeyboardVisible && keyboardAccessoryManager.keyboardHeight > 0 {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                                            KeyboardAccessoryView(manager: keyboardAccessoryManager)
                        .offset(y: -keyboardAccessoryManager.keyboardHeight)
                        .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .allowsHitTesting(false) // GeometryReader는 터치 차단하지 않음
                .ignoresSafeArea()
                .zIndex(1000) // 최상위 레이어지만 터치는 통과
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: keyboardAccessoryManager.isKeyboardVisible)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var headerSection: some View {
        HStack {
            Image(systemName: "play.rectangle.fill")
                .foregroundColor(.red)
                .font(.title3)
            Text("YouTube Studio")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
        }
    }
    
    @ViewBuilder
    private var streamingStatusCard: some View {
        let streamingStatus = viewModel.liveStreamViewModel.status
        let isStreaming = (streamingStatus == .streaming)
        
        HStack {
            // 라이브 상태 표시
            Circle()
                .fill(isStreaming ? Color.red : Color.gray)
                .frame(width: 8, height: 8)
                .scaleEffect(isStreaming ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isStreaming)
            
            // 상태 텍스트
            VStack(alignment: .leading, spacing: 2) {
                Text(isStreaming ? NSLocalizedString("live_status", comment: "🔴 LIVE") : NSLocalizedString("waiting_status", comment: "⚪ 대기 중"))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(isStreaming ? .red : .secondary)
                
                Text(streamingStatus.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 스트림 키 상태 표시
            streamKeyStatusIndicator
        }
        .padding(8)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(6)
    }
    
    @ViewBuilder
    private var streamKeyStatusIndicator: some View {
        let hasStreamKey = !viewModel.liveStreamViewModel.settings.streamKey.isEmpty
        let isValidStreamKey = viewModel.liveStreamViewModel.settings.streamKey != "YOUR_YOUTUBE_STREAM_KEY_HERE" && hasStreamKey
        
        Image(systemName: isValidStreamKey ? "key.fill" : "key.slash")
            .foregroundColor(isValidStreamKey ? .green : .red)
            .font(.caption)
    }
    
    @ViewBuilder
    private var youtubeStudioWebView: some View {
        YouTubeStudioWebView(keyboardAccessoryManager: keyboardAccessoryManager)
            .frame(minHeight: 300, maxHeight: .infinity)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
    

}

// MARK: - YouTube Studio WebView Component

/// YouTube Studio 내장 WebView 컴포넌트
/// 앱 내에서 직접 YouTube Studio에 접근할 수 있는 웹뷰를 제공합니다.
struct YouTubeStudioWebView: UIViewRepresentable {
    private let youtubeStudioURL = "https://studio.youtube.com"
    let keyboardAccessoryManager: KeyboardAccessoryManager
    

    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // 강화된 메시지 핸들러 설정
        let messageHandler = InputTrackingMessageHandler(accessoryManager: keyboardAccessoryManager)
        
        // 기본 핸들러들
        configuration.userContentController.add(messageHandler, name: "inputChanged")
        configuration.userContentController.add(messageHandler, name: "inputFocused") 
        configuration.userContentController.add(messageHandler, name: "inputBlurred")
        

        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // 키보드 관련 설정: 웹뷰 크기 변경 방지
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .never // 자동 크기 조정 완전 비활성화
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false // 스크롤 인디케이터 자동 조정 비활성화
        
        // YouTube Studio URL 로드
        if let url = URL(string: youtubeStudioURL) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 업데이트 로직이 필요한 경우 여기에 구현
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: YouTubeStudioWebView
        
        init(_ parent: YouTubeStudioWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // WebView 로딩 시작
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // WebView 로딩 완료 - 모듈화된 JavaScript 주입
            webView.evaluateJavaScript(WebViewInputTrackingScript.defaultScript) { result, error in
                // JavaScript 주입 결과 처리
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // WebView 로딩 실패 처리
        }
    }
}

// YouTube Studio 버튼 컴포넌트는 제거됨 - 항상 표시되는 WebView로 대체

// YouTube Studio 접근 뷰 - 진단 및 설정 가이드 기능 제거됨
// 내장 WebView를 통한 직접적인 YouTube Studio 접근에 집중 