import SwiftUI
import WebKit
import Combine

// MARK: - Keyboard Accessory Kit
// 다른 프로젝트에서도 재사용 가능한 키보드 액세서리 컴포넌트 모듈

// MARK: - Input Tracking Message Handler

/// WebView에서 JavaScript 메시지를 받아 키보드 액세서리 매니저에 전달하는 핸들러
/// 
/// **사용법:**
/// ```swift
/// let messageHandler = InputTrackingMessageHandler(accessoryManager: keyboardAccessoryManager)
/// configuration.userContentController.add(messageHandler, name: "inputChanged")
/// configuration.userContentController.add(messageHandler, name: "inputFocused") 
/// configuration.userContentController.add(messageHandler, name: "inputBlurred")
/// ```
public class InputTrackingMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var accessoryManager: KeyboardAccessoryManager?
    
    public init(accessoryManager: KeyboardAccessoryManager) {
        self.accessoryManager = accessoryManager
        super.init()
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { 
            return 
        }
        
        switch message.name {
        case "inputChanged":
            if let text = body["text"] as? String,
               let placeholder = body["placeholder"] as? String {
                DispatchQueue.main.async {
                    self.accessoryManager?.updateTypingText(text, placeholder: placeholder)
                    // 기존 텍스트가 있으면 키보드가 표시되어야 함을 강제로 알림
                    if !text.isEmpty {
                        self.accessoryManager?.forceShowKeyboard()
                    }
                }
            }
        case "inputFocused":
            if let placeholder = body["placeholder"] as? String {
                let text = body["text"] as? String ?? ""
                DispatchQueue.main.async {
                    self.accessoryManager?.updateTypingText(text, placeholder: placeholder)
                    // 포커스 시 키보드 표시 강제 활성화
                    self.accessoryManager?.forceShowKeyboard()
                }
            }
        case "inputBlurred":
            DispatchQueue.main.async {
                self.accessoryManager?.hideKeyboard()
            }

        default:
            break
        }
    }
}

// MARK: - Keyboard Accessory Manager

/// 키보드 액세서리 뷰를 관리하는 ObservableObject
/// 
/// **주요 기능:**
/// - 키보드 표시/숨김 상태 추적
/// - 입력 중인 텍스트와 플레이스홀더 관리
/// - 키보드 강제 표시/숨김 기능
/// 
/// **사용법:**
/// ```swift
/// @StateObject private var keyboardAccessoryManager = KeyboardAccessoryManager()
/// 
/// // 키보드 액세서리 뷰 표시
/// if keyboardAccessoryManager.isKeyboardVisible && keyboardAccessoryManager.keyboardHeight > 0 {
///     KeyboardAccessoryView(manager: keyboardAccessoryManager)
/// }
/// ```
public class KeyboardAccessoryManager: ObservableObject {
    @Published public var isKeyboardVisible: Bool = false
    @Published public var keyboardHeight: CGFloat = 0
    @Published public var currentTypingText: String = ""
    @Published public var inputPlaceholder: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private var keyboardCheckTimer: Timer?
    
    public init() {
        setupKeyboardObservers()
    }
    
    deinit {
        keyboardCheckTimer?.invalidate()
    }
    
    private func setupKeyboardObservers() {
        // 키보드 표시 감지
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { notification in
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            }
            .sink { [weak self] keyboardFrame in
                DispatchQueue.main.async {
                    self?.isKeyboardVisible = true
                    self?.keyboardHeight = keyboardFrame.height
                }
            }
            .store(in: &cancellables)
        
        // 키보드 숨김 감지
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isKeyboardVisible = false
                    self?.keyboardHeight = 0
                    self?.currentTypingText = ""
                    self?.inputPlaceholder = ""
                }
            }
            .store(in: &cancellables)
    }
    
    /// 타이핑 중인 텍스트와 플레이스홀더 업데이트
    /// - Parameters:
    ///   - text: 현재 입력 중인 텍스트
    ///   - placeholder: 입력 필드의 플레이스홀더 텍스트
    public func updateTypingText(_ text: String, placeholder: String = "") {
        self.currentTypingText = text
        self.inputPlaceholder = placeholder
    }
    
    /// 기존 텍스트가 있는 필드에서 키보드가 즉시 표시되도록 강제
    /// 웹뷰에서 기존 텍스트가 있는 입력 필드에 포커스할 때 사용
    public func forceShowKeyboard() {
        // 실제 키보드가 나타날 때까지는 강제로 상태를 변경하지 않음
        // 대신 3초 후에 실제 키보드가 나타나지 않으면 강제 초기화
        keyboardCheckTimer?.invalidate()
        keyboardCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] timer in
            guard let self = self else { return }
            
            // 3초 후에도 실제 키보드가 나타나지 않았다면 상태 초기화
            if self.keyboardHeight == 0 {
                DispatchQueue.main.async {
                    self.isKeyboardVisible = false
                    self.currentTypingText = ""
                    self.inputPlaceholder = ""
                }
            }
            timer.invalidate()
        }
    }
    
    /// 키보드 숨김 처리
    public func hideKeyboard() {
        keyboardCheckTimer?.invalidate()
        self.isKeyboardVisible = false
        self.keyboardHeight = 0
        self.currentTypingText = ""
        self.inputPlaceholder = ""
    }
}

// MARK: - Keyboard Accessory View

/// 키보드 위에 표시되는 액세서리 뷰
/// 현재 입력 중인 텍스트와 플레이스홀더 정보를 표시합니다.
/// 
/// **사용법:**
/// ```swift
/// if keyboardAccessoryManager.isKeyboardVisible && keyboardAccessoryManager.keyboardHeight > 0 {
///     KeyboardAccessoryView(manager: keyboardAccessoryManager)
///         .offset(y: -keyboardAccessoryManager.keyboardHeight)
/// }
/// ```
public struct KeyboardAccessoryView: View {
    @ObservedObject public var manager: KeyboardAccessoryManager
    
    public init(manager: KeyboardAccessoryManager) {
        self.manager = manager
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // 왼쪽: 상태 표시
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .foregroundColor(.white)
                    .font(.system(size: 16))
                
                Text(manager.inputPlaceholder.isEmpty ? "입력 중..." : manager.inputPlaceholder)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            // 오른쪽: 입력 내용 표시
            if !manager.currentTypingText.isEmpty {
                Text(manager.currentTypingText)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemBackground))
                    )
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBlue))
        )
        .frame(height: 50)
    }
}

// MARK: - WebView Input Tracking JavaScript

/// WebView에 주입할 JavaScript 코드
/// 입력 필드의 포커스, 블러, 텍스트 변경을 감지하여 네이티브 앱에 메시지를 전송합니다.
public struct WebViewInputTrackingScript {
    
    /// 기본 입력 추적 JavaScript 코드
    /// - Returns: WebView에 주입할 JavaScript 문자열
    public static var defaultScript: String {
        return """
        // 전역 상태 관리
        window.inputTracker = {
            activeElement: null,
            lastValue: '',
            lastPlaceholder: '',
            intervalId: null,
            isEnabled: true
        };
        
        // 메시지 전송 함수
        function safeSendMessage(handlerName, data) {
            try {
                if (window.webkit && 
                    window.webkit.messageHandlers && 
                    window.webkit.messageHandlers[handlerName]) {
                    
                    window.webkit.messageHandlers[handlerName].postMessage(data);
                    return true;
                }
                return false;
            } catch (error) {
                return false;
            }
        }
        
        // 입력 값 변경 감지 및 전송
        function detectAndSendChange(element) {
            if (!element || !window.inputTracker.isEnabled) return;
            
            const currentValue = element.value || '';
            const currentPlaceholder = element.placeholder || element.getAttribute('aria-label') || '';
            
            if (currentValue !== window.inputTracker.lastValue || 
                currentPlaceholder !== window.inputTracker.lastPlaceholder) {
                
                window.inputTracker.lastValue = currentValue;
                window.inputTracker.lastPlaceholder = currentPlaceholder;
                
                safeSendMessage('inputChanged', {
                    text: currentValue,
                    placeholder: currentPlaceholder
                });
            }
        }
        
        // 포커스 이벤트 핸들러
        function handleFocus(event) {
            const element = event.target;
            if (element && (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA' || element.isContentEditable)) {
                window.inputTracker.activeElement = element;
                
                const text = element.value || element.textContent || '';
                const placeholder = element.placeholder || element.getAttribute('aria-label') || '';
                
                window.inputTracker.lastValue = text;
                window.inputTracker.lastPlaceholder = placeholder;
                
                safeSendMessage('inputFocused', {
                    text: text,
                    placeholder: placeholder
                });
                
                // 주기적 체크 시작
                if (window.inputTracker.intervalId) {
                    clearInterval(window.inputTracker.intervalId);
                }
                
                window.inputTracker.intervalId = setInterval(() => {
                    detectAndSendChange(window.inputTracker.activeElement);
                }, 200);
            }
        }
        
        // 블러 이벤트 핸들러
        function handleBlur(event) {
            const element = event.target;
            if (element && (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA' || element.isContentEditable)) {
                safeSendMessage('inputBlurred', {});
                
                // 주기적 체크 중단
                if (window.inputTracker.intervalId) {
                    clearInterval(window.inputTracker.intervalId);
                    window.inputTracker.intervalId = null;
                }
                
                window.inputTracker.activeElement = null;
                window.inputTracker.lastValue = '';
                window.inputTracker.lastPlaceholder = '';
            }
        }
        
        // 입력 이벤트 핸들러
        function handleInput(event) {
            detectAndSendChange(event.target);
        }
        
        // 이벤트 리스너 등록
        document.addEventListener('focusin', handleFocus, true);
        document.addEventListener('focusout', handleBlur, true);
        document.addEventListener('input', handleInput, true);
        
        // DOM 변경 감지 (동적으로 추가되는 입력 필드를 위해)
        const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                if (mutation.type === 'childList') {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === 1) { // Element 노드
                            const inputs = node.querySelectorAll ? node.querySelectorAll('input, textarea, [contenteditable]') : [];
                            inputs.forEach(function(input) {
                                input.addEventListener('focus', handleFocus, true);
                                input.addEventListener('blur', handleBlur, true);
                                input.addEventListener('input', handleInput, true);
                            });
                        }
                    });
                }
            });
        });
        
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
        """
    }
}

// MARK: - Usage Example

/*
 
 ## KeyboardAccessoryKit 사용 예제
 
 ### 1. WebView에서 키보드 액세서리 사용하기
 
 ```swift
 struct ContentView: View {
     @StateObject private var keyboardAccessoryManager = KeyboardAccessoryManager()
     
     var body: some View {
         ZStack {
             // 메인 컨텐츠
             MyWebView(keyboardAccessoryManager: keyboardAccessoryManager)
             
             // 키보드 액세서리 뷰
             if keyboardAccessoryManager.isKeyboardVisible && keyboardAccessoryManager.keyboardHeight > 0 {
                 VStack {
                     Spacer()
                     KeyboardAccessoryView(manager: keyboardAccessoryManager)
                         .offset(y: -keyboardAccessoryManager.keyboardHeight)
                 }
             }
         }
     }
 }
 
 struct MyWebView: UIViewRepresentable {
     let keyboardAccessoryManager: KeyboardAccessoryManager
     
     func makeUIView(context: Context) -> WKWebView {
         let configuration = WKWebViewConfiguration()
         
         // 메시지 핸들러 설정
         let messageHandler = InputTrackingMessageHandler(accessoryManager: keyboardAccessoryManager)
         configuration.userContentController.add(messageHandler, name: "inputChanged")
         configuration.userContentController.add(messageHandler, name: "inputFocused") 
         configuration.userContentController.add(messageHandler, name: "inputBlurred")
         
         let webView = WKWebView(frame: .zero, configuration: configuration)
         return webView
     }
     
     func updateUIView(_ uiView: WKWebView, context: Context) {
         // JavaScript 주입
         uiView.evaluateJavaScript(WebViewInputTrackingScript.defaultScript) { result, error in
             // 처리 완료
         }
     }
 }
 ```
 
 ### 2. 다른 프로젝트에서 파일 복사하여 사용
 
 1. `KeyboardAccessoryKit.swift` 파일을 프로젝트에 복사
 2. 위 예제 코드를 참고하여 구현
 3. 필요에 따라 `KeyboardAccessoryView`의 디자인 커스터마이징
 
 ### 3. 커스터마이징
 
 ```swift
 // 액세서리 뷰 색상 변경
 KeyboardAccessoryView(manager: keyboardAccessoryManager)
     .background(Color.red) // 배경색 변경
 
 // 매니저 확장 사용
 extension KeyboardAccessoryManager {
     func customFunction() {
         // 추가 기능 구현
     }
 }
 ```
 
 */ 