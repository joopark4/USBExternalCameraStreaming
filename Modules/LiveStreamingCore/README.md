# LiveStreamingCore

iOS RTMP 라이브 스트리밍을 위한 Swift Package Manager 모듈입니다.

## 개요

LiveStreamingCore는 HaishinKit을 기반으로 RTMP 프로토콜을 사용한 라이브 스트리밍 기능을 제공합니다. YouTube Live, Twitch 등 RTMP를 지원하는 플랫폼에서 사용할 수 있습니다.

## 요구사항

- iOS 17.0+
- Swift 5.9+
- Xcode 15.0+

## 의존성

- [HaishinKit](https://github.com/shogo4405/HaishinKit.swift) - RTMP 스트리밍 라이브러리

## 설치

### Swift Package Manager

`Package.swift` 파일에 다음을 추가하세요:

```swift
dependencies: [
    .package(path: "../Modules/LiveStreamingCore")
    // 또는 원격 저장소 사용 시:
    // .package(url: "https://github.com/your-repo/LiveStreamingCore.git", from: "1.0.0")
]
```

타겟에 의존성을 추가합니다:

```swift
.target(
    name: "YourApp",
    dependencies: ["LiveStreamingCore"]
)
```

## 사용 방법

### 1. 모듈 임포트

```swift
import LiveStreamingCore
```

### 2. 스트리밍 설정

#### LiveStreamSettingsModel (SwiftData 지원)

```swift
// SwiftData를 사용하는 영구 저장 설정
let settings = LiveStreamSettingsModel()
settings.rtmpURL = "rtmp://a.rtmp.youtube.com/live2"
settings.streamKey = "your-stream-key"
settings.videoBitrate = 2500  // kbps
settings.videoWidth = 1280
settings.videoHeight = 720
settings.frameRate = 30
```

#### USBExternalCamera.LiveStreamSettings (Codable 지원)

```swift
// Codable을 사용하는 임시 설정
var settings = USBExternalCamera.LiveStreamSettings()
settings.rtmpURL = "rtmp://a.rtmp.youtube.com/live2"
settings.streamKey = "your-stream-key"
settings.videoBitrate = 2500
settings.videoWidth = 1280
settings.videoHeight = 720
```

### 3. YouTube 프리셋 사용

```swift
// 프리셋 적용
var settings = USBExternalCamera.LiveStreamSettings()
settings.applyYouTubeLivePreset(.hd720p)

// 현재 설정이 어떤 프리셋인지 감지
if let preset = settings.detectYouTubePreset() {
    print("현재 프리셋: \(preset.displayName)")
}
```

사용 가능한 프리셋:
- `.sd480p` - 848×480, 30fps, 1500kbps
- `.hd720p` - 1280×720, 30fps, 2500kbps
- `.fhd1080p` - 1920×1080, 30fps, 4500kbps
- `.custom` - 사용자 정의

### 4. HaishinKitManager 사용

```swift
// 매니저 인스턴스 생성
let manager = HaishinKitManager()

// 스트리밍 시작
Task {
    do {
        try await manager.startScreenCaptureStreaming(with: settings)
    } catch {
        print("스트리밍 시작 실패: \(error)")
    }
}

// 스트리밍 중지
Task {
    await manager.stopStreaming()
}
```

### 5. 연결 테스트

```swift
Task {
    let result = await manager.testConnection(to: settings)
    if result.isSuccessful {
        print("연결 성공! 지연시간: \(result.latency)ms")
    } else {
        print("연결 실패: \(result.message)")
    }
}
```

### 6. 스트리밍 통계 모니터링

```swift
// 데이터 전송 통계
let stats = manager.transmissionStats
print("비트레이트: \(stats.currentVideoBitrate) kbps")
print("FPS: \(stats.averageFrameRate)")
print("드롭된 프레임: \(stats.droppedFrames)")

// 스트림 통계
let streamStats = StreamStats()
streamStats.startStreaming()
streamStats.updateStats(
    videoBitrate: 2500,
    frameRate: 30,
    latency: 50
)
print("품질 상태: \(streamStats.qualityStatus.displayName)")
```

### 7. 진단 보고서

```swift
// 스트리밍 진단 실행
var report = StreamingDiagnosisReport()
report.calculateOverallScore()

print("전체 점수: \(report.overallScore)")
print("등급: \(report.overallGrade)")
print("권장사항: \(report.getRecommendation())")

// 개별 상태 확인
print("설정 유효: \(report.configValidation.isValid)")
print("네트워크 상태: \(report.networkStatus.isValid)")
```

## 주요 타입

### 설정 관련

| 타입 | 설명 |
|------|------|
| `LiveStreamSettingsModel` | SwiftData 기반 영구 저장 설정 |
| `USBExternalCamera.LiveStreamSettings` | Codable 지원 임시 설정 |
| `YouTubeLivePreset` | YouTube 표준 해상도 프리셋 |
| `ResolutionPreset` | 해상도 프리셋 |
| `QualityPreset` | 품질 프리셋 |

### 상태 및 통계

| 타입 | 설명 |
|------|------|
| `StreamStats` | 스트리밍 통계 정보 |
| `ConnectionInfo` | 연결 정보 |
| `DataTransmissionStats` | 데이터 전송 통계 |
| `ScreenCaptureStats` | 화면 캡처 통계 |

### 상태 열거형

| 타입 | 설명 |
|------|------|
| `LiveStreamStatus` | 스트리밍 상태 |
| `ConnectionStatus` | 연결 상태 |
| `ConnectionQuality` | 연결 품질 |
| `QualityStatus` | 품질 상태 |
| `NetworkQuality` | 네트워크 품질 |

### 진단 관련

| 타입 | 설명 |
|------|------|
| `StreamingDiagnosisReport` | 종합 진단 보고서 |
| `ConfigValidationResult` | 설정 검증 결과 |
| `NetworkValidationResult` | 네트워크 검증 결과 |
| `MediaMixerValidationResult` | 미디어 믹서 검증 결과 |

## 텍스트 오버레이

```swift
// 텍스트 오버레이 설정
var overlaySettings = TextOverlaySettings(
    text: "라이브 방송",
    fontSize: 24,
    textColor: .white,
    fontName: "System Bold"
)

// UIFont로 변환
let font = overlaySettings.uiFont

// UIColor로 변환
let color = overlaySettings.uiColor
```

## 로깅

```swift
// 로깅 매니저 사용
let logger = LoggingManager.shared

// 로그 레벨 설정
logger.setLogLevel(.debug)

// 로그 기록
logger.log("스트리밍 시작", level: .info, category: .streaming)
```

## 오류 처리

```swift
do {
    try await manager.startScreenCaptureStreaming(with: settings)
} catch let error as LiveStreamError {
    switch error {
    case .configurationError(let message):
        print("설정 오류: \(message)")
    case .connectionFailed(let message):
        print("연결 실패: \(message)")
    case .streamingFailed(let message):
        print("스트리밍 실패: \(message)")
    default:
        print("기타 오류: \(error)")
    }
}
```

## 권한 요청

앱에서 다음 권한이 필요합니다. `Info.plist`에 추가하세요:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>라이브 스트리밍을 위해 마이크 접근이 필요합니다.</string>
<key>NSCameraUsageDescription</key>
<string>라이브 스트리밍을 위해 카메라 접근이 필요합니다.</string>
```

## 라이선스

이 모듈은 프로젝트 라이선스를 따릅니다. HaishinKit은 BSD-3-Clause 라이선스를 따릅니다.
