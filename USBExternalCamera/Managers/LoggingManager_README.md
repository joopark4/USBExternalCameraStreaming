# LoggingManager - 재사용 가능한 로깅 시스템

**완전히 재사용 가능한 iOS 로깅 매니저**

SwiftUI와 완벽 통합되며, 프로젝트 간 이식이 간편한 전문가급 로깅 솔루션입니다.

## 🎯 주요 특징

- ✅ **완전한 재사용성**: 하드코딩 없이 다양한 프로젝트에서 즉시 사용
- ✅ **자동 프로덕션 비활성화**: 릴리즈 빌드에서 컴파일러 레벨 완전 제거
- ✅ **SwiftUI 네이티브**: ObservableObject 기반 실시간 UI 업데이트
- ✅ **프로젝트별 프리셋**: 미디어, E-커머스, 소셜 앱 등 도메인별 최적화
- ✅ **성능 최적화**: Apple os.Logger 백엔드 + 최소 오버헤드
- ✅ **완벽한 UI 관리**: 디버그 전용 설정 인터페이스
- ✅ **개발자 친화적**: 직관적인 전역 함수와 상세한 디버깅 도구

## 📁 현재 프로젝트 구성

### 파일 구조
```
USBExternalCamera/
├── Managers/
│   ├── LoggingManager.swift           # 핵심 로깅 시스템
│   └── LoggingManager_README.md       # 이 문서
├── Views/
│   ├── LoggingSettingsView.swift      # SwiftUI 설정 화면
│   └── SidebarView.swift              # 설정 접근 버튼 (🔍)
├── ViewModels/
│   └── MainViewModel.swift            # 설정 화면 표시 로직
└── ContentView.swift                   # 메인 뷰 (시트 연결)
```

### 현재 적용된 설정
```swift
// 미디어 앱 프리셋 사용
Categories: camera, streaming, network, ui, data, settings, device, general, performance, error
Bundle ID: com.usbexternalcamera (자동 감지)
Access: SidebarView의 주황색 🔍 버튼 (디버그 빌드에만 표시)
```

## 🚀 빠른 시작 가이드

### 현재 프로젝트에서 사용법

```swift
// 기본 로깅 - 어디서든 사용 가능
logInfo("앱이 시작되었습니다", category: .general)
logDebug("카메라 초기화 중", category: .camera)
logWarning("네트워크 연결 불안정", category: .network)
logError("스트리밍 연결 실패", category: .streaming)

// 카테고리별 사용 예시
logInfo("USB 카메라 연결됨", category: .camera)
logDebug("RTMP 서버 연결 시도", category: .streaming)
logWarning("메모리 사용량 높음", category: .performance)
```

### 설정 화면 접근
1. **디버그 빌드에서**: 사이드바의 주황색 🔍 돋보기 아이콘 클릭
2. **프로그래밍**: `MainViewModel.showLoggingSettings()` 호출

## 📦 다른 프로젝트에 적용하기

### 단계 1: 파일 복사
```bash
# 최소 필요 파일
LoggingManager.swift → 새프로젝트/Managers/

# UI가 필요한 경우 추가
LoggingSettingsView.swift → 새프로젝트/Views/
```

### 단계 2: 프로젝트별 초기화

#### A. 미디어/카메라 앱
```swift
// AppDelegate.swift 또는 App.swift
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 미디어 앱용 설정 (camera, streaming 카테고리 포함)
        _ = LoggingManager.setupForMediaApp(bundleIdentifier: "com.yourcompany.yourapp")
        
        return true
    }
}

// 사용 예시
logInfo("카메라 앱 시작", category: .general)
logDebug("비디오 인코딩 설정", category: .streaming)
logInfo("외부 카메라 감지", category: .camera)
```

#### B. E-커머스 앱
```swift
// SwiftUI App
import SwiftUI

@main
struct ECommerceApp: App {
    init() {
        // E-커머스용 설정 (auth, payment, analytics 포함)
        _ = LoggingManager.setupForEcommerceApp()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// 사용 예시
logInfo("사용자 로그인 성공", category: .auth)
logWarning("결제 처리 지연", category: .payment)
logDebug("상품 클릭 이벤트", category: .analytics)
```

#### C. 소셜 미디어 앱
```swift
// 소셜 앱용 설정
_ = LoggingManager.setupForSocialApp()

// 사용 예시
logInfo("푸시 알림 수신", category: .push)
logDebug("위치 정보 업데이트", category: .location)
logError("이미지 업로드 실패", category: .storage)
```

#### D. 완전 커스텀 설정
```swift
// 금융 앱 예시
let financeCategories: [LoggingManager.Category] = [
    .general, .network, .security, .auth, .data, .analytics, .error
]

_ = LoggingManager.configure(
    bundleIdentifier: "com.bank.mobileapp",
    userDefaultsKey: "FinanceAppLogging",
    categories: financeCategories
)

// 사용 예시
logInfo("거래 승인", category: .security)
logWarning("의심스러운 접근", category: .auth)
logError("API 호출 실패", category: .network)
```

### 단계 3: UI 통합 (선택사항)

#### SwiftUI 앱에서
```swift
import SwiftUI

struct SettingsView: View {
    @State private var showingLoggingSettings = false
    
    var body: some View {
        NavigationView {
            List {
                #if DEBUG
                Button("🔧 개발자 로깅 설정") {
                    showingLoggingSettings = true
                }
                #endif
            }
        }
        .sheet(isPresented: $showingLoggingSettings) {
            LoggingSettingsView()
        }
    }
}
```

#### UIKit 앱에서
```swift
import UIKit

class SettingsViewController: UIViewController {
    
    @IBAction func showLoggingSettings(_ sender: UIButton) {
        #if DEBUG
        let hostingController = UIHostingController(rootView: LoggingSettingsView())
        present(hostingController, animated: true)
        #endif
    }
}
```

## 📋 전체 카테고리 가이드

### 🔧 기본 카테고리 (모든 앱)
| 카테고리 | 아이콘 | 용도 | 예시 |
|---------|-------|------|------|
| `general` | ℹ️ | 일반적인 로그 | 앱 시작/종료, 기본 상태 |
| `ui` | 🖼️ | UI 이벤트 | 화면 전환, 버튼 클릭, 애니메이션 |
| `network` | 🌐 | 네트워크 통신 | API 호출, 연결 상태, 응답 |
| `data` | 📊 | 데이터 처리 | 파싱, 저장, 캐싱, 동기화 |
| `settings` | ⚙️ | 설정 변경 | 사용자 설정, 앱 구성 |
| `device` | 📱 | 디바이스 상태 | 배터리, 메모리, 센서 |
| `performance` | ⚡ | 성능 관련 | 메모리 사용량, 실행 시간 |
| `error` | ❌ | 에러 및 예외 | 크래시, 예외 상황 |

### 🎯 도메인별 카테고리

#### 미디어 앱
| 카테고리 | 용도 | 예시 |
|---------|------|------|
| `camera` 📹 | 카메라 기능 | 권한, 설정, 캡처, USB 카메라 |
| `streaming` 🎥 | 스트리밍 | RTMP 연결, 인코딩, 전송 상태 |

#### E-커머스 앱
| 카테고리 | 용도 | 예시 |
|---------|------|------|
| `auth` 🔐 | 인증/인가 | 로그인, 토큰, 권한 확인 |
| `payment` 💳 | 결제 처리 | 주문, 결제, 영수증 |
| `analytics` 📈 | 사용자 분석 | 행동 추적, 전환율, A/B 테스트 |

#### 소셜 앱
| 카테고리 | 용도 | 예시 |
|---------|------|------|
| `push` 🔔 | 푸시 알림 | 메시지, 알림 설정 |
| `location` 📍 | 위치 서비스 | GPS, 체크인, 주변 검색 |
| `storage` 💾 | 파일 저장소 | 이미지, 동영상 업로드 |

#### 기타 유용한 카테고리
| 카테고리 | 용도 | 예시 |
|---------|------|------|
| `api` 🔗 | API 호출 | REST API, GraphQL |
| `security` 🛡️ | 보안 관련 | 암호화, 해킹 시도 감지 |

## 🎨 사용 패턴 및 베스트 프랙티스

### 1. 생명주기 로깅
```swift
class CameraManager {
    init() {
        logInfo("CameraManager 초기화", category: .camera)
    }
    
    func startCapture() {
        logDebug("카메라 캡처 시작", category: .camera)
        
        do {
            // 카메라 로직
            logInfo("카메라 캡처 성공", category: .camera)
        } catch {
            logError("카메라 캡처 실패: \(error)", category: .camera)
        }
    }
    
    deinit {
        logDebug("CameraManager 해제", category: .camera)
    }
}
```

### 2. 네트워크 호출 로깅
```swift
class APIService {
    func fetchUserData() async {
        logDebug("사용자 데이터 요청 시작", category: .network)
        
        do {
            let response = try await URLSession.shared.data(from: userURL)
            logInfo("사용자 데이터 수신 완료: \(response.data.count) bytes", category: .network)
            
            let user = try JSONDecoder().decode(User.self, from: response.data)
            logDebug("사용자 데이터 파싱 완료: \(user.name)", category: .data)
            
        } catch {
            logError("사용자 데이터 요청 실패: \(error)", category: .network)
        }
    }
}
```

### 3. 성능 모니터링
```swift
func performHeavyTask() {
    let startTime = Date()
    logDebug("무거운 작업 시작", category: .performance)
    
    // 작업 수행
    heavyComputation()
    
    let duration = Date().timeIntervalSince(startTime)
    logInfo("작업 완료: \(String(format: "%.2f", duration))초", category: .performance)
    
    if duration > 5.0 {
        logWarning("작업 시간이 예상보다 깁니다: \(duration)초", category: .performance)
    }
}
```

### 4. 조건부 상세 로깅
```swift
func processUserAction(_ action: UserAction) {
    logInfo("사용자 액션: \(action.type)", category: .ui)
    
    // 복잡한 디버깅 정보는 조건부로
    if LoggingManager.shared.getCurrentStatus().minimumLogLevel == .debug {
        let detailedInfo = generateDetailedActionInfo(action)
        logDebug("상세 액션 정보: \(detailedInfo)", category: .ui)
    }
}
```

## ⚙️ 고급 설정 및 커스터마이징

### 런타임 설정 변경
```swift
// 특정 상황에서만 네트워크 로깅 활성화
func enableNetworkDebugging() {
    LoggingManager.shared.setCategoryEnabled(.network, enabled: true)
    LoggingManager.shared.setMinimumLogLevel(.debug)
}

// A/B 테스트를 위한 조건부 로깅
func configureLoggingForExperiment(_ experimentGroup: String) {
    if experimentGroup == "detailed_logging" {
        LoggingManager.shared.setAllCategoriesEnabled(true)
        LoggingManager.shared.setTimestampEnabled(true)
        LoggingManager.shared.setFileInfoEnabled(true)
    }
}
```

### 프로덕션 환경 설정
```swift
func configureProductionLogging() {
    // 프로덕션에서는 에러만 로깅 (실제로는 DEBUG에서만 동작)
    LoggingManager.shared.setMinimumLogLevel(.error)
    LoggingManager.shared.setCategoryEnabled(.error, enabled: true)
    LoggingManager.shared.setAllCategoriesEnabled(false) // 나머지 비활성화
}
```

### 로그 레벨별 사용 가이드

#### 🔍 DEBUG - 상세한 개발 정보
```swift
logDebug("변수 상태: count=\(count), isEnabled=\(isEnabled)", category: .data)
logDebug("UI 업데이트 프레임: \(frame)", category: .ui)
logDebug("네트워크 헤더: \(headers)", category: .network)
```

#### ℹ️ INFO - 중요한 상태 변화
```swift
logInfo("사용자 로그인 성공", category: .auth)
logInfo("파일 다운로드 완료", category: .network)
logInfo("캐시 업데이트됨", category: .data)
```

#### ⚠️ WARNING - 주의가 필요한 상황
```swift
logWarning("API 응답 시간 지연: \(responseTime)ms", category: .network)
logWarning("메모리 사용량 높음: \(memoryUsage)MB", category: .performance)
logWarning("사용 중단 예정 기능 호출", category: .general)
```

#### ❌ ERROR - 즉시 해결이 필요한 문제
```swift
logError("데이터베이스 연결 실패: \(error)", category: .data)
logError("결제 처리 실패: \(paymentError)", category: .payment)
logError("치명적 오류로 인한 복구 시도", category: .error)
```

## 🚀 성능 최적화 가이드

### 1. 컴파일 시간 최적화
```swift
// 릴리즈에서는 아예 컴파일되지 않음
#if DEBUG
    logDebug("복잡한 계산 결과: \(expensiveCalculation())", category: .performance)
#endif

// 조건부 로깅으로 런타임 최적화
if LoggingManager.shared.isLoggingEnabled {
    let complexMessage = buildComplexLogMessage()
    logDebug(complexMessage, category: .data)
}
```

### 2. 메모리 최적화
```swift
// 큰 객체는 설명만 로깅
logDebug("대용량 데이터 처리 중: \(data.count) bytes", category: .data)
// 전체 데이터를 로깅하지 않음: logDebug("데이터: \(data)")

// 문자열 보간 최적화
let userID = user.id
logInfo("사용자 처리: \(userID)", category: .auth) // ✅ 좋음
// logInfo("사용자 처리: \(user.expensiveDescription)", category: .auth) // ❌ 피해야 함
```

### 3. 네트워크 로깅 최적화
```swift
func logNetworkResponse(_ response: HTTPURLResponse, data: Data) {
    // 응답 코드와 크기만 로깅
    logInfo("HTTP \(response.statusCode): \(data.count) bytes", category: .network)
    
    // 상세 헤더는 디버그에서만
    #if DEBUG
    if LoggingManager.shared.getCurrentStatus().enabledCategories.contains(.network) {
        logDebug("응답 헤더: \(response.allHeaderFields)", category: .network)
    }
    #endif
}
```

## 🔍 디버깅 및 문제 해결

### 일반적인 문제들

#### 1. 로그가 출력되지 않음
```swift
// 진단 코드
func diagnoseLogging() {
    let status = LoggingManager.shared.getCurrentStatus()
    print("=== 로깅 진단 ===")
    print("디버그 모드: \(status.isDebugMode)")
    print("전역 활성화: \(status.isGloballyEnabled)")
    print("실제 로깅 가능: \(status.isLoggingEnabled)")
    print("활성화된 카테고리: \(status.enabledCategories.map { $0.rawValue })")
    print("최소 로그 레벨: \(status.minimumLogLevel.rawValue)")
}
```

#### 2. 특정 카테고리만 활성화하기
```swift
// 네트워크 문제 디버깅을 위해 네트워크 로그만 활성화
LoggingManager.shared.setAllCategoriesEnabled(false)
LoggingManager.shared.setCategoryEnabled(.network, enabled: true)
LoggingManager.shared.setMinimumLogLevel(.debug)
```

#### 3. 프로덕션 로그 확인
```swift
// 실제 프로덕션에서는 동작하지 않지만, 테스트용
#if DEBUG
func simulateProductionLogging() {
    LoggingManager.shared.setMinimumLogLevel(.error)
    // 에러 레벨만 로깅되는지 확인
    logDebug("이 메시지는 보이지 않음") // 출력되지 않음
    logError("이 메시지는 보임", category: .error) // 출력됨
}
#endif
```

### Console.app에서 로그 확인하기

1. **macOS Console 앱 실행**
2. **디바이스 선택** (시뮬레이터 또는 실제 기기)
3. **필터 설정**:
   ```
   subsystem:com.usbexternalcamera
   category:camera
   ```
4. **로그 레벨 필터**:
   ```
   level:debug
   level:info
   level:error
   ```

### Xcode Console에서 확인
```swift
// 콘솔 출력이 활성화되어 있는지 확인
LoggingManager.shared.setConsoleOutputEnabled(true)

// 타임스탬프 추가로 시간 추적
LoggingManager.shared.setTimestampEnabled(true)
```

## 📦 패키지 관리 및 배포

### Swift Package로 만들기 (선택사항)
```swift
// Package.swift
// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LoggingManager",
    platforms: [.iOS(.v14), .macOS(.v11)],
    products: [
        .library(
            name: "LoggingManager",
            targets: ["LoggingManager"]),
    ],
    targets: [
        .target(
            name: "LoggingManager",
            dependencies: []),
    ]
)
```

### CocoaPods 지원
```ruby
# LoggingManager.podspec
Pod::Spec.new do |spec|
  spec.name         = "LoggingManager"
  spec.version      = "1.0.0"
  spec.summary      = "재사용 가능한 iOS 로깅 시스템"
  spec.homepage     = "https://github.com/yourname/LoggingManager"
  spec.license      = { :type => "MIT" }
  spec.author       = { "Your Name" => "your.email@example.com" }
  spec.source       = { :git => "https://github.com/yourname/LoggingManager.git", :tag => "#{spec.version}" }
  spec.source_files = "Sources/**/*.swift"
  spec.ios.deployment_target = "14.0"
  spec.swift_version = "5.7"
end
```

## 🎯 프로젝트별 실전 가이드

### USBExternalCamera 프로젝트 (현재)
```swift
// 실제 사용 중인 로깅 패턴
class LiveStreamService {
    func startStreaming() async {
        logInfo("🚀 YouTube RTMP 스트리밍 시작", category: .streaming)
        
        do {
            logDebug("RTMP 연결 설정", category: .streaming)
            try await setupRTMPConnection()
            
            logDebug("카메라 디바이스 연결", category: .camera)
            try await setupCameraDevices()
            
            logInfo("✅ 스트리밍 시작 완료", category: .streaming)
        } catch {
            logError("❌ 스트리밍 시작 실패: \(error)", category: .streaming)
        }
    }
}
```

### E-커머스 앱 예시
```swift
class ShoppingCartService {
    func addToCart(_ product: Product) {
        logInfo("상품 장바구니 추가: \(product.name)", category: .analytics)
        
        // 장바구니 로직
        cart.add(product)
        
        logDebug("장바구니 상태: \(cart.items.count)개 상품", category: .data)
        
        // 분석 이벤트
        logInfo("구매 의도 이벤트 발생", category: .analytics)
    }
    
    func checkout() async {
        logInfo("결제 프로세스 시작", category: .payment)
        
        do {
            logDebug("결제 정보 검증", category: .payment)
            try validatePaymentInfo()
            
            logDebug("결제 게이트웨이 호출", category: .network)
            let result = try await processPayment()
            
            logInfo("✅ 결제 성공: \(result.transactionId)", category: .payment)
        } catch {
            logError("❌ 결제 실패: \(error)", category: .payment)
        }
    }
}
```

### 소셜 미디어 앱 예시
```swift
class SocialFeedService {
    func uploadPhoto(_ image: UIImage) async {
        logInfo("사진 업로드 시작", category: .storage)
        
        do {
            logDebug("이미지 압축: \(image.size)", category: .data)
            let compressedData = compressImage(image)
            
            logDebug("서버 업로드 시작: \(compressedData.count) bytes", category: .network)
            let url = try await uploadToServer(compressedData)
            
            logInfo("✅ 사진 업로드 완료: \(url)", category: .storage)
            
            // 푸시 알림 전송
            logDebug("팔로워에게 알림 전송", category: .push)
            await notifyFollowers()
            
        } catch {
            logError("❌ 사진 업로드 실패: \(error)", category: .storage)
        }
    }
}
```

## 🔧 마이그레이션 가이드

### 기존 print 문에서
```swift
// Before
print("카메라 시작됨")
print("네트워크 연결 실패: \(error)")

// After  
logInfo("카메라 시작됨", category: .camera)
logError("네트워크 연결 실패: \(error)", category: .network)
```

### 기존 NSLog에서
```swift
// Before
NSLog("설정 저장: %@", settingName)

// After
logInfo("설정 저장: \(settingName)", category: .settings)
```

### 기존 os.log에서
```swift
// Before
import os.log
let logger = Logger(subsystem: "com.app", category: "network")
logger.info("API 호출")

// After
logInfo("API 호출", category: .network)
```

## 🔮 향후 확장 가능성

### 1. 원격 로깅 (선택적 확장)
```swift
// 확장 예시 - 원격 로그 수집
extension LoggingManager {
    func enableRemoteLogging(apiKey: String) {
        // Crashlytics, Sentry 등과 연동
    }
}
```

### 2. 로그 필터링 및 검색
```swift
// 확장 예시 - 로그 검색 기능
extension LoggingManager {
    func searchLogs(query: String, category: Category? = nil) -> [LogEntry] {
        // 로그 검색 구현
    }
}
```

### 3. 성능 메트릭 수집
```swift
// 확장 예시 - 성능 메트릭
extension LoggingManager {
    func logPerformanceMetric(_ metric: String, value: Double, category: Category = .performance) {
        // 성능 지표 수집
    }
}
```

---

## 📞 지원 및 기여

이 LoggingManager는 완전히 재사용 가능하며, 어떤 iOS 프로젝트에서든 즉시 사용할 수 있습니다.

### 기여 방법
1. 새로운 카테고리 제안
2. 성능 최적화 아이디어
3. UI/UX 개선 제안
4. 문서 개선

### 라이선스
MIT License - 자유롭게 사용, 수정, 배포 가능

---

**이제 LoggingManager를 사용하여 전문가급 로깅 시스템을 구축하세요!** 🚀

개발 효율성과 디버깅 경험이 크게 향상될 것입니다. 