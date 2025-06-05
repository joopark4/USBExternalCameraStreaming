# 🎥 USB External Camera - iOS 라이브 스트리밍 앱

> **HaishinKit 2.0.8 기반 실시간 RTMP 스트리밍 애플리케이션**  
> USB 외장 카메라와 iPhone 카메라를 사용하여 YouTube Live 등의 플랫폼으로 고품질 라이브 스트리밍을 제공합니다.

## 📋 프로젝트 개요

### 🎯 주요 기능
- ✅ **HaishinKit 2.0.8** - 실제 RTMP 스트리밍 구현 완료
- ✅ **USB 외장 카메라 지원** - AVFoundation 기반 카메라 연동
- ✅ **실시간 스트리밍 제어** - 스트리밍 시작/중지, 실시간 모니터링
- ✅ **YouTube Live 연동** - RTMP URL 및 스트림 키 지원
- ✅ **고급 설정** - 비디오/오디오 품질, 해상도, 비트레이트 제어
- ✅ **실시간 통계** - 네트워크 품질, 프레임 드롭, 전송률 모니터링
- ✅ **다국어 지원** - 한국어/영어 지원

### 🏗 아키텍처
```
USBExternalCamera/
├── Services/
│   └── LiveStreamService.swift          # HaishinKit 2.0.8 실제 구현
├── ViewModels/
│   ├── LiveStreamViewModel.swift        # MVVM 스트리밍 뷰모델
│   ├── CameraViewModel.swift           # 카메라 관리 뷰모델
│   ├── MainViewModel.swift             # 메인 앱 뷰모델
│   └── PermissionViewModel.swift       # 권한 관리 뷰모델
├── Views/
│   ├── LiveStreamControlView.swift     # 스트리밍 컨트롤 UI
│   ├── LiveStreamSettingsView.swift    # 스트리밍 설정 UI
│   ├── CameraPreviewView.swift         # 카메라 미리보기
│   └── CameraListView.swift            # 카메라 선택 UI
├── Models/                             # SwiftData 모델
├── Managers/                           # 추가 매니저 클래스들
└── Assets.xcassets/                    # 앱 리소스
```

## 🔧 기술 스택

### 📱 iOS Framework
- **SwiftUI** - 모던 UI 프레임워크
- **AVFoundation** - 카메라 캡처 및 미디어 처리
- **SwiftData** - 설정 데이터 영구 저장
- **Combine** - 리액티브 프로그래밍

### 📡 스트리밍 기술
- **HaishinKit 2.0.8** - RTMP 실시간 스트리밍
- **MediaMixer** - 카메라 데이터 처리 및 믹싱
- **RTMPConnection/RTMPStream** - 실제 RTMP 연결 및 스트림

### 🎥 지원 해상도 & 품질
| 프리셋 | 해상도 | 비디오 비트레이트 | 오디오 비트레이트 | 프레임률 |
|--------|--------|------------------|------------------|----------|
| 저화질 | 720p | 1.5 Mbps | 64 kbps | 30 fps |
| 표준 | 1080p | 2.5 Mbps | 128 kbps | 30 fps |
| 고화질 | 1080p | 4.5 Mbps | 192 kbps | 60 fps |
| 최고화질 | 4K | 8 Mbps | 256 kbps | 60 fps |

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

### 🎥 HaishinKit 2.0.8 실제 구현
```swift
// LiveStreamService.swift - 실제 HaishinKit 구현
class LiveStreamService: ObservableObject {
    private var rtmpConnection: RTMPConnection?
    private var rtmpStream: RTMPStream?
    private var mediaMixer: MediaMixer?
    
    func startStreaming(with captureSession: AVCaptureSession, 
                       settings: LiveStreamSettings) async throws {
        // 1. 실제 HaishinKit 객체 생성
        rtmpConnection = RTMPConnection()
        rtmpStream = RTMPStream(connection: rtmpConnection!)
        mediaMixer = MediaMixer()
        
        // 2. RTMP 서버 연결
        _ = try await rtmpConnection!.connect(settings.rtmpURL)
        
        // 3. 스트림 설정 적용
        var videoSettings = await rtmpStream!.videoSettings
        videoSettings.videoSize = CGSize(width: 1920, height: 1080)
        videoSettings.bitRate = 2500 * 1000 // 2.5 Mbps
        await rtmpStream!.setVideoSettings(videoSettings)
        
        // 4. 스트리밍 시작
        _ = try await rtmpStream!.publish(settings.streamKey)
    }
}
```

### 📊 실시간 모니터링
```swift
// 실시간 통계 수집 및 표시
func updateStreamingStats() {
    let streamInfo = await getStreamInfo(from: rtmpStream!)
    
    // UI 업데이트
    currentStats.videoBitrate = streamInfo.actualVideoBitrate
    currentStats.audioBitrate = streamInfo.actualAudioBitrate
    currentStats.frameRate = streamInfo.actualFrameRate
    currentStats.droppedFrames = streamInfo.droppedFrames
    
    // 성능 문제 감지
    if streamInfo.droppedFrames > 0 {
        logWarning("⚠️ 프레임 드롭 감지: \(streamInfo.droppedFrames)개")
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
- [x] YouTube Live 연동
- [x] USB 외장 카메라 지원
- [x] 실시간 통계 모니터링
- [x] 다국어 지원 (한국어/영어)

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
이슈 발생 시 다음 정보를 포함하여 GitHub Issues에 등록해주세요:
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