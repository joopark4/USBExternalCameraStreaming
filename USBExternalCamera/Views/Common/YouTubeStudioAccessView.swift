//
//  YouTubeStudioAccessView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import LiveStreamingCore
import SwiftUI
import WebKit

// MARK: - YouTube Studio Access Components

/// YouTube Studio 접근 및 관리를 위한 통합 뷰 컴포넌트
///
/// **주요 기능:**
/// - **내장 YouTube Studio WebView** - Safari 17.1 User-Agent로 완전한 브라우저 호환성
/// - **실시간 스트리밍 상태 모니터링** - 라이브 상태 및 스트림 키 상태 표시
/// - **직접적인 스트림 관리 접근** - 앱 전환 없이 YouTube Studio 조작
/// - **커스텀 키보드 액세서리** - 키보드 입력 시 레이아웃 문제 해결
/// - **최적화된 레이아웃** - 웹뷰 공간 최대화 (500px 최소 높이)
///
/// **WebView 개선사항:**
/// - 데스크톱 브라우저 User-Agent (구버전 브라우저 메시지 해결)
/// - JavaScript 및 팝업 창 완전 지원
/// - 웹사이트 데이터 지속성 (로그인 상태 유지)
/// - iOS 버전별 최신 웹 기능 활성화
struct YouTubeStudioAccessView: View {
    @ObservedObject var viewModel: MainViewModel
    var showsSupplementaryInfo: Bool = true
    @StateObject private var keyboardAccessoryManager = KeyboardAccessoryManager()
    
    var body: some View {
        // 이중 VStack 제거하고 단일 VStack으로 간소화
        VStack(spacing: showsSupplementaryInfo ? 2 : 0) { // spacing 4에서 2로 줄임
            if showsSupplementaryInfo {
                // 메인 컨텐츠 - 웹뷰 공간을 최대화하기 위해 여백 최소화
                headerSection
                    .layoutPriority(0) // 낮은 우선순위
                
                // 스트리밍 상태 정보 (컴팩트하게)
                streamingStatusCard
                    .layoutPriority(0) // 낮은 우선순위
            }
            
            // YouTube Studio WebView (최대한 확장) - Spacer 역할로 남은 공간 모두 차지
            youtubeStudioWebView
                .frame(maxWidth: .infinity, maxHeight: .infinity) // 명시적으로 maxWidth, maxHeight infinity 설정
                .layoutPriority(1) // 높은 우선순위로 확장
        }
        .padding(2) // 패딩 4에서 2로 줄임
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
    
    // MARK: - Helper Functions
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var headerSection: some View {
        HStack {
            Image(systemName: "play.rectangle.fill")
                .foregroundColor(.red)
                .font(.body) // 더 작은 크기로
            Text("YouTube Studio")
                .font(.subheadline) // 더 작은 크기로
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.vertical, 2) // 상하 패딩을 4에서 2로 더 최소화
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
        .padding(.horizontal, 6) // 좌우 패딩 8에서 6으로 줄임
        .padding(.vertical, 3) // 상하 패딩 6에서 3으로 더 줄임
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
            .frame(maxWidth: .infinity, maxHeight: .infinity) // maxHeight .infinity 추가하여 전체 공간 활용
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
    

}

// MARK: - YouTube Studio WebView Component

/// YouTube Studio 내장 WebView 컴포넌트
///
/// **기술적 특징:**
/// - **Safari 17.1 User-Agent** - 최신 브라우저로 인식하여 모든 기능 사용 가능
/// - **고급 JavaScript 지원** - 팝업 창, 웹 앱 기능 완전 지원
/// - **데이터 지속성** - 로그인 상태 및 설정 자동 저장
/// - **키보드 최적화** - 커스텀 액세서리로 입력 경험 개선
/// - **iOS 버전별 기능** - 14.0+, 15.0+, 17.0+ 각각의 최신 기능 활용
struct YouTubeStudioWebView: UIViewRepresentable {
    private let youtubeStudioURL = "https://studio.youtube.com"
    let keyboardAccessoryManager: KeyboardAccessoryManager
    

    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 기본 미디어 재생 설정
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // 데이터 지속성 설정 (로그인 상태 유지)
        configuration.websiteDataStore = .default()
        
        // JavaScript 및 웹 기능 활성화
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        // iOS 14.0+: 앱 바운드 도메인 제한 해제
        if #available(iOS 14.0, *) {
            configuration.limitsNavigationsToAppBoundDomains = false
        }
        
        // iOS 15.0+: HTTPS 자동 업그레이드 비활성화 (혼합 콘텐츠 허용)
        if #available(iOS 15.0, *) {
            configuration.upgradeKnownHostsToHTTPS = false
        }
        
        // 키보드 입력 추적을 위한 메시지 핸들러 설정
        let messageHandler = InputTrackingMessageHandler(accessoryManager: keyboardAccessoryManager)
        configuration.userContentController.add(messageHandler, name: "inputChanged")
        configuration.userContentController.add(messageHandler, name: "inputFocused")
        configuration.userContentController.add(messageHandler, name: "inputBlurred")
        
        // WebView 인스턴스 생성
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // 데스크톱 Safari User-Agent 설정 (YouTube Studio 완전 호환성)
        let customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15"
        webView.customUserAgent = customUserAgent
        
        // iOS 17.0+: 웹 인스펙터 활성화 (개발/디버깅용)
        if #available(iOS 17.0, *) {
            webView.isInspectable = true
        }
        
        // 키보드 상호작용 최적화 설정
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        
        // YouTube Studio URL 로드
        if let url = URL(string: youtubeStudioURL) {
            var request = URLRequest(url: url)
            // 추가 헤더 설정으로 최신 브라우저 지원 명시
            request.setValue("max-age=0", forHTTPHeaderField: "Cache-Control")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("ko-KR,ko;q=0.8,en-US;q=0.6,en;q=0.4", forHTTPHeaderField: "Accept-Language")
            request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
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
            // 네비게이션 시작 (로딩 시작)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 페이지 로딩 완료 - 키보드 입력 추적 스크립트 주입
            webView.evaluateJavaScript(WebViewInputTrackingScript.defaultScript) { result, error in
                if let error = error {
                    logWarning("JavaScript 주입 실패: \(error.localizedDescription)", category: .error)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logError("WebView 로딩 실패: \(error.localizedDescription)", category: .error)
        }
    }
}

// MARK: - Implementation Notes

/*
 YouTube Studio WebView 구현 특징:
 
 1. 브라우저 호환성:
    - Safari 17.1 User-Agent로 "구버전 브라우저" 메시지 해결
    - 모든 YouTube Studio 기능 완전 지원
 
 2. 키보드 처리:
    - 커스텀 키보드 액세서리로 입력 최적화
    - 레이아웃 고정으로 키보드로 인한 UI 깨짐 방지
 
 3. 레이아웃 최적화:
    - 최소 높이 500px로 충분한 작업 공간 제공
    - 적응형 레이아웃으로 다양한 화면 크기 대응
 
 4. 성능 최적화:
    - 데이터 지속성으로 로그인 상태 유지
    - iOS 버전별 최신 웹 기능 활용
 */
