# 🎥 USB External Camera - iOS 라이브 스트리밍 앱

> **HaishinKit 2.0.8 기반 실시간 RTMP 스트리밍 애플리케이션**  
> USB 외장 카메라와 iPhone 카메라를 사용하여 YouTube Live 등의 플랫폼으로 고품질 라이브 스트리밍을 제공합니다.

## 📋 프로젝트 개요

### 🎯 주요 기능
- ✅ **HaishinKit 2.0.8** - 실제 RTMP 스트리밍 구현 완료
- ✅ **USB 외장 카메라 지원** - AVFoundation 기반 카메라 연동
- ✅ **스크린 캡처 스트리밍** - 카메라 + UI 오버레이를 포함한 전체 화면 스트리밍
- ✅ **실시간 스트리밍 제어** - 스트리밍 시작/중지, 실시간 모니터링
- ✅ **YouTube Live 연동** - RTMP URL 및 스트림 키 지원
- ✅ **고급 설정** - 비디오/오디오 품질, 해상도, 비트레이트 제어
- ✅ **실시간 통계** - 네트워크 품질, 프레임 드롭, 전송률 모니터링
- ✅ **다국어 지원** - 한국어/영어 지원

### 🏗 아키텍처
```
USBExternalCamera/
├── Services/
│   └── LiveStreaming/
│       ├── Protocols/
│       │   └── LiveStreamServiceProtocol.swift  # 스트리밍 서비스 인터페이스
│       ├── Managers/
│       │   ├── HaishinKitManager.swift          # HaishinKit 2.0.8 핵심 구현
│       │   ├── NetworkMonitoringManager.swift   # 네트워크 모니터링
│       │   ├── StreamingStatsManager.swift      # 스트리밍 통계 관리
│       │   └── StreamingLogger.swift            # 스트리밍 전용 로거
│       ├── Models/                              # 스트리밍 관련 데이터 모델
│       ├── Types/                               # 스트리밍 타입 정의
│       ├── Utilities/                           # 스트리밍 유틸리티
│       ├── Factory/                             # 스트리밍 팩토리 패턴
│       └── Help/                                # 스트리밍 도움말
├── ViewModels/
│   ├── LiveStreamViewModel.swift                # 스트리밍 뷰모델 (스크린 캡처 전용)
│   ├── LiveStreamViewModelStub.swift            # 스트리밍 뷰모델 스텁 (테스트용)
│   ├── CameraViewModel.swift                    # 카메라 관리 뷰모델
│   ├── MainViewModel.swift                      # 메인 앱 뷰모델
│   └── PermissionViewModel.swift                # 권한 관리 뷰모델
├── Views/
│   ├── LiveStream/
│   │   ├── LiveStreamView.swift                 # 메인 스트리밍 UI
│   │   ├── LiveStreamControlView.swift          # 스트리밍 제어 UI
│   │   ├── LiveStreamSettingsView.swift         # 스트리밍 설정 UI
│   │   └── StreamingLogView.swift               # 스트리밍 로그 UI
│   ├── Camera/
│   │   ├── CameraPreviewView.swift              # 카메라 미리보기 UI
│   │   └── CameraListView.swift                 # 카메라 선택 UI
│   ├── Settings/                                # 설정 관련 UI
│   └── Common/                                  # 공통 UI 컴포넌트
├── Models/
│   ├── LiveStreamSettings.swift                 # 스트리밍 설정 모델
│   ├── CameraDevice.swift                       # 카메라 디바이스 모델
│   ├── StreamStats.swift                        # 스트리밍 통계 모델
│   ├── ConnectionInfo.swift                     # 연결 정보 모델
│   └── PermissionManager.swift                  # 권한 관리 모델
├── Managers/
│   ├── CameraSessionManager.swift               # 카메라 세션 관리
│   ├── LoggingManager.swift                     # 앱 전역 로깅
│   └── DeviceOrientationManager.swift           # 디바이스 방향 관리
├── ContentView.swift                            # 메인 앱 뷰
├── USBExternalCameraApp.swift                   # 앱 진입점
└── Assets.xcassets/                             # 앱 리소스
```

## 🔧 기술 스택

### 📱 iOS Framework
- **SwiftUI** - 모던 UI 프레임워크
- **AVFoundation** - 카메라 캡처 및 미디어 처리
- **SwiftData** - 설정 데이터 영구 저장 (Core Data의 최신 대안)
- **Combine** - 리액티브 프로그래밍
- **Network** - 네트워크 상태 모니터링
- **CoreMedia** - 미디어 프레임 처리

### 📡 스트리밍 기술
- **HaishinKit 2.0.8** - RTMP 실시간 스트리밍 핵심 엔진
- **MediaMixer** - HaishinKit의 미디어 믹싱 컴포넌트
- **RTMPConnection/RTMPStream** - RTMP 프로토콜 연결 및 스트림 관리
- **CVPixelBuffer** - 실시간 비디오 프레임 버퍼 처리
- **CMSampleBuffer** - Core Media 프레임 샘플 처리

### 🎨 UI/UX 기술
- **MVVM 패턴** - Model-View-ViewModel 아키텍처
- **@MainActor** - 메인 스레드 안전성 보장
- **async/await** - 현대적 비동기 프로그래밍
- **ObservableObject** - SwiftUI 상태 관리

### 🔧 개발 도구
- **Swift Package Manager** - 의존성 관리
- **Xcode 16.3+** - 개발 환경
- **iOS 17.0+** - 최소 지원 버전

### 🎥 지원 해상도 & 품질
| 프리셋 | 해상도 | 비디오 비트레이트 | 오디오 비트레이트 | 프레임률 |
|--------|--------|------------------|------------------|----------|
| 저화질 | 720p | 1.5 Mbps | 64 kbps | 30 fps |
| 표준 | 1080p | 2.5 Mbps | 128 kbps | 30 fps |
| 고화질 | 1080p | 4.5 Mbps | 192 kbps | 60 fps |
| 최고화질 | 4K | 8 Mbps | 256 kbps | 60 fps |

## 🆕 최신 업데이트 (v2.0.0)

### 🎯 스크린 캡처 스트리밍 시스템
기존의 일반 카메라 스트리밍을 대체하여 **스크린 캡처 기반 스트리밍**으로 전환:

#### ✨ 새로운 기능
- **📱 전체 화면 캡처**: 카메라 미리보기 + UI 오버레이를 함께 스트리밍
- **🎤 통합 오디오**: 마이크 오디오를 포함한 실시간 오디오 스트리밍
- **⚡ 30fps 안정적 출력**: CVPixelBuffer 기반 최적화된 프레임 처리
- **🔄 실시간 동기화**: 카메라 뷰모델과 스트리밍 매니저 자동 연결

#### 🗑️ 제거된 기능
- 이전 일반 카메라 스트리밍 버튼 (사이드바)
- 기존 `startStreaming(with captureSession:)` 메서드
- 카메라 전환 델리게이트 및 관련 UI
- 중복된 스트리밍 제어 버튼들

#### 🔧 리팩토링된 구조
```swift
// 이전: 일반 카메라 스트리밍 + 스크린 캡처 스트리밍 혼재
// 현재: 스크린 캡처 스트리밍 전용

// HaishinKitManager - 핵심 변경사항
class HaishinKitManager {
    // ✅ 유지: 스크린 캡처 스트리밍
    func startScreenCaptureStreaming(settings: LiveStreamSettings) async throws
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer) async
    
    // ❌ 제거: 일반 스트리밍 메서드들
    // func startStreaming(with settings: LiveStreamSettings) async throws
    // func setupCamera(), setupAudio()
    // func detachCamera(), detachAudio()
}

// LiveStreamViewModel - 스크린 캡처 전용
class LiveStreamViewModel {
    // ✅ 핵심 기능: 스크린 캡처 스트리밍만 지원
    func startScreenCaptureStreaming() async
    func stopStreaming() async
    
    // ❌ 제거: 일반 스트리밍 관련 프로퍼티 및 메서드
    // var streamControlButtonText, isStreamControlButtonEnabled 등
}
```

#### 🔄 개선된 아키텍처
1. **단일 스트리밍 방식**: 스크린 캡처 스트리밍으로 통일
2. **자동 컴포넌트 연결**: MainViewModel에서 CameraViewModel ↔ HaishinKitManager 자동 연결
3. **최적화된 오디오 처리**: 스크린 캡처 전용 오디오 설정 (`setupAudioForScreenCapture`)
4. **향상된 프레임 전달**: `RTMPStream.append()` 직접 호출로 성능 개선

### 🐛 해결된 주요 이슈
- **❌ 오디오 누락**: 스크린 캡처 모드에서 오디오 설정 완전 제거 → **✅ 해결**: `setupAudioForScreenCapture()` 추가
- **❌ 프레임 전달 문제**: MediaMixer 의존성 → **✅ 해결**: RTMPStream 직접 전달 방식
- **❌ 컴포넌트 연결 누락**: 수동 연결 → **✅ 해결**: MainViewModel 자동 초기화

## 🚀 설치 및 설정

### 1️⃣ 시스템 요구사항
- **iOS 17.0+**
- **Xcode 16.3+**
- **iPhone/iPad** with USB-C or Lightning port
- **USB 외장 카메라** (UVC 호환)

### 2️⃣ 프로젝트 설정
```bash
# 프로젝트 클론
git clone <repository-url>
cd USBExternalCamera-iOS

# Xcode에서 프로젝트 열기
open USBExternalCamera.xcodeproj
```

### 3️⃣ 의존성 (자동 설치)
프로젝트는 Swift Package Manager를 사용하여 다음 의존성들을 자동으로 관리합니다:
- **HaishinKit**: `v2.0.8` - RTMP 스트리밍
- **Inject**: `v1.5.2` - 개발용 Hot Reload
- **Logboard**: `v2.5.0` - HaishinKit 로깅

## 📺 YouTube Live 스트리밍 설정

### 1️⃣ YouTube Studio에서 스트림 키 생성
1. [YouTube Studio](https://studio.youtube.com) 접속
2. **만들기** → **라이브 스트리밍 시작**
3. **스트림** 탭에서 스트림 키 복사

### 2️⃣ 앱에서 설정
```swift
// 기본 YouTube RTMP 설정
RTMP URL: rtmp://a.rtmp.youtube.com/live2/
스트림 키: [YouTube에서 복사한 키]
```

### 3️⃣ 권장 설정
- **해상도**: 1920x1080 (1080p)
- **비디오 비트레이트**: 2500 kbps
- **오디오 비트레이트**: 128 kbps
- **프레임률**: 30 fps
- **키프레임 간격**: 2초

## 💻 주요 코드 구현

### 🎥 스크린 캡처 스트리밍 구현
```swift
// HaishinKitManager.swift - Examples 패턴 적용한 최신 구현
@MainActor
public class HaishinKitManager: ObservableObject, HaishinKitManagerProtocol {
    
    /// MediaMixer (Examples 패턴)
    private lazy var mixer = MediaMixer(
        multiCamSessionEnabled: false, 
        multiTrackAudioMixingEnabled: false, 
        useManualCapture: true
    )
    
    /// StreamSwitcher (Examples 패턴)
    private let streamSwitcher = StreamSwitcher()
    
    // 화면 캡처 모드로 스트리밍 시작
    public func startScreenCaptureStreaming(with settings: LiveStreamSettings) async throws {
        logger.info("🎬 화면 캡처 스트리밍 모드 시작", category: .streaming)
        
        guard !isStreaming else {
            throw LiveStreamError.streamingFailed("이미 스트리밍이 진행 중입니다")
        }
        
        // 1. 화면 캡처 전용 MediaMixer 설정
        try await setupScreenCaptureMediaMixer()
        
        // 2. 스트림 설정 (카메라 없이)
        let preference = StreamPreference(
            rtmpURL: settings.rtmpURL,
            streamKey: settings.streamKey
        )
        await streamSwitcher.setPreference(preference)
        
        // 3. MediaMixer를 RTMPStream에 연결
        if let stream = await streamSwitcher.stream {
            await mixer.addOutput(stream)
            currentRTMPStream = stream
        }
        
        // 4. 오디오 설정 (마이크 포함)
        try await setupAudioForScreenCapture()
        
        // 5. 스트리밍 시작
        try await streamSwitcher.startStreaming()
        
        isStreaming = true
        isScreenCaptureMode = true
    }
    
    // 수동 프레임 전달 (30fps 화면 캡처)
    public func sendManualFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let sampleBuffer = createSampleBuffer(from: pixelBuffer) else { return }
        
        Task { @MainActor in
            if let stream = self.currentRTMPStream {
                // RTMPStream에 직접 비디오 프레임 전달
                await stream.append(sampleBuffer)
            } else {
                // 백업: MediaMixer 사용
                await self.mixer.append(sampleBuffer)
            }
        }
    }
    
    // 스크린 캡처 전용 오디오 설정
    private func setupAudioForScreenCapture() async throws {
        let audioDevice = AVCaptureDevice.default(for: .audio)
        try await mixer.attachAudio(audioDevice, track: 0)
        logger.info("✅ 화면 캡처용 오디오 설정 완료", category: .system)
    }
}
```

### 📊 스크린 캡처 통계 모니터링
```swift
// LiveStreamViewModel.swift - 실시간 통계
@MainActor
class LiveStreamViewModel: ObservableObject {
    @Published var streamingStats = StreamingStats()
    
    func updateStreamingStats() async {
        guard let manager = haishinKitManager,
              let streamInfo = await manager.getCurrentStreamInfo() else { return }
        
        // 스크린 캡처 전용 통계 업데이트
        streamingStats.videoBitrate = streamInfo.actualVideoBitrate
        streamingStats.audioBitrate = streamInfo.actualAudioBitrate
        streamingStats.frameRate = streamInfo.actualFrameRate
        streamingStats.screenCaptureFrames = streamInfo.totalFrames
        
        // 스크린 캡처 성능 모니터링
        if streamInfo.droppedFrames > 0 {
            logger.warning("⚠️ Screen capture frame drop: \(streamInfo.droppedFrames)")
        }
    }
}
```

## 🐛 디버깅 및 문제해결

### 🎯 로그 확인 방법
Xcode 콘솔에서 다음 필터를 사용하여 로그를 확인하세요:
```
🎥          # 모든 스트리밍 관련 로그
[RTMP]      # RTMP 연결 및 스트리밍
[NETWORK]   # 네트워크 상태 및 품질
[GENERAL]   # 일반 서비스 로그
```

### 📋 예상 로그 출력
```
🎥 [RTMP] [🚀] Starting YouTube RTMP streaming process
🎥 [RTMP] [📡] RTMP URL: rtmp://a.rtmp.youtube.com/live2/
🎥 [RTMP] [🔑] Stream Key: ✅ YouTube Key: 3ry5-q5q***
🎥 [RTMP] [✅] YouTube RTMP connection established!
🎥 [RTMP] [🎉] YouTube Live streaming started successfully!
🎥 [RTMP] [📊] 실시간 송출 데이터:
   📹 비디오: 2500 kbps (설정: 2500 kbps)
   🔊 오디오: 128 kbps (설정: 128 kbps)
   🎬 프레임률: 30.0 fps (설정: 30 fps)
   📶 네트워크 상태: 좋음
```

### 🔧 일반적인 문제와 해결방법

| 문제 | 증상 | 해결 방법 |
|------|------|-----------|
| **RTMP 연결 실패** | `Connection timeout (30s)` | - YouTube 스트림 키 확인<br>- 네트워크 연결 상태 점검<br>- 방화벽 설정 확인 |
| **카메라 인식 안됨** | `Camera unavailable` | - USB 카메라 UVC 호환성 확인<br>- iOS 카메라 권한 허용<br>- Lightning-USB 어댑터 확인 |
| **스트리밍 끊김** | `Connection lost detected` | - 네트워크 안정성 확인<br>- 비트레이트 설정 낮추기<br>- 자동 재연결 활성화 |
| **프레임 드롭** | `Frame drop detected: X개` | - 비트레이트 낮추기<br>- 해상도 줄이기<br>- 프레임률 30fps로 설정 |

### 🚨 긴급 상황 대응
1. **스트리밍 중단 시**: 앱 재시작 → 설정 재확인 → 재연결
2. **네트워크 문제**: WiFi → 셀룰러 전환 또는 그 반대
3. **카메라 문제**: USB 연결 해제 → 재연결 → 앱 재시작

## 📈 성능 최적화

### 🎯 권장 네트워크 환경
- **WiFi**: 5GHz 대역, 최소 10 Mbps 업로드
- **5G/LTE**: 안정적인 신호 강도 (3바 이상)
- **업로드 속도**: 설정 비트레이트의 1.5배 이상

### ⚙️ 품질별 권장 설정
```swift
// 저화질 (안정성 우선)
videoWidth: 1280, videoHeight: 720
videoBitrate: 1500, audioBitrate: 64
frameRate: 30

// 표준 (권장)
videoWidth: 1920, videoHeight: 1080
videoBitrate: 2500, audioBitrate: 128
frameRate: 30

// 고화질 (고성능 네트워크 필요)
videoWidth: 1920, videoHeight: 1080
videoBitrate: 4500, audioBitrate: 192
frameRate: 60
```

## 🔄 향후 개발 계획

### ✅ 완료된 기능
- [x] HaishinKit 2.0.8 완전 통합
- [x] 실시간 RTMP 스트리밍
- [x] **스크린 캡처 스트리밍** - 카메라 + UI 오버레이 동시 스트리밍
- [x] YouTube Live 연동
- [x] USB 외장 카메라 지원
- [x] 실시간 통계 모니터링
- [x] 다국어 지원 (한국어/영어)
- [x] **레거시 코드 정리** - 이전 카메라 스트리밍 시스템 제거
- [x] **아키텍처 단순화** - 단일 스트리밍 방식으로 통일

### 🚀 개발 중인 기능
- [ ] **화면 녹화 저장** - 로컬 MP4 파일 저장
- [ ] **멀티 카메라 지원** - 여러 카메라 동시 사용
- [ ] **고급 오디오 믹싱** - 마이크 + 시스템 오디오
- [ ] **스트림 자동 복구** - 연결 끊김 시 자동 재연결

### 🎯 계획된 기능
- [ ] **Twitch/Facebook Live 지원**
- [ ] **SRT 프로토콜 지원**
- [ ] **클라우드 설정 동기화**
- [ ] **스트리밍 일정 관리**

---

## 📞 지원 및 문의

### 🐛 버그 리포트
개발 초기 버전이라 참고 정도로만 확인해 주세요.
이슈 공유 시 최소 사용 환경 정보:
1. **iOS 버전** 및 **기기 모델**
2. **앱 버전** (Build Number 포함)
3. **사용 중인 카메라** 모델명
4. **RTMP 서버** (YouTube/Twitch 등)
5. **Xcode 콘솔 로그** (🎥 필터링)
6. **네트워크 환경** (WiFi/5G/LTE)
7. **재현 단계**

### 📚 참고 자료
- [HaishinKit 공식 문서](https://github.com/HaishinKit/HaishinKit.swift)
- [YouTube Live Streaming API](https://developers.google.com/youtube/v3/live)
- [AVFoundation 개발 가이드](https://developer.apple.com/documentation/avfoundation)

---

**🎉 USB External Camera로 프로페셔널한 라이브 스트리밍을 경험해보세요!**