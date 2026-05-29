import SwiftUI

struct VoiceLoopView: View {
    var engine: SpeechEngine
    var settings: SettingsStore

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            switch engine.state {
            case .requestingPermission:
                loadingOverlay(message: PromptStore.shared.string(for: "permission_denied_overlay"), progress: nil)

            case .permissionDenied:
                permissionDeniedView

            case .loadingModels(let message):
                loadingOverlay(message: message, progress: engine.downloadProgress)

            default:
                mainContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Error", isPresented: isError) {
            Button("OK") { engine.cancelError() }
        } message: {
            if case .error(let msg) = engine.state { Text(msg) }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 48) {
            Group {
                if engine.state == .recording {
                    RecordingPulse()
                } else if engine.state == .transcribing {
                    ProgressView()
                } else {
                    Color.clear.frame(height: 20)
                }
            }
            .frame(height: 20)
            .padding(.top, 16)

            Spacer()
            transcriptSection
            Spacer()
            recordButton
                .padding(.bottom, 56)
        }
    }

    @ViewBuilder
    private var transcriptSection: some View {
        VStack(spacing: 16) {
            Text(engine.state.label.uppercased())
                .font(.caption)
                .kerning(1.5)
                .foregroundStyle(.secondary)
                .animation(.easeInOut, value: engine.state.label)

            Text(engine.transcript.isEmpty ? PromptStore.shared.string(for: "tap_to_record") : engine.transcript)
                .font(.title3)
                .fontWeight(.regular)
                .multilineTextAlignment(.center)
                .foregroundStyle(engine.transcript.isEmpty ? .tertiary : .primary)
                .padding(.horizontal, 32)
                .animation(.easeInOut, value: engine.transcript)
        }
    }

    private var recordButton: some View {
        Button(action: onRecordTap) {
            Circle()
                .fill(buttonColor)
                .frame(width: 72, height: 72)
                .overlay {
                    if case .transcribing = engine.state {
                        ProgressView().tint(.white)
                    } else if case .speaking = engine.state {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: buttonIcon)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .scaleEffect(engine.state == .recording ? 1.15 : 1.0)
                .animation(.spring(response: 0.3), value: engine.state == .recording)
        }
        .disabled(!engine.state.allowsInteraction)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(PromptStore.shared.string(for: "mic_access_required"))
                .font(.title3)
            Text(PromptStore.shared.string(for: "mic_access_settings"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Settings") { engine.openSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private func loadingOverlay(message: String, progress: Double?) -> some View {
        VStack(spacing: 20) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.primary)
            } else {
                ProgressView()
                    .scaleEffect(1.4)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
    }

    private var buttonColor: Color {
        switch engine.state {
        case .recording: .red
        case .transcribing, .speaking: Color(.systemGray3)
        default: .primary
        }
    }

    private var buttonIcon: String {
        switch engine.state {
        case .recording: "stop.fill"
        default: "mic.fill"
        }
    }

    private var isError: Binding<Bool> {
        Binding(
            get: { if case .error = engine.state { true } else { false } },
            set: { _ in }
        )
    }

    private func onRecordTap() {
        switch engine.state {
        case .idle:
            try? engine.startRecording()
        case .recording:
            Task { await engine.stopRecordingAndProcess() }
        default:
            break
        }
    }
}

extension SpeechEngine.State {
    var label: String {
        switch self {
        case .idle:                 PromptStore.shared.string(for: "ready")
        case .requestingPermission: PromptStore.shared.string(for: "requesting_access")
        case .permissionDenied:     PromptStore.shared.string(for: "no_microphone_access")
        case .loadingModels:        PromptStore.shared.string(for: "loading")
        case .recording:            PromptStore.shared.string(for: "recording_hint")
        case .transcribing:         PromptStore.shared.string(for: "transcribing")
        case .speaking:             PromptStore.shared.string(for: "speaking")
        case .error:                PromptStore.shared.string(for: "error")
        }
    }

    var allowsInteraction: Bool {
        switch self {
        case .idle, .recording: true
        default: false
        }
    }
}

extension SpeechEngine.State: Equatable {
    static func == (lhs: SpeechEngine.State, rhs: SpeechEngine.State) -> Bool {
        switch (lhs, rhs) {
        case (.requestingPermission, .requestingPermission),
             (.permissionDenied, .permissionDenied),
             (.idle, .idle),
             (.recording, .recording),
             (.transcribing, .transcribing),
             (.speaking, .speaking): true
        case (.loadingModels(let a), .loadingModels(let b)): a == b
        case (.error(let a), .error(let b)): a == b
        default: false
        }
    }
}

#Preview {
    VoiceLoopView(engine: SpeechEngine(), settings: SettingsStore())
}
