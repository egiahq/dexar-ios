import SwiftUI
import UserNotifications

struct OnboardingView: View {
    var speech: SpeechEngine
    var settings: SettingsStore
    var onComplete: () -> Void

    @State private var name: String = ""
    @State private var step: Step = .intro
    @FocusState private var fieldFocused: Bool

    enum Step { case intro, downloading, nameInput, done }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                switch step {
                case .intro:
                    introContent
                case .downloading:
                    downloadingContent
                case .nameInput:
                    nameContent
                case .done:
                    doneContent
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .animation(.easeInOut(duration: 0.4), value: step)
    }

    private var introContent: some View {
        VStack(spacing: 32) {
            Text(PromptStore.shared.string(for: "onboarding_title"))
                .font(.system(size: 34, weight: .light, design: .rounded))
                .foregroundStyle(Color.appForeground)

            Text(PromptStore.shared.string(for: "onboarding_subtitle"))
                .font(.callout)
                .foregroundStyle(Color.appMutedForeground)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(spacing: 8) {
                Text(PromptStore.shared.string(for: "onboarding_download_hint"))
                    .font(.footnote)
                    .foregroundStyle(Color.appMutedForeground)
                Text(PromptStore.shared.string(for: "onboarding_models_info"))
                    .font(.caption)
                    .foregroundStyle(Color.appMutedForeground.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button(action: startDownload) {
                Text(PromptStore.shared.string(for: "onboarding_start_button"))
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.appForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appSecondaryBackground)
                    .clipShape(Rectangle())
            }
        }
    }

    private var downloadingContent: some View {
        VStack(spacing: 32) {
            Text(PromptStore.shared.string(for: "onboarding_setup_title"))
                .font(.title3.weight(.regular))
                .foregroundStyle(Color.appForeground)

            VStack(spacing: 16) {
                if let progress = speech.downloadProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color.appForeground)
                } else {
                    BouncingDots(color: Color.appMutedForeground)
                }

                Text(speech.loadingMessage.isEmpty ? "Loading…" : speech.loadingMessage)
                    .font(.subheadline)
                    .foregroundStyle(Color.appMutedForeground)
                    .multilineTextAlignment(.center)
            }

            Text(PromptStore.shared.string(for: "onboarding_setup_hint"))
                .font(.caption)
                .foregroundStyle(Color.appMutedForeground.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .onChange(of: speech.state) { _, newState in
            if case .idle = newState {
                withAnimation { step = .nameInput }
            }
        }
    }

    private var nameContent: some View {
        VStack(spacing: 28) {
            Text(PromptStore.shared.string(for: "onboarding_name_title"))
                .font(.title3.weight(.regular))
                .foregroundStyle(Color.appForeground)

            Text(PromptStore.shared.string(for: "onboarding_name_hint"))
                .font(.caption)
                .foregroundStyle(Color.appMutedForeground.opacity(0.7))
                .multilineTextAlignment(.center)

            TextField(PromptStore.shared.string(for: "onboarding_name_placeholder"), text: $name)
                .font(.title3)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(Color.appSecondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: confirmName) {
                Text(PromptStore.shared.string(for: "onboarding_continue_button"))
                    .font(.body.weight(.medium))
                    .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.appMutedForeground : Color.appForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appSecondaryBackground)
                    .clipShape(Rectangle())
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { fieldFocused = true }
    }

    private var doneContent: some View {
        VStack(spacing: 24) {
            Text(PromptStore.shared.string(for: "onboarding_ready_prefix") + settings.userName + PromptStore.shared.string(for: "onboarding_ready_suffix"))
                .font(.title3.weight(.regular))
                .foregroundStyle(Color.appForeground)

            Text(PromptStore.shared.string(for: "onboarding_change_name_hint"))
                .font(.caption)
                .foregroundStyle(Color.appMutedForeground.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }

    private func startDownload() {
        withAnimation { step = .downloading }
        Task {
            await speech.requestPermissionAndLoad(settings: settings)
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private func confirmName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        settings.userName = trimmed
        settings.onboardingComplete = true
        withAnimation { step = .done }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            onComplete()
        }
    }
}

#Preview {
    OnboardingView(speech: SpeechEngine(), settings: SettingsStore()) {}
}
