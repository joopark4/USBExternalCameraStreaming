import AVFoundation
import Foundation
import LiveStreamingCore

extension LiveStreamViewModel {
  // MARK: - Public Microphone Input

  var selectedMicrophoneInputDisplayName: String {
    availableMicrophoneInputs.first(where: { $0.id == selectedMicrophoneInputID })?.name
      ?? NSLocalizedString("microphone_input_auto", comment: "시스템 기본 마이크(자동)")
  }

  var hasExternalMicrophoneInput: Bool {
    availableMicrophoneInputs.contains { !$0.isAutomatic && $0.isExternal }
  }

  var activeMicrophoneConnectionLabel: String {
    let portType = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType
    guard let portType else {
      return NSLocalizedString("microphone_connection_external", comment: "외부")
    }
    return microphoneConnectionLabel(for: portType)
  }

  var activeMicrophoneDisplaySummary: String {
    let inputName = activeMicrophoneInputName.isEmpty
      ? NSLocalizedString("microphone_input_none", comment: "입력 없음")
      : activeMicrophoneInputName

    if inputName == NSLocalizedString("microphone_input_none", comment: "입력 없음") {
      return inputName
    }

    return "\(inputName) · \(activeMicrophoneConnectionLabel)"
  }

  func selectMicrophoneInput(_ inputID: String) {
    guard selectedMicrophoneInputID != inputID else { return }
    selectedMicrophoneInputID = inputID

    Task { [weak self] in
      _ = await self?.applySelectedMicrophoneInputToAudioSession(reconnectIfStreaming: true)
    }
  }

  func setupMicrophoneInputMonitoring() {
    refreshAvailableMicrophoneInputs()

    let session = AVAudioSession.sharedInstance()
    audioRouteChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: session,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.refreshAvailableMicrophoneInputs()
        _ = await self.applySelectedMicrophoneInputToAudioSession(
          reconnectIfStreaming: self.status == .streaming
        )
      }
    }
  }

  func refreshAvailableMicrophoneInputs() {
    let session = AVAudioSession.sharedInstance()
    let availableInputs = session.availableInputs ?? []

    let automaticInput = MicrophoneInputOption(
      id: MicrophoneInputOption.automaticID,
      name: NSLocalizedString("microphone_input_auto", comment: "시스템 기본 마이크(자동)"),
      portType: nil,
      uid: nil
    )

    let inputOptions = availableInputs.map { input in
      MicrophoneInputOption(
        id: input.uid,
        name: microphoneDisplayName(for: input),
        portType: input.portType,
        uid: input.uid
      )
    }

    availableMicrophoneInputs = [automaticInput] + inputOptions

    if !availableMicrophoneInputs.contains(where: { $0.id == selectedMicrophoneInputID }) {
      selectedMicrophoneInputID = MicrophoneInputOption.automaticID
    }

    updateActiveMicrophoneInputName()
  }

  @discardableResult
  func applySelectedMicrophoneInputToAudioSession(reconnectIfStreaming: Bool) async -> Bool {
    let session = AVAudioSession.sharedInstance()

    do {
      try session.setCategory(
        .playAndRecord,
        mode: status == .streaming ? .videoRecording : .measurement,
        options: [.defaultToSpeaker, .allowBluetoothHFP]
      )

      let targetPort: AVAudioSessionPortDescription?
      if selectedMicrophoneInputID == MicrophoneInputOption.automaticID {
        targetPort = nil
      } else {
        let availableInputs = session.availableInputs ?? []
        targetPort = availableInputs.first(where: { $0.uid == selectedMicrophoneInputID })
      }

      if selectedMicrophoneInputID != MicrophoneInputOption.automaticID && targetPort == nil {
        selectedMicrophoneInputID = MicrophoneInputOption.automaticID
      }

      try session.setPreferredInput(targetPort)
      try session.setActive(true)
      updateActiveMicrophoneInputName()

      if reconnectIfStreaming {
        _ = await reattachAudioInputForCurrentRouteIfNeeded()
      } else {
        restartIdleMicrophonePeakMonitoringIfNeeded()
      }

      return true
    } catch {
      logWarning("마이크 입력 소스 적용 실패: \(error.localizedDescription)", category: .streaming)
      updateActiveMicrophoneInputName()
      return false
    }
  }

  // MARK: - Private

  private func microphoneDisplayName(for port: AVAudioSessionPortDescription) -> String {
    let connectionName = microphoneConnectionLabel(for: port.portType)
    return "\(port.portName) · \(connectionName)"
  }

  private func microphoneConnectionLabel(for portType: AVAudioSession.Port) -> String {
    switch portType {
    case .builtInMic:
      return NSLocalizedString("microphone_connection_builtin", comment: "내장")
    case .bluetoothHFP, .bluetoothLE:
      return NSLocalizedString("microphone_connection_bluetooth", comment: "블루투스")
    case .headsetMic, .lineIn, .usbAudio:
      return NSLocalizedString("microphone_connection_wired", comment: "유선/USB")
    default:
      return NSLocalizedString("microphone_connection_external", comment: "외부")
    }
  }

  private func updateActiveMicrophoneInputName() {
    let currentInputName = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
    activeMicrophoneInputName =
      currentInputName ?? NSLocalizedString("microphone_input_none", comment: "입력 없음")
  }

  private func reattachAudioInputForCurrentRouteIfNeeded() async -> Bool {
    guard status == .streaming else { return true }
    guard let haishinKitManager = liveStreamService as? HaishinKitManager else { return false }
    return await haishinKitManager.codexReattachAudioInputForCurrentRoute()
  }
}

private extension HaishinKitManager {
  @MainActor
  func codexReattachAudioInputForCurrentRoute() async -> Bool {
    guard let mixer = Mirror(reflecting: self).descendant("mixer") as? MediaMixer else {
      return false
    }

    do {
      try await mixer.attachAudio(nil, track: 0)
      if let audioDevice = AVCaptureDevice.default(for: .audio) {
        try await mixer.attachAudio(audioDevice, track: 0)
      }
      return true
    } catch {
      return false
    }
  }
}
