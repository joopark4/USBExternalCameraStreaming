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

    if muted {
      resetMicrophonePeakDisplay()
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
      audioPeakDiagnosticMessage = NSLocalizedString(
        "audio_peak_diag_no_input",
        comment: "오디오 입력 감지 안됨. 마이크 연결/선택 확인"
      )
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
      audioPeakDiagnosticMessage = NSLocalizedString(
        "audio_peak_diag_no_input",
        comment: "오디오 입력 감지 안됨. 마이크 연결/선택 확인"
      )
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
    guard let stream = liveStreamService.getRTMPStream() else {
      guard retryCount > 0 else { return }
      if retryCount == 20 || retryCount == 1 {
        logDebug("🎵 오디오 피크 옵저버 대기 중... 남은 재시도: \(retryCount)", category: .streaming)
      }
      try? await Task.sleep(nanoseconds: 300_000_000)
      await attachAudioPeakObserverIfNeeded(retryCount: retryCount - 1)
      return
    }

    if audioPeakObserver == nil {
      audioPeakObserver = StreamAudioPeakOutputObserver { [weak self] level, decibels in
        guard let self else { return }
        Task { @MainActor [weak self] in
          self?.updateMicrophonePeak(level: level, decibels: decibels)
        }
      }
    }

    if let observer = audioPeakObserver {
      await stream.addOutput(observer)
      resetAudioPeakDiagnostics()
      startAudioPeakHealthCheckTask()
      logDebug("🎵 오디오 피크 옵저버 연결 완료", category: .streaming)
    }
  }

  func detachAudioPeakObserver() async {
    stopAudioPeakHealthCheckTask()
    guard let observer = audioPeakObserver else { return }
    guard let stream = liveStreamService.getRTMPStream() else { return }
    await stream.removeOutput(observer)
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
    guard !isMicrophoneMuted else { return }

    let normalized = level.clamped(to: 0...1)
    if status == .streaming {
      let eased = max(normalized, microphonePeakLevel * 0.82)
      microphonePeakLevel = eased
    } else {
      microphonePeakLevel = normalized
    }
    microphonePeakDecibels = decibels.clamped(to: -80...0)
    audioPeakSampleCount += 1
    audioPeakLastSampleAt = Date()
    if !audioPeakDiagnosticMessage.isEmpty {
      audioPeakDiagnosticMessage = ""
    }
  }

  func applyMicrophoneMuteStateToStreamingPipeline() async {
    let muted = isMicrophoneMuted

    let attachmentApplied = await applyMicrophoneMuteViaAudioTrackAttachment(muted)
    let mixerApplied = await applyMicrophoneMuteViaMixer(muted)
    let bitrateApplied = await enforceStreamAudioBitrate()

    // 믹서 반영이 실패한 경우에만 오디오 세션 카테고리 fallback 적용
    // (playback/playAndRecord 강제 전환은 라우트 불안정의 부작용이 있어 최후 수단으로만 사용)
    if !(attachmentApplied || mixerApplied) {
      _ = applyMicrophoneMuteViaAudioSessionCategory(muted)
    }

    logDebug(
      "🎚️ [AUDIO MUTE] requested=\(muted), attachment=\(attachmentApplied), mixer=\(mixerApplied), bitrate=\(bitrateApplied)",
      category: .streaming)
  }

  private func applyMicrophoneMuteViaAudioSessionCategory(_ muted: Bool) -> Bool {
    let session = AVAudioSession.sharedInstance()

    do {
      if muted {
        try session.setCategory(
          .playback,
          mode: .default,
          options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )
      } else {
        try session.setCategory(
          .playAndRecord,
          mode: status == .streaming ? .videoRecording : .measurement,
          options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
      }

      try session.setActive(true)
      return true
    } catch {
      logWarning("오디오 세션 기반 음소거 반영 실패: \(error.localizedDescription)", category: .streaming)
      return false
    }
  }

  private func applyMicrophoneMuteViaMixer(_ muted: Bool) async -> Bool {
    guard let haishinKitManager = liveStreamService as? HaishinKitManager else {
      return false
    }
    return await haishinKitManager.codexSetMicrophoneMutedWithMixer(muted)
  }

  private func applyMicrophoneMuteViaAudioTrackAttachment(_ muted: Bool) async -> Bool {
    guard let haishinKitManager = liveStreamService as? HaishinKitManager else {
      return false
    }
    return await haishinKitManager.codexSetMicrophoneMutedByAudioAttachment(muted)
  }

  private func enforceStreamAudioBitrate() async -> Bool {
    guard let stream = liveStreamService.getRTMPStream() else {
      return false
    }

    var audioSettings = await stream.audioSettings
    let targetBitrate = max(64_000, settings.audioBitrate * 1_000)

    if audioSettings.bitRate != targetBitrate {
      audioSettings.bitRate = targetBitrate
      await stream.setAudioSettings(audioSettings)
    }

    return true
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

private extension HaishinKitManager {
  @MainActor
  func codexSetMicrophoneMutedWithMixer(_ muted: Bool) async -> Bool {
    guard let mixer = codexResolveMediaMixer() else {
      logWarning("마이크 음소거 실패: MediaMixer 접근 불가", category: .streaming)
      return false
    }

    var settings = await mixer.audioMixerSettings
    let targetTracks = Set<UInt8>([0, settings.mainTrack])
    for track in targetTracks {
      var trackSettings = settings.tracks[track] ?? .default
      trackSettings.isMuted = muted
      trackSettings.volume = muted ? 0 : 1
      settings.tracks[track] = trackSettings
    }

    if settings.isMuted != muted {
      settings.isMuted = muted
    }
    await mixer.setAudioMixerSettings(settings)

    let applied = await mixer.audioMixerSettings
    let appliedOnAllTracks = targetTracks.allSatisfy { track in
      (applied.tracks[track] ?? .default).isMuted == muted
    }
    let isApplied = applied.isMuted == muted && appliedOnAllTracks
    if !isApplied {
      let trackStateSummary = targetTracks
        .map { track in "\(track):\((applied.tracks[track] ?? .default).isMuted)" }
        .joined(separator: ",")
      logWarning(
        "마이크 음소거 상태 반영 실패: requested=\(muted), applied=\(applied.isMuted), tracks=\(trackStateSummary)",
        category: .streaming)
    }
    return isApplied
  }

  @MainActor
  func codexSetMicrophoneMutedByAudioAttachment(_ muted: Bool) async -> Bool {
    guard let mixer = codexResolveMediaMixer() else {
      return false
    }

    let settings = await mixer.audioMixerSettings
    let targetTracks = Set<UInt8>([0, settings.mainTrack]).sorted()

    if muted {
      var applied = false
      for track in targetTracks {
        do {
          try await mixer.attachAudio(nil, track: track)
          applied = true
        } catch {
          logWarning("오디오 attach 기반 음소거 처리 실패(track=\(track)): \(error.localizedDescription)", category: .streaming)
        }
      }
      return applied
    }

    // 음소거 해제 시에는 먼저 오디오 디바이스를 확보한 뒤 재연결한다.
    guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
      logWarning("오디오 attach 기반 음소거 해제 실패: 기본 오디오 디바이스를 찾을 수 없음", category: .streaming)
      return false
    }

    var applied = false
    for track in targetTracks {
      do {
        try await mixer.attachAudio(audioDevice, track: track)
        applied = true
      } catch {
        logWarning("오디오 attach 기반 음소거 해제 실패(track=\(track)): \(error.localizedDescription)", category: .streaming)
      }
    }
    return applied
  }

  @MainActor
  private func codexResolveMediaMixer() -> MediaMixer? {
    let mirror = Mirror(reflecting: self)

    if let mixer = mirror.descendant("mixer") as? MediaMixer {
      return mixer
    }

    if let lazyStorage = mirror.descendant("$__lazy_storage_$_mixer"),
       let mixer = codexUnwrapMediaMixer(from: lazyStorage)
    {
      return mixer
    }

    for child in mirror.children {
      guard let label = child.label else { continue }
      guard label.contains("mixer") else { continue }
      if let mixer = codexUnwrapMediaMixer(from: child.value) {
        return mixer
      }
    }

    return nil
  }

  private func codexUnwrapMediaMixer(from value: Any) -> MediaMixer? {
    if let mixer = value as? MediaMixer {
      return mixer
    }

    let mirror = Mirror(reflecting: value)
    if mirror.displayStyle == .optional,
       let child = mirror.children.first
    {
      return codexUnwrapMediaMixer(from: child.value)
    }

    return nil
  }
}

final class StreamAudioPeakOutputObserver: NSObject, HKStreamOutput, @unchecked Sendable {
  private let onPeak: @Sendable (Float, Float) -> Void
  private let lock = NSLock()
  private var previousLevel: Float = 0

  init(onPeak: @escaping @Sendable (Float, Float) -> Void) {
    self.onPeak = onPeak
  }

  nonisolated func stream(_ stream: some HKStream, didOutput audio: AVAudioBuffer, when: AVAudioTime)
  {
    guard let pcmBuffer = audio as? AVAudioPCMBuffer else { return }

    let (level, decibels) = Self.measurePeak(from: pcmBuffer)

    lock.lock()
    let smoothed = max(level, previousLevel * 0.78)
    previousLevel = smoothed
    lock.unlock()

    onPeak(smoothed, decibels)
  }

  nonisolated func stream(_ stream: some HKStream, didOutput video: CMSampleBuffer) {}

  static func measurePeak(from buffer: AVAudioPCMBuffer) -> (Float, Float) {
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0 else { return (0, -80) }

    let channelCount = Int(buffer.format.channelCount)
    guard channelCount > 0 else { return (0, -80) }

    let sampleStep = max(1, frameCount / 1024)
    var peak: Float = 0

    if let channels = buffer.floatChannelData {
      for channel in 0..<channelCount {
        let samples = channels[channel]
        var index = 0
        while index < frameCount {
          peak = max(peak, abs(samples[index]))
          index += sampleStep
        }
      }
    } else if let channels = buffer.int16ChannelData {
      let scale = Float(Int16.max)
      for channel in 0..<channelCount {
        let samples = channels[channel]
        var index = 0
        while index < frameCount {
          peak = max(peak, abs(Float(samples[index])) / scale)
          index += sampleStep
        }
      }
    } else if let channels = buffer.int32ChannelData {
      let scale = Float(Int32.max)
      for channel in 0..<channelCount {
        let samples = channels[channel]
        var index = 0
        while index < frameCount {
          peak = max(peak, abs(Float(samples[index])) / scale)
          index += sampleStep
        }
      }
    }

    let safePeak = max(peak, 0.0001)
    let decibels = max(-80, min(0, 20 * log10(safePeak)))
    let normalized = normalizedLevel(from: decibels)

    return (normalized, decibels)
  }

  private static func normalizedLevel(from decibels: Float) -> Float {
    // 작은 음성도 더 잘 보이도록 감도를 보정한 커브
    let noiseFloor: Float = -72
    let headroom: Float = -6
    let gamma: Float = 0.72

    if decibels <= noiseFloor {
      return 0
    }

    let linear = ((decibels - noiseFloor) / (headroom - noiseFloor)).clamped(to: 0...1)
    return pow(linear, gamma).clamped(to: 0...1)
  }
}

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
      let (level, decibels) = StreamAudioPeakOutputObserver.measurePeak(from: buffer)

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
