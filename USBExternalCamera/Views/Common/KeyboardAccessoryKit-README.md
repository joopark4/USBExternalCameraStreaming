# KeyboardAccessoryKit

WebView에서 키보드 입력을 감지하고 액세서리 뷰를 표시하는 재사용 가능한 Swift 모듈입니다.

## 주요 기능

- 🎯 **WebView 입력 추적**: JavaScript를 통해 입력 필드 포커스/블러/변경 감지
- ⌨️ **키보드 상태 관리**: 키보드 표시/숨김 상태 자동 추적
- 🎨 **커스터마이징 가능**: 액세서리 뷰 디자인 자유롭게 변경 가능
- 🔄 **실시간 동기화**: 웹 입력과 네이티브 UI 실시간 연동
- 📱 **iOS 17+ 지원**: 최신 iOS 버전 완전 지원

## 구성 요소

### 1. InputTrackingMessageHandler
WebView에서 JavaScript 메시지를 받아 키보드 매니저에 전달하는 핸들러

### 2. KeyboardAccessoryManager
키보드 상태와 입력 텍스트를 관리하는 ObservableObject

### 3. KeyboardAccessoryView
키보드 위에 표시되는 액세서리 뷰 컴포넌트

### 4. WebViewInputTrackingScript
WebView에 주입할 JavaScript 코드 제공

## 설치 방법

1. `KeyboardAccessoryKit.swift` 파일을 프로젝트에 복사
2. SwiftUI 프로젝트에서 바로 사용 가능

## 사용 예제

### 기본 사용법

```swift
import SwiftUI
import WebKit

struct ContentView: View {
    @StateObject private var keyboardAccessoryManager = KeyboardAccessoryManager()
    
    var body: some View {
        ZStack {
            // 메인 WebView
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
        webView.navigationDelegate = context.coordinator
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // JavaScript 주입
        uiView.evaluateJavaScript(WebViewInputTrackingScript.defaultScript) { result, error in
            // 처리 완료
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // JavaScript 주입
            webView.evaluateJavaScript(WebViewInputTrackingScript.defaultScript) { result, error in
                // 완료
            }
        }
    }
}
```

### 고급 사용법

#### 액세서리 뷰 커스터마이징

```swift
// 색상 변경
KeyboardAccessoryView(manager: keyboardAccessoryManager)
    .background(Color.red)

// 완전한 커스텀 액세서리 뷰
struct CustomKeyboardAccessoryView: View {
    @ObservedObject var manager: KeyboardAccessoryManager
    
    var body: some View {
        HStack {
            Text("입력 중: \(manager.currentTypingText)")
                .foregroundColor(.white)
            Spacer()
            Button("완료") {
                // 처리
            }
        }
        .padding()
        .background(Color.purple)
    }
}
```

#### 키보드 매니저 확장

```swift
extension KeyboardAccessoryManager {
    func clearText() {
        self.currentTypingText = ""
    }
    
    func hasText() -> Bool {
        return !currentTypingText.isEmpty
    }
}
```

## API 문서

### KeyboardAccessoryManager

**Published Properties:**
- `isKeyboardVisible: Bool` - 키보드 표시 상태
- `keyboardHeight: CGFloat` - 키보드 높이
- `currentTypingText: String` - 현재 입력 중인 텍스트
- `inputPlaceholder: String` - 입력 필드 플레이스홀더

**Public Methods:**
- `updateTypingText(_:placeholder:)` - 타이핑 텍스트 업데이트
- `forceShowKeyboard()` - 키보드 강제 표시
- `hideKeyboard()` - 키보드 숨김

### InputTrackingMessageHandler

**Constructor:**
- `init(accessoryManager: KeyboardAccessoryManager)`

**Required Message Names:**
- `"inputChanged"` - 텍스트 변경 시
- `"inputFocused"` - 입력 필드 포커스 시  
- `"inputBlurred"` - 입력 필드 블러 시

### WebViewInputTrackingScript

**Static Properties:**
- `defaultScript: String` - 기본 JavaScript 코드

## 주의 사항

1. **WebView 설정**: `WKWebView`에 메시지 핸들러를 올바르게 등록해야 합니다
2. **JavaScript 주입**: 웹페이지 로딩 완료 후 JavaScript를 주입해야 합니다
3. **메모리 관리**: `InputTrackingMessageHandler`에서 `KeyboardAccessoryManager`를 weak 참조합니다

## 호환성

- **iOS**: 17.0+
- **Swift**: 5.0+
- **SwiftUI**: 지원
- **WebKit**: WKWebView 사용

## 라이센스

이 모듈은 MIT 라이센스 하에 배포됩니다.

## 문제 해결

### 키보드가 감지되지 않는 경우
1. 메시지 핸들러가 올바르게 등록되었는지 확인
2. JavaScript가 성공적으로 주입되었는지 확인
3. WebView에서 JavaScript가 활성화되어 있는지 확인

### 액세서리 뷰가 표시되지 않는 경우
1. `isKeyboardVisible`과 `keyboardHeight` 조건 확인
2. ZStack 구조에서 뷰 순서 확인
3. `offset` 값이 올바른지 확인

### 텍스트가 업데이트되지 않는 경우
1. JavaScript와 네이티브 코드 간 메시지 전달 확인
2. `@ObservedObject` 또는 `@StateObject` 사용 확인
3. 메인 스레드에서 UI 업데이트가 이루어지는지 확인

## 예제 프로젝트

이 README와 함께 제공되는 예제 코드를 참고하여 빠르게 시작할 수 있습니다. 