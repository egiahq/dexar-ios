import Foundation
import AVFoundation
import UIKit
import WhisperKit

@MainActor
@Observable
final class SpeechEngine {

    enum State {
        case requestingPermission
        case permissionDenied
        case loadingModels(String)
        case idle
        case recording
        case transcribing
        case speaking
        case error(String)
    }

    private(set) var state: State = .requestingPermission
    private(set) var transcript: String = ""
    private(set) var downloadProgress: Double? = nil

    var loadingMessage: String {
        switch state {
        case .requestingPermission: return PromptStore.shared.string(for: "requesting_mic")
        case .loadingModels(let msg): return msg
        default: return ""
        }
    }

    private var whisper: WhisperKit?
    private var loadTask: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    private var currentModel: SettingsStore.WhisperModel = .tiny
    private var currentVoice: SettingsStore.Voice = .ryan

    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var cuePlayer: AVAudioPlayer?

    var currentInputLevel: Float? {
        guard let recorder else { return nil }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        let linear = pow(10, db / 20)
        return max(0, min(1, linear))
    }

    var isReady: Bool {
        whisper != nil
    }

    func requestPermissionAndLoad(settings: SettingsStore) async {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            state = .permissionDenied
            return
        }
        currentModel = settings.whisperModel
        currentVoice = settings.voice
        observeAudioSession()
        startPreloading(model: currentModel, voice: currentVoice)
    }

    func applySettings(model: SettingsStore.WhisperModel, voice: SettingsStore.Voice, settings: SettingsStore) async {
        settings.voice = voice
        currentVoice = voice

        guard model != currentModel else { return }

        settings.whisperModel = model
        currentModel = model
        whisper = nil
        await loadModels(model: model, voice: voice)
    }

    func ensureReady() async -> Bool {
        if isReady { return true }
        if case .permissionDenied = state { return false }

        if loadTask == nil {
            startPreloading(model: currentModel, voice: currentVoice)
        }
        await loadTask?.value

        if isReady { return true }

        whisper = nil
        await loadModels(model: currentModel, voice: currentVoice)
        return isReady
    }

    private func startPreloading(model: SettingsStore.WhisperModel, voice: SettingsStore.Voice) {
        if isReady { return }
        if loadTask != nil { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.loadModels(model: model, voice: voice)
            self.loadTask = nil
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func loadModels(model: SettingsStore.WhisperModel, voice: SettingsStore.Voice) async {
        state = .loadingModels(PromptStore.shared.string(for: "loading_recognition"))
        try? configureAudioSession()
        downloadProgress = nil
        do {
            whisper = try await makeWhisper(model: model)
            downloadProgress = nil
            state = .idle
        } catch {
            downloadProgress = nil
            state = .error(error.localizedDescription)
        }
    }

    private func makeWhisper(model: SettingsStore.WhisperModel) async throws -> WhisperKit {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let whisperBase = docs.appendingPathComponent("whisper_models", isDirectory: true)
        try? FileManager.default.createDirectory(at: whisperBase, withIntermediateDirectories: true)
        let config = WhisperKitConfig(
            model: model.rawValue,
            downloadBase: whisperBase,
            prewarm: false
        )
        let w = try await WhisperKit(config)
        try await w.loadModels()
        return w
    }

    func startRecording() throws {
        try configureAudioSession()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.record()
        state = .recording
    }

    func stopRecordingAndProcess() async {
        recorder?.stop()
        recorder = nil
        guard let url = recordingURL else { return }

        state = .transcribing
        do {
            guard let whisper else { throw EngineError.notLoaded }
            let results = try await whisper.transcribe(audioPath: url.path)
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                if transcript.isEmpty {
                    transcript = text
                } else {
                    transcript += " " + text
                }
            }
            try? FileManager.default.removeItem(at: url)

            state = .idle
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func cancelError() { state = .idle }

    func stopAll() {
        recorder?.stop()
        recorder = nil
        cuePlayer?.stop()
        cuePlayer = nil
        if state == .recording || state == .speaking || state == .transcribing {
            state = .idle
        }
    }

    func transcribeRecording() async -> String {
        recorder?.stop()
        recorder = nil
        guard let url = recordingURL, let whisper else { return "" }
        do {
            let results = try await whisper.transcribe(audioPath: url.path)
            let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: url)
            return text
        } catch { return "" }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @discardableResult
    func playCue(named name: String) -> Bool {
        cuePlayer?.stop()
        cuePlayer = nil
        recorder?.stop()
        recorder = nil
        let voiceDir = currentVoice.rawValue.lowercased()
        let extensions = ["m4a", "wav"]
        var candidates: [URL?] = []

        for ext in extensions {
            candidates += [
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "SFX"),
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "sfx"),
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Assets/SFX"),
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Assets/sfx"),
                Bundle.main.url(forResource: "\(voiceDir)_\(name)", withExtension: ext, subdirectory: "Audio/\(voiceDir)"),
                Bundle.main.url(forResource: "\(voiceDir)_\(name)", withExtension: ext, subdirectory: voiceDir),
                Bundle.main.url(forResource: "\(voiceDir)_\(name)", withExtension: ext),
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio/\(voiceDir)"),
                Bundle.main.url(forResource: name, withExtension: ext, subdirectory: voiceDir),
                Bundle.main.url(forResource: name, withExtension: ext)
            ]
        }

        guard let url = candidates.compactMap({ $0 }).first else { return false }
        do {
            cuePlayer = try AVAudioPlayer(contentsOf: url)
            cuePlayer?.volume = 0.9
            cuePlayer?.prepareToPlay()
            cuePlayer?.play()
            return true
        } catch {
            cuePlayer = nil
            return false
        }
    }

    func playCueAndWait(named name: String) async -> Bool {
        guard playCue(named: name), let player = cuePlayer else { return false }
        while player.isPlaying {
            if Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return true
    }

    private func observeAudioSession() {
        let nc = NotificationCenter.default

        interruptionObserver = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let typeVal = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }

            Task { @MainActor in
                switch type {
                case .began:
                    if self.state == .recording {
                        self.recorder?.pause()
                    }
                case .ended:
                    let optionsVal = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsVal)
                    if options.contains(.shouldResume) {
                        try? self.configureAudioSession()
                        if self.state == .recording {
                            self.recorder?.record()
                        }
                    }
                @unknown default: break
                }
            }
        }

        routeChangeObserver = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let reasonVal = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonVal) else { return }
            if reason == .oldDeviceUnavailable {
                Task { @MainActor in
                    if self.state == .recording {
                        self.recorder?.pause()
                    }
                }
            }
        }
    }
}

private enum EngineError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "Models not loaded yet." }
}
