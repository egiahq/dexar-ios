import SwiftUI

struct RootView: View {
    @State private var speech = SpeechEngine()
    @State private var gemma = GemmaEngine()
    @State private var settings = SettingsStore()
    @State private var session: SessionEngine?
    @State private var isBooting = true
    @State private var messageIdx = 0

    private let bootMessages = [
        "Teaching the mic to pay attention…",
        "Loading your focus engine…",
        "Whisper is waking up…",
        "Almost ready. Good things take a second.",
        "Warming up the voice. Won't be long.",
        "Downloading a little patience…",
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if isBooting {
                bootView
            } else if !settings.onboardingComplete {
                OnboardingView(speech: speech, settings: settings) {
                    if gemma.wasDownloaded {
                        Task { await gemma.load() }
                    }
                    session = SessionEngine(speech: speech, gemma: gemma)
                }
                .transition(.opacity)
            } else if let session {
                FocusView(session: session, gemma: gemma, settings: settings)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isBooting)
        .animation(.easeInOut(duration: 0.4), value: settings.onboardingComplete)
        .task {
            if settings.onboardingComplete {
                await speech.requestPermissionAndLoad(settings: settings)
                if gemma.wasDownloaded {
                    Task { await gemma.load() }
                }
                withAnimation {
                    isBooting = false
                    session = SessionEngine(speech: speech, gemma: gemma)
                }
            } else {
                withAnimation { isBooting = false }
            }
        }
    }

    private var bootView: some View {
        VStack(spacing: 24) {
            Text("Dexar")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .foregroundStyle(.primary)

            BouncingDots(color: .secondary)

            Text(bootMessages[messageIdx])
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
                .animation(.easeInOut(duration: 0.5), value: messageIdx)
                .id(messageIdx)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { t in
                withAnimation { messageIdx = (messageIdx + 1) % bootMessages.count }
                if !isBooting { t.invalidate() }
            }
        }
    }
}

#Preview {
    RootView()
}
