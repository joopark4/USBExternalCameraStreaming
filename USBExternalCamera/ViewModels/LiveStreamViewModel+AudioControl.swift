import AVFoundation
import CoreMedia
import Foundation
import LiveStreamingCore

extension LiveStreamViewModel {
  // MARK: - Public Audio Control

  func toggleMicrophoneMute() {
    setMicrophoneMuted(!isMicrophoneMuted)
  }

  func setMicrophoneMuted(_ muted: Bool) {
    guard isMicrophoneMuted != muted else { return }

    isMicrophoneMuted = muted
    audioPeakDiagnosticMessage = ""

    if muted {
      stopAudioPeakHealthCheckTask()
      resetMicrophonePeakDisplay()
    } else if status == .streaming {
      resetAudioPeakDiagnostics()
      startAudioPeakHealthCheckTask()
    }

    Task { [weak self] in
      await self?.applyMicrophoneMuteStateToStreamingPipeline()
    }
  }

  func suspendIdleMicrophonePeakMonitoringForStreaming() {
    isIdleMicrophonePeakMonitoringSuspended = true
    stopIdleMicrophonePeakMonitoring()
  }

  func resumeIdleMicrophonePeakMonitoringAfterStreaming() {
    isIdleMicrophonePeakMonitoringSuspended = false
    restartIdleMicrophonePeakMonitoringIfNeeded()
  }

  func startIdleMicrophonePeakMonitoringIfNeeded() {
    guard !isIdleMicrophonePeakMonitoringSuspended else { return }
    guard status != .streaming else { return }

    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      break

    case .notDetermined:
      Task { [weak self] in
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
          guard let self else { return }
          if granted {
            self.startIdleMicrophonePeakMonitoringIfNeeded()
          } else {
            self.audioPeakDiagnosticMessage = NSLocalizedString(
              "mic_permission_denied_error",
              comment: "마이크 권한이 필요합니다. 설정에서 허용해주세요."
            )
          }
        }
      }
      return

    case .denied, .restricted:
      audioPeakDiagnosticMessage = NSLocalizedString(
        "mic_permission_denied_error",
        comment: "마이크 권한이 필요합니다. 설정에서 허용해주세요."
      )
      return

    @unknown default:
      audioPeakDiagnosticMessage = NSLocalizedString(
        "mic_permission_unknown_status_error",
        comment: "마이크 권한 상태를 확인할 수 없습니다."
      )
      return
    }

    guard configureAudioSessionForIdleMonitoring() else {
      if !isMicrophoneMuted {
        audioPeakDiagnosticMessage = NSLocalizedString(
          "audio_peak_diag_no_input",
          comment: "오디오 입력 감지 안됨. 마이크 연결/선택 확인"
        )
      }
      return
    }

    if idleMicrophonePeakMonitor == nil {
      idleMicrophonePeakMonitor = IdleMicrophonePeakMonitor { [weak self] level, decibels in
        guard let self else { return }
        Task { @MainActor [weak self] in
          self?.updateMicrophonePeak(level: level, decibels: decibels)
        }
      }
    }

    guard let monitor = idleMicrophonePeakMonitor else { return }
    guard !monitor.isRunning else { return }

    if monitor.start() {
      if !audioPeakDiagnosticMessage.isEmpty {
        audioPeakDiagnosticMessage = ""
      }
      logDebug("🎙️ 대기 상태 오디오 피크 모니터 시작", category: .streaming)
    } else {
      if !isMicrophoneMuted {
        audioPeakDiagnosticMessage = NSLocalizedString(
          "audio_peak_diag_no_input",
          comment: "오디오 입력 감지 안됨. 마이크 연결/선택 확인"
        )
      }
      logWarning("대기 상태 오디오 피크 모니터 시작 실패", category: .streaming)
    }
  }

  func stopIdleMicrophonePeakMonitoring() {
    guard let monitor = idleMicrophonePeakMonitor, monitor.isRunning else { return }
    monitor.stop()
    logDebug("🎙️ 대기 상태 오디오 피크 모니터 중지", category: .streaming)
  }

  func restartIdleMicrophonePeakMonitoringIfNeeded() {
    guard !isIdleMicrophonePeakMonitoringSuspended else { return }
    guard status != .streaming else { return }
    stopIdleMicrophonePeakMonitoring()
    startIdleMicrophonePeakMonitoringIfNeeded()
  }

  func attachAudioPeakObserverIfNeeded(retryCount: Int = 20) async {
    // 스트림 준비 전에 호출될 수 있으므로 짧게 retry.
    // 이전에는 `liveStreamService.getRTMPStream()?.addOutput(observer)` 로 직접 붙였지만,
    // 그 경로는 `HaishinKit` / `RTMPHaishinKit` 타입을 app layer 로 노출시켰다.
    // LSC 의 `attachAudioPeakObserver(onPeak:)` 가 옵저버 인스턴스까지 내부에 보관하므로,
    // 성공 여부는 `isAudioPeakObserverAttached` 로 확인한다.
    guard liveStreamService.getRTMPStream() != nil else {
      guard retryCount > 0 else { return }
      if retryCount == 20 || retryCount == 1 {
        logDebug("🎵 오디오 피크 옵저버 대기 중... 남은 재시도: \(retryCount)", category: .streaming)
      }
      try? await Task.sleep(nanoseconds: 300_000_000)
      await attachAudioPeakObserverIfNeeded(retryCount: retryCount - 1)
      return
    }

    await liveStreamService.attachAudioPeakObserver { [weak self] level, decibels in
      Task { @MainActor [weak self] in
        self?.updateMicrophonePeak(level: level, decibels: decibels)
      }
    }

    if liveStreamService.isAudioPeakObserverAttached {
      resetAudioPeakDiagnostics()
      startAudioPeakHealthCheckTask()
      logDebug("🎵 오디오 피크 옵저버 연결 완료", category: .streaming)
    }
  }

  func detachAudioPeakObserver() async {
    stopAudioPeakHealthCheckTask()
    await liveStreamService.detachAudioPeakObserver()
    logDebug("🎵 오디오 피크 옵저버 해제 완료", category: .streaming)
  }

  func startMicrophonePeakDecayTimerIfNeeded() {
    guard audioPeakDecayTimer == nil else { return }

    let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }

        if self.isMicrophoneMuted {
          self.resetMicrophonePeakDisplay()
          return
        }

        let decayedLevel = self.microphonePeakLevel * 0.86
        if decayedLevel < 0.001 {
          self.microphonePeakLevel = 0
          self.microphonePeakDecibels = -80
        } else {
          self.microphonePeakLevel = decayedLevel
          self.microphonePeakDecibels = max(-80, min(0, 20 * log10(max(decayedLevel, 0.0001))))
        }
      }
    }
    timer.tolerance = 0.02
    RunLoop.main.add(timer, forMode: .common)
    audioPeakDecayTimer = timer
  }

  func resetMicrophonePeakDisplay() {
    microphonePeakLevel = 0
    microphonePeakDecibels = -80
    if status != .streaming {
      audioPeakDiagnosticMessage = ""
      audioPeakSampleCount = 0
      audioPeakLastSampleAt = nil
    }
  }

  // MARK: - Internal Audio Pipeline

  fileprivate func updateMicrophonePeak(level: Float, decibels: Float) {
    audioPeakSampleCount += 1
    audioPeakLastSampleAt = Date()
    if !audioPeakDiagnosticMessage.isEmpty {
      audioPeakDiagnosticMessage = ""
    }

    guard !isMicrophoneMuted else {
      microphonePeakLevel = 0
      microphonePeakDecibels = -80
      return
    }

    let normalized = level.clamped(to: 0...1)
    if status == .streaming {
      let eased = max(normalized, microphonePeakLevel * 0.82)
      microphonePeakLevel = eased
    } else {
      microphonePeakLevel = normalized
    }
    microphonePeakDecibels = decibels.clamped(to: -80...0)
  }

  func applyMicrophoneMuteStateToStreamingPipeline() async {
    let muted = isMicrophoneMuted
    let serviceApplied = await liveStreamService.setMicrophoneMuted(muted)

    logDebug(
      "🎚️ [AUDIO MUTE] requested=\(muted), service=\(serviceApplied)",
      category: .streaming)
  }

  private func configureAudioSessionForIdleMonitoring() -> Bool {
    let session = AVAudioSession.sharedInstance()

    do {
      try session.setCategory(
        .playAndRecord,
        mode: .measurement,
        options: [.defaultToSpeaker, .allowBluetoothHFP]
      )

      let targetPort: AVAudioSessionPortDescription?
      if selectedMicrophoneInputID == MicrophoneInputOption.automaticID {
        targetPort = nil
      } else {
        targetPort = (session.availableInputs ?? []).first(where: { $0.uid == selectedMicrophoneInputID })
      }

      try session.setPreferredInput(targetPort)
      try session.setPreferredIOBufferDuration(0.005)
      try session.setActive(true)

      activeMicrophoneInputName =
        session.currentRoute.inputs.first?.portName
        ?? NSLocalizedString("microphone_input_none", comment: "입력 없음")
      return true
    } catch {
      logWarning("대기 상태 오디오 세션 구성 실패: \(error.localizedDescription)", category: .streaming)
      return false
    }
  }

  private func resetAudioPeakDiagnostics() {
    audioPeakSampleCount = 0
    audioPeakLastSampleAt = nil
    audioPeakDiagnosticMessage = ""
  }

  private func stopAudioPeakHealthCheckTask() {
    audioPeakHealthCheckTask?.cancel()
    audioPeakHealthCheckTask = nil
  }

  private func startAudioPeakHealthCheckTask() {
    stopAudioPeakHealthCheckTask()

    audioPeakHealthCheckTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      guard !Task.isCancelled else { return }

      await MainActor.run { [weak self] in
        guard let self else { return }
        guard self.status == .streaming else { return }
        guard !self.isMicrophoneMuted else { return }
        guard self.audioPeakSampleCount == 0 else { return }

        let routeInput = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
          ?? NSLocalizedString("microphone_input_none", comment: "입력 없음")
        let selectedInput = self.selectedMicrophoneInputDisplayName

        self.audioPeakDiagnosticMessage = NSLocalizedString(
          "audio_peak_diag_no_input", comment: "오디오 입력 감지 안됨. 마이크 연결/선택 확인")
        logWarning(
          "오디오 피크 샘플 미수신: route=\(routeInput), selected=\(selectedInput), muted=\(self.isMicrophoneMuted)",
          category: .streaming)
      }
    }
  }
}

// NOTE: `StreamAudioPeakOutputObserver` 는 LiveStreamingCore 로 이관되었습니다
// (`AudioPeakStreamOutput` + `HaishinKitManager.attachAudioPeakObserver(onPeak:)`).
// app layer 에는 더 이상 `StreamOutput` / `StreamConvertible` 타입 참조가 없고
// `import HaishinKit` / `import RTMPHaishinKit` 도 불필요합니다.

final class IdleMicrophonePeakMonitor: @unchecked Sendable {
  private let onPeak: @Sendable (Float, Float) -> Void
  private let lock = NSLock()
  private var previousLevel: Float = 0
  private var engine: AVAudioEngine?

  private(set) var isRunning: Bool = false

  init(onPeak: @escaping @Sendable (Float, Float) -> Void) {
    self.onPeak = onPeak
  }

  func start() -> Bool {
    stop()

    let newEngine = AVAudioEngine()
    let inputNode = newEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.channelCount > 0 else { return false }

    lock.lock()
    previousLevel = 0
    lock.unlock()

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let self else { return }
      let (level, decibels) = AudioPeakMeter.measurePeak(from: buffer)

      self.lock.lock()
      let smoothedLevel = max(level, self.previousLevel * 0.55)
      self.previousLevel = smoothedLevel
      self.lock.unlock()

      self.onPeak(smoothedLevel, decibels)
    }

    do {
      newEngine.prepare()
      try newEngine.start()
      engine = newEngine
      isRunning = true
      return true
    } catch {
      inputNode.removeTap(onBus: 0)
      engine = nil
      isRunning = false
      return false
    }
  }

  func stop() {
    guard let engine else {
      isRunning = false
      return
    }

    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    self.engine = nil
    isRunning = false

    lock.lock()
    previousLevel = 0
    lock.unlock()
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
