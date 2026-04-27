# Architecture Notes

이 문서는 코드베이스를 처음 만지는 사람이 알아야 할 **아키텍처 의사결정 / 잠재 이슈** 를 모아두는
간단한 참고서다. 변경 가이드(`CLAUDE.md`) 와 사용자 매뉴얼(`README.md`) 과는 다르게, 여기에는
"왜 이렇게 됐는지" 와 "어디가 깨지기 쉬운지" 가 들어간다.

## 1. Settings 영속화 정책

라이브 스트리밍 설정은 **세 개 저장소** 에 분산되어 있다. 보안 / 휘발성 / 스키마 진화 가능성에
따라 의도적으로 나뉘었다.

### 1.1 저장소별 책임

| 저장소 | 위치 | 무엇이 담기는가 | 비고 |
|---|---|---|---|
| **Keychain** | `LiveStreamingCore.KeychainManager` | `streamKey` (YouTube Stream Key) | sensitive secret. 디바이스 백업에 평문으로 들어가지 않게 보호. |
| **UserDefaults** | `LiveStream.*` 키 prefix (`UserDefaults.standard`) | `rtmpURL`, `streamTitle`, `videoBitrate`, `videoWidth`, `videoHeight`, `frameRate`, `streamOrientation`, `savedAt`, `Debug.*` flags | non-sensitive 사용자 환경설정. 마이그레이션 가벼움. |
| **SwiftData** | `LiveStreamSettingsModel` (LSC), `ModelContainer` | future-proofed 영속 모델 — 현재 컨테이너만 만들어두고 본격 사용은 보류 | 나중에 멀티 프로필 / 히스토리 도입 시 채택. |

### 1.2 어떤 데이터를 어디에 둘 것인가

새 설정 항목을 추가할 때 분기 기준:

```
[데이터가 secret 인가?]
   yes → Keychain (KeychainManager.saveStreamKey 또는 saveString(_, forAccount:))
   no
    └─ [구조가 단순(scalar/string) + 단일 값인가?]
         yes → UserDefaults (`LiveStream.<항목명>` 키)
         no  → SwiftData 모델 추가 (multi-profile 나 nested data 일 때)
```

### 1.3 주의해야 할 마이그레이션 패턴

`HaishinKitManager+Protocol.swift:97` 에 sensitive 마이그레이션 예시가 있다:

```swift
// 과거 빌드는 streamKey 를 UserDefaults 에 평문으로 저장.
// 새 빌드 첫 실행 시 자동으로 Keychain 으로 이동시키고 UserDefaults 에서 제거.
if let legacyStreamKey = defaults.string(forKey: "LiveStream.streamKey"),
   !legacyStreamKey.isEmpty {
    _ = KeychainManager.shared.saveStreamKey(legacyStreamKey)
    defaults.removeObject(forKey: "LiveStream.streamKey")
}
```

새 sensitive 데이터를 도입할 때는 항상 이 lazy migration 패턴을 따른다 — 사용자가 한 번도 새
빌드를 켜지 않아도 옛 평문은 그대로 남으므로, 처음 켤 때 자동 이전 + 흔적 삭제.

### 1.4 알려진 가려운 부분

- **SwiftData 컨테이너만 있고 실제 사용은 보류** — `ContentView.swift:29` 에서
  `ModelContainer(for: LiveStreamSettingsModel.self)` 를 만들지만, 실제 read/write 는
  UserDefaults 가 한다. 컨테이너 생성 비용을 매번 지불하면서 실효 가치가 없는 상태. 본격 도입할
  때 모델 마이그레이션 정책을 함께 정해야 한다.
- **프리뷰 디버그 플래그가 `UserDefaults.standard` 에 직접 박혀있음** —
  `CameraPreviewUIView.swift:18` 의 `Debug.previewDebugLoggingEnabled`. 같은 prefix 가 아니라
  나중에 grep 으로 찾기 어려움. 새로 추가할 때는 `LiveStream.debug.*` 로 통일하는 게 좋다.

## 2. 알려진 잠재 이슈 (Instruments 실측 권장)

다음 두 항목은 **LiveStreamingCore 측 코드 경로** 라 본 레포에서 직접 패치할 수 없지만, 영향이
큰 경로라 여기에 기록한다.

### 2.1 H3 — Frame backpressure race (LSC `HaishinKitManager+Debug.swift`)

**현상.** `enqueueManualFrame` → `transmitPreparedSampleBuffer` → `videoCodecWorkaround.sendFrameWithWorkaround`
경로가 **모두 `@MainActor`** 에서 직렬 처리된다. backpressure 메커니즘이 없어서, VideoToolbox 가
인코딩으로 잠시 느려지면 main actor 가 막힌다. 1080p30 송출에서 SwiftUI 렌더 stutter 와 함께
발생하면 hitch 가 보일 수 있다.

**검증 방법.**
- Instruments → Time Profiler / Hangs 템플릿
- `transmitPreparedSampleBuffer` 의 main thread time 추적
- Hangs 마커가 송출 시작 직후 / 카메라 전환 직후 집중되는지 확인

**권장 변경 (LSC PR 후보).**
- `enqueueManualFrame` 안에 "직전 frame 이 still in flight 이면 새 frame drop + drop counter 증가"
  guard 추가. 큐 깊이 1 backpressure 정책.
- `transmitPreparedSampleBuffer` 의 인코딩 호출만 `Task.detached` 로 분리, main actor 는 큐잉 만
  담당.
- 드랍 통계는 이미 있는 `recordScreenCaptureDrop(reason:)` 로 흘려보내면 됨.

**App 단 완화책.** 이미 적용된 것:
- `CameraScreenCapture.getCaptureIntervalForResolution()` 가 해상도별로 capture cadence 를 늘림
- `CameraScreenCapture.swift` 의 capture timer 가 main actor isolated 라 자동으로 직렬 처리됨

추가로 가능한 옵션:
- 직전 frame 의 enqueue 가 미완료면 (boolean flag) 새 frame skip — 단, LSC API 가 in-flight 상태
  를 노출하지 않으므로 LSC 변경이 선행되어야 깨끗함.

### 2.2 H4 — `mixer.screen.size` 갱신이 1회성 (LSC `HaishinKitManager+ScreenCapture.swift:33`)

**현상.** `mixer.screen.size` 는 `setupScreenCaptureMediaMixer()` 안에서 stream 시작 직후 한 번만
설정된다. 하지만 `currentSettings` 는 다음 경로에서 stream 도중 변경될 수 있다:
- `HaishinKitManager+Monitoring.swift:279` — adaptive quality monitoring 이 해상도/비트레이트를
  내려서 quality 를 떨어뜨림
- `HaishinKitManager+Protocol.swift:196,208` — 외부 setter 호출
- `HaishinKitManager+ManualFrame.swift:858` — manual frame path

이 setter 들은 직후 `applyStreamSettings()` 를 호출해 RTMPStream / VideoCodec 측 인코딩 해상도는
갱신한다. 하지만 **`mixer.screen.size` 는 갱신하지 않는다.** 즉 mixer 는 stale 한 합성 해상도로
프레임을 만들고, 인코더는 새 해상도로 잡아서 차이만큼 letterbox / pillarbox / 잘림이 발생할 수
있다.

**검증 방법.**
- 송출 시작 → adaptive quality 가 발동될 만큼 네트워크를 의도적으로 좁힘 (Network Link Conditioner
  의 EDGE 프리셋)
- YouTube Studio 의 송출 화면에서 aspect ratio 가 어긋나는지 확인
- `screenCaptureStats.recordPreprocessTime` 로그에서 letterbox 변화 흔적 추적

**권장 변경 (LSC PR 후보).**
- `applyStreamSettings()` 안에서도 `mixer.screen.size` 를 새 `videoWidth × videoHeight` 로 동기화.
- 또는 `currentSettings` 의 didSet 에 mixer 동기화를 묶어 단일 진입점으로 통일.
- 시작 시점의 `setupScreenCaptureMediaMixer` 의 size 설정 코드는 새 동기 path 와 중복되지 않게
  정리.

**App 단 완화책.** 본 앱은 송출 중 해상도 변경 UI 를 의도적으로 잠가두므로
(`LiveStreamSettingsView` 의 disable 가드), 사용자가 명시적으로 바꾸는 경로는 막혀있다. 단, LSC
의 adaptive quality 가 자체적으로 내릴 수 있으므로 H4 발동 가능성은 남아있다.

## 3. Capture / Streaming wiring 한 줄 요약

- 카메라 캡처: `CameraSessionManager` 가 `AVCaptureSession` + `AVCaptureVideoDataOutput`. 프레임은
  fan-out 으로 등록된 `CameraFrameDelegate` 들에게 전달.
- 스트리밍 매니저(`LSC.HaishinKitManager`) 가 `CameraFrameDelegate` 를 채택해서 fan-out 의 한
  consumer 로 등록됨 (`CameraViewModel.connectToStreaming`).
- 화면 캡처는 별도 path — `CameraScreenCapture` 가 SwiftUI 뷰 트리를 `UIGraphicsImageRenderer` 로
  렌더해 `enqueueManualFrame(_:)` 에 넘김.

## 4. 변경 시 영향 범위 빠른 체크 (요약)

> 자세한 체크리스트는 `CLAUDE.md` "변경 시 최소 체크리스트" 참고. 여기서는 자주 잊는 항목만.

- 권한 흐름 변경 — `MainViewModel.UIState` 분기 + `PermissionViewModel` computed forward 가 같이
  움직여야 함
- 설정 키 추가 — 어느 저장소에 둘지 위 1.2 의 분기 기준으로 결정
- 송출 해상도 / 방향 관련 — 시작 시 path (`performScreenCaptureStreamingStart`) 와 stream 도중
  setter (`updateSettings`) 양쪽 모두 검토
