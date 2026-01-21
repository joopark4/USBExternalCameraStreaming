# 📱 USB 외부 카메라 스트리밍 for iOS

<div align="center">

![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg?style=flat&logo=ios)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat&logo=swift)
![Xcode](https://img.shields.io/badge/Xcode-16.3+-blue.svg?style=flat&logo=xcode)
![HaishinKit](https://img.shields.io/badge/HaishinKit-2.0.8-red.svg?style=flat)

**USB 외부 카메라 지원 및 실시간 RTMP 스트리밍을 제공하는 전문 라이브 스트리밍 앱**

</div>

## 🎥 개요

USB External Camera는 UVC 호환 USB 외부 카메라를 사용하여 iPad 최적화된 라이브 스트리밍을 가능하게 하는 전문 iOS 애플리케이션입니다. HaishinKit 2.0.8로 구축되어 YouTube Live에 실시간 RTMP 스트리밍을 제공하며, iPad 기기용으로 특별히 설계된 성능 최적화된 480p/720p 품질 프리셋을 제공합니다.

### 💡 개발 계기

이 프로젝트는 **모바일 환경에서 외부 카메라를 활용하여 다양한 각도에서의 촬영과 모니터링**을 가능하게 하기 위해 시작되었습니다. 기존 모바일 스트리밍은 내장 카메라 위치에 제한되어 있지만, USB 외부 카메라를 활용함으로써 사용자들이 여러 카메라 앵글, 원격 위치 설정, 향상된 비디오 품질을 갖춘 전문가급 스트리밍 설정을 구현할 수 있으면서도 iPad 기기의 휴대성과 편의성을 유지할 수 있도록 하였습니다.

### ✨ 주요 특징

- 📹 **화면 캡처 스트리밍** - 카메라 프리뷰 + UI 오버레이 동시 스트리밍
- 🔌 **USB 카메라 지원** - UVC 호환 외부 카메라 완전 지원
- 📡 **실시간 RTMP** - HaishinKit 2.0.8으로 전문적인 스트리밍
- 🎛️ **고급 제어** - 비디오/오디오 품질, 해상도, 비트레이트 설정
- 📊 **실시간 통계** - 스트리밍 성능 실시간 모니터링
- 🎬 **YouTube Studio 통합** - 직접 스트림 관리를 위한 내장 YouTube Studio WebView
- ⌨️ **스마트 키보드 처리** - WebView 상호작용을 위한 최적화된 키보드 입력
- 🌍 **다국어 지원** - 한국어 및 영어 지원

## 🚀 기능

### 핵심 스트리밍 기능
- ✅ YouTube Live 실시간 RTMP 스트리밍
- ✅ 화면 캡처 스트리밍 (카메라 + UI 오버레이)
- ✅ AVFoundation과 USB 외부 카메라 통합
- ✅ 하드웨어 가속 H.264 비디오 인코딩
- ✅ AAC 인코딩을 통한 실시간 오디오 믹싱 및 처리

### 비디오 및 오디오
- 🎬 **해상도**: 480p, 720p 지원
- 🎵 **오디오**: 설정 가능한 비트레이트로 AAC 인코딩
- 📏 **프레임 레이트**: 30fps
- 🔧 **비트레이트 제어**: 설정 가능한 비트레이트 설정

### 고급 기능
- 📈 실시간 스트리밍 통계 및 모니터링
- 🔄 자동 재연결 및 오류 복구
- ⚙️ YouTube Live 최적화 프리셋 (480p/720p)
- 🎯 네트워크 품질 모니터링 및 비트레이트 조정
- 📱 iOS 기기 방향 지원
- ⚡ iPad 기기 성능 최적화
- 🎬 **YouTube Studio 통합** - 데스크톱 브라우저 호환성을 갖춘 네이티브 WebView
- ⌨️ **향상된 키보드 지원** - 더 나은 WebView 상호작용을 위한 커스텀 키보드 액세서리
- 📱 **적응형 레이아웃** - 다양한 화면 크기와 방향에 대응하는 반응형 레이아웃

## 📋 요구사항

- **iOS**: 17.0 이상
- **Xcode**: 16.3 이상
- **기기**: USB-C 포트가 있는 iPad (iPhone은 공식 지원하지 않음 - 테스트 단말 부족으로 검증되지 않음)
- **카메라**: UVC 호환 USB 외부 카메라
- **네트워크**: 안정적인 인터넷 연결 (480p/720p를 위한 최소 2-5 Mbps 업로드)
- **화면 방향**: **가로모드** (세로모드 개발 중) - 현재 가로 방향에 최적화됨

### 📷 테스트된 외부 카메라

**전문가용 카메라**
- ✅ **Sony a7M4** - UVC 지원 DSLR/미러리스 카메라
  - USB-C를 통해 최대 720p 지원
  - 뛰어난 저조도 성능
  - 전문가급 비디오 품질

**웹캠**  
- ✅ **Logitech C922x Pro** - 전문 스트리밍 웹캠
  - 30fps에서 네이티브 720p 지원
  - 내장 스테레오 마이크
  - 자동 초점 및 조명 보정

> **참고**: UVC 호환 카메라는 모두 작동해야 합니다. 위에 나열된 카메라들은 이 앱과 잘 작동하는 것으로 특별히 테스트되고 검증되었습니다.

### 📱 테스트된 iPad 기기

**iPad Pro 모델**
- ✅ **iPad Pro 12.9인치 (4세대)** - 2020년 모델
  - **칩**: A12Z Bionic (Neural Engine이 탑재된 8코어)
  - **USB 포트**: 고속 데이터 전송을 지원하는 USB-C
  - **메모리**: 6GB RAM
  - **디스플레이**: ProMotion(120Hz)이 적용된 12.9인치 Liquid Retina
  - **성능**: 하드웨어 가속을 통한 우수한 스트리밍 성능
  - **전력**: 대부분의 웹캠에 직접 전력 공급 가능, 전문가용 카메라는 전원 공급 허브 필요할 수 있음

> **참고**: 이 앱은 USB-C 포트가 있는 iPad Pro 모델에 최적화되어 있지만, iOS 17.0 이상을 실행하는 USB-C가 있는 모든 iPad에서 작동해야 합니다. 기기 성능에 따라 성능이 달라질 수 있습니다.

## 🛠 설치

### 복제 및 빌드

```bash
# 저장소 복제
git clone <repository-url>
cd USBExternalCamera-iOS

# Xcode에서 열기
open USBExternalCamera.xcodeproj

# 기기에서 빌드 및 실행
# 참고: 카메라 기능을 위해서는 실제 기기가 필요하며 시뮬레이터는 지원되지 않습니다
```

### 종속성

이 프로젝트는 다음 종속성과 함께 Swift Package Manager를 사용합니다:

- [HaishinKit](https://github.com/HaishinKit/HaishinKit.swift) (2.0.8) - RTMP 스트리밍 엔진
- [Inject](https://github.com/krzysztofzablocki/Inject) (1.5.2) - 개발용 핫 리로드
- [Logboard](https://github.com/shogo4405/Logboard) (2.5.0) - 고급 로깅

모든 종속성은 Xcode에서 자동으로 관리됩니다.

### 모듈화 아키텍처

이 프로젝트는 다른 프로젝트에서 재사용할 수 있는 **LiveStreamingCore** 모듈을 별도의 Swift Package로 포함합니다:

```
Modules/
└── LiveStreamingCore/     # 재사용 가능한 RTMP 스트리밍 모듈
    ├── Package.swift
    └── Sources/
        └── LiveStreamingCore/
            ├── LiveStreamSettings.swift
            ├── LoggingManager.swift
            ├── Models/
            ├── LiveStreaming/
            │   ├── Managers/
            │   ├── Types/
            │   └── Utilities/
            └── ...
```

**LiveStreamingCore** 모듈이 제공하는 기능:
- HaishinKit 기반 RTMP 스트리밍 기능
- YouTube Live 최적화 프리셋 및 설정
- 스트리밍 통계 및 진단
- 텍스트 오버레이 지원
- 연결 관리 및 오류 처리

자세한 사용 방법은 [LiveStreamingCore README](Modules/LiveStreamingCore/README.md)를 참조하세요.

## 🎯 빠른 시작

### 1. 하드웨어 설정
1. UVC 호환 USB 카메라를 iPad에 연결
2. USB-C 허브 또는 직접 USB-C 연결 사용
3. 요청 시 카메라 및 마이크 권한 허용

### 2. 스트리밍 설정
1. 앱을 열고 **라이브 스트림 설정**으로 이동
2. RTMP URL 및 스트림 키 설정:
   ```
   RTMP URL: rtmp://a.rtmp.youtube.com/live2/
   스트림 키: [YouTube 스트림 키]
   ```
3. 스트리밍 품질 프리셋 선택:
   - **480p**: 제한된 대역폭 또는 구형 기기에 최적
   - **720p**: 대부분의 스트리밍 시나리오에 권장

### 3. 스트리밍 시작
1. 카메라 목록에서 USB 카메라 선택
2. **화면 캡처 스트리밍 시작** 버튼 터치
3. 스트리밍 뷰에서 실시간 통계 모니터링

### YouTube Live 설정
1. [YouTube Studio](https://studio.youtube.com)로 이동
2. **만들기** → **라이브 방송** 클릭
3. 스트림 탭에서 **스트림 키** 복사
4. RTMP URL로 `rtmp://a.rtmp.youtube.com/live2/` 사용

### 🎬 YouTube Studio 통합

앱에서 내장된 **YouTube Studio WebView**를 통해 앱 전환 없이 직접 스트림을 관리할 수 있습니다:

**주요 기능:**
- **데스크톱 브라우저 호환성** - 모든 기능 접근을 위한 Safari 17.1 User-Agent 사용
- **완전한 YouTube Studio 접근** - 스트림 관리, 분석, 채팅 등 모든 기능 사용 가능
- **최적화된 레이아웃** - 더 나은 사용성을 위한 WebView 공간 최대화
- **스마트 키보드 처리** - 레이아웃 문제를 방지하는 커스텀 키보드 액세서리
- **로그인 상태 유지** - 앱 세션 간 로그인 상태 지속

## 🏗 아키텍처

이 앱은 SwiftUI와 MVVM 아키텍처, 그리고 모듈화된 설계를 따릅니다:

```
USBExternalCamera-iOS/
├── USBExternalCamera/           # 메인 앱
│   ├── Views/                   # SwiftUI 뷰
│   │   ├── LiveStream/         # 스트리밍 UI
│   │   ├── Camera/             # 카메라 선택 및 프리뷰
│   │   └── Settings/           # 설정 뷰
│   ├── ViewModels/             # MVVM 뷰모델
│   ├── Services/               # 비즈니스 로직
│   ├── Models/                 # 데이터 모델
│   ├── Managers/               # 시스템 매니저
│   └── Utils/                  # 유틸리티 및 확장
│
└── Modules/                     # 재사용 가능한 Swift Packages
    └── LiveStreamingCore/       # RTMP 스트리밍 모듈
        └── Sources/
            └── LiveStreamingCore/
                ├── Models/              # StreamStats, ConnectionInfo 등
                ├── LiveStreaming/
                │   ├── Managers/        # HaishinKitManager
                │   ├── Types/           # StreamingModels, Validation
                │   └── Utilities/       # 헬퍼
                └── ...
```

### 주요 구성 요소

- **HaishinKitManager**: 핵심 스트리밍 엔진 래퍼 (LiveStreamingCore 모듈)
- **CameraViewModel**: USB 카메라 관리
- **LiveStreamViewModel**: 스트리밍 상태 관리
- **LoggingManager**: 중앙화된 로깅 시스템 (LiveStreamingCore 모듈)
- **LiveStreamSettingsModel**: SwiftData 기반 영구 저장 설정 (LiveStreamingCore 모듈)

## 🎬 스트리밍 품질 프리셋

| 프리셋 | 해상도 | 비디오 비트레이트 | 오디오 비트레이트 | 프레임 레이트 |
|--------|---------|------------------|------------------|---------------|
| 저화질 (480p) | 480p | 1.5 Mbps | 128 kbps | 30 fps |
| 표준 (720p) | 720p | 2.5 Mbps | 128 kbps | 30 fps |

## 🐛 문제 해결

### 일반적인 문제

**카메라가 감지되지 않음**
- USB 카메라가 UVC 호환인지 확인
- USB-C 허브 또는 직접 연결 확인
- iOS 설정에서 카메라 권한 허용
- 참고: iPhone 지원은 테스트 단말 부족으로 공식적으로 검증되지 않음

**카메라 전력 문제 / 전력 부족**
- 일부 카메라(특히 Sony a7M4와 같은 전문가용 카메라)는 iPad가 제공할 수 있는 것보다 더 많은 전력이 필요할 수 있음
- 외부 전원에 연결되는 **전원 공급 USB-C 허브** 사용
- 카메라와 전원 공급장치를 모두 전원 공급 허브에 연결
- 허브가 카메라 모델에 충분한 전력 공급을 지원하는지 확인
- 카메라의 전원 표시등을 확인하여 적절한 전원 공급 상태 확인

**RTMP 연결 실패**
- RTMP URL 및 스트림 키 확인
- 네트워크 연결 확인
- 방화벽이 RTMP 트래픽을 허용하는지 확인

**YouTube Studio WebView 문제**
- **"구버전 브라우저" 메시지**: Safari 17.1 User-Agent로 자동 해결됨
- **로그인이 안 됨**: iOS 설정 > Safari > 고급 > 웹사이트 데이터에서 WebView 데이터 삭제
- **키보드가 내용을 가림**: 커스텀 키보드 액세서리가 자동으로 처리함
- **레이아웃이 멈춤**: 키보드 이벤트 중 UI 중단을 방지하는 적응형 레이아웃
- **기능이 작동하지 않음**: 향상된 WebView로 모든 데스크톱 YouTube Studio 기능 지원

**스트리밍 중 프레임 드롭**
- 비트레이트 설정 낮추기 (안정성을 위해 480p 사용)
- 더 안정적인 네트워크 연결로 전환
- 메모리 및 CPU 리소스 확보를 위해 다른 앱 종료
- iPad 기기의 최적 성능을 위해 720p 최대 사용

**성능 최적화**
- 1080p 옵션은 성능 최적화를 위해 현재 비활성화됨 (최대 720p)
- 느린 기기나 제한된 대역폭에는 480p 권장
- 사용 가능한 경우 하드웨어 가속 자동 활성화

**세로모드 / UI 레이아웃 문제**
- 이 앱은 현재 **가로모드만** 지원합니다
- 세로모드에서는 UI 레이아웃 문제가 발생할 수 있습니다 (세로모드 지원 개발 중)
- 현재는 앱 사용 전에 iPad를 가로 방향으로 회전시켜 주세요
- 스트리밍 성능은 현재 가로 방향에 최적화되어 있습니다

### 디버그 로그

다음 필터로 Xcode 콘솔 사용:
```
🎥        # 모든 스트리밍 로그
[RTMP]    # RTMP 연결 로그
[CAMERA]  # 카메라 시스템 로그
```

## 🔧 개발

### 소스에서 빌드

```bash
# Xcode 16.3+ 확인
xcode-select --install

# 복제 및 설정
git clone <repository-url>
cd USBExternalCamera-iOS

# 프로젝트 열기
open USBExternalCamera.xcodeproj
```

### 코드 스타일

- Swift API 설계 가이드라인 준수
- 모든 새로운 UI 구성 요소에 SwiftUI 사용
- async/await로 적절한 오류 처리 구현
- 디버깅을 위한 포괄적인 로깅 추가

### 테스트

```bash
# 기기용 빌드
xcodebuild -scheme USBExternalCamera -destination 'platform=iOS,name=Your-Device'

# 참고: 카메라 기능을 위해서는 실제 기기가 필요함
# 시뮬레이터 테스트는 UI 구성 요소에만 제한됨
```

### 🚧 향후 개발 계획

- **세로모드 지원**: 가로와 세로 방향을 모두 지원하도록 현재 개발 중
- **향상된 UI 레이아웃**: 다양한 화면 방향에 대한 반응형 디자인 개선
- **추가 카메라 기능**: 더 많은 카메라 제어 및 설정 옵션
- **성능 개선**: 다양한 iPad 모델에 대한 지속적인 최적화

## 📖 문서

### 프로젝트 문서
- [LiveStreamingCore 모듈 가이드](Modules/LiveStreamingCore/README.md) - 재사용 가능한 스트리밍 모듈 문서

### 외부 참고자료
- [HaishinKit 문서](https://github.com/HaishinKit/HaishinKit.swift)
- [YouTube Live Streaming API](https://developers.google.com/youtube/v3/live)
- [AVFoundation 가이드](https://developer.apple.com/documentation/avfoundation)
- [Apple - iPadOS 앱에서 외부 카메라 지원 (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10106/)
  - iPad에서 USB Video Class (UVC) 외부 카메라 지원에 대한 Apple 공식 가이드
- [Apple - 정지 및 비디오 미디어 캡처](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/04_MediaCapture.html)
  - AVFoundation을 사용한 미디어 캡처에 대한 상세 가이드

## 🙏 감사의 말

- [HaishinKit](https://github.com/HaishinKit/HaishinKit.swift) - 우수한 RTMP 스트리밍 프레임워크
- [YouTube Live API](https://developers.google.com/youtube/v3/live) - 라이브 스트리밍 플랫폼
- Apple의 [AVFoundation](https://developer.apple.com/documentation/avfoundation) - 카메라 및 미디어 프레임워크

## ⚠️ 면책 사항

이 프로젝트는 현재 개발 중이며 불완전한 문서나 미확인된 문제점이 있을 수 있습니다. 앱과 문서를 지속적으로 개선해 나가는 과정에서 여러분의 양해를 부탁드립니다. 문제를 발견하시거나 제안사항이 있으시면 언제든지 이슈를 등록하거나 프로젝트에 기여해 주시기 바랍니다.

**알려진 제한사항:**
- 모든 카메라 모델과 구성이 테스트되지 않았습니다
- 일부 예외 상황과 호환성 문제가 존재할 수 있습니다
- 특정 영역에서 문서가 불완전할 수 있습니다
- iPhone 지원은 테스트 기기 부족으로 공식적으로 검증되지 않았습니다

인내심과 지원에 감사드립니다! 🙏

---

<div align="center">

iOS 스트리밍을 위해 ❤️로 제작됨

</div> 
