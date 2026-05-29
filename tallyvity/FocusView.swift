import SwiftUI

struct FocusView: View {
    var session: SessionEngine
    var gemma: GemmaEngine
    var settings: SettingsStore

    @State private var showSettings = false
    @State private var showCamera = false
    @State private var showHistory = false
    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
    @State private var loopCount = 4
    @State private var breakAmbientShift = false
    @State private var showEndAlert = false
    @State private var goalTranscriptText = ""
    @FocusState private var captureFieldFocused: Bool

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            phaseContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            SettingsView(gemma: gemma, settings: settings)
        }
        .sheet(isPresented: $showHistory) {
            SessionHistoryView(session: session, settings: settings)
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in
                session.setBaselinePhoto(image)
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .task {
            session.loadPendingCheckpoint(userName: settings.userName)
        }
        .confirmationDialog(
            "End Session?",
            isPresented: $showEndAlert,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) { session.cancelSession() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will stop the current timer and end your progress.")
        }
        .onChange(of: session.transcript) { _, newValue in
            goalTranscriptText = newValue
        }
        .onChange(of: goalTranscriptText) { _, newValue in
            session.updateTranscript(newValue)
        }
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .goalCapture {
                goalTranscriptText = session.transcript
            }
        }
    }

    // MARK: - Phase routing

    @ViewBuilder
    private var phaseContent: some View {
        switch session.phase {
        case .idle:
            idleView

        case .motivationSelection:
            motivationView

        case .preparingAudio:
            preparingAudioView

        case .goalCapture:
            captureView(
                title: "Say your goal",
                hint: "What are you working on?"
            )

        case .photoBaseline:
            photoPromptView(isBaseline: true)

        case .sessionReady:
            sessionReadyView

        case .backgroundPrep(let loop):
            workView(loopNumber: loop)

        case .workActive(let loop):
            workView(loopNumber: loop)

        case .roundEnd:
            roundEndView

        case .photoDelta:
            photoPromptView(isBaseline: false)

        case .storing:
            transitionView(text: "Storing…", showContinue: false)

        case .breakTime(let loop):
            breakView(loopNumber: loop)

        case .nextSessionCountdown(let loop):
            nextSessionView(loopNumber: loop)

        case .sessionReport:
            if let artifact = session.finalArtifact {
                SessionReportView(
                    loops: session.completedLoops,
                    artifact: artifact,
                    beforeImage: session.baselinePhoto,
                    afterImage: session.finalPhoto,
                    comparison: session.comparisonText,
                    onDismiss: session.dismissReport
                )
            }

        case .error(let msg):
            errorView(message: msg)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { showHistory = true }) {
                    Image(systemName: "clock")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 44) {
                VStack(spacing: 10) {
                    Text("Tallyvity")
                        .font(.system(size: 34, weight: .light, design: .rounded))
                        .foregroundStyle(.primary)

                    // if let recall = session.memoryRecallText {
                    //     Text(recall)
                    //         .font(.callout)
                    //         .foregroundStyle(.secondary)
                    //         .multilineTextAlignment(.center)
                    //         .padding(.horizontal, 40)
                    //         .transition(.opacity)
                    // } else if let checkpoint = session.pendingCheckpoint {
                    //     resumePill(checkpoint: checkpoint)
                    // } else if let latest = SessionStore.shared.latest {
                    //     lastSessionPill(artifact: latest)
                    // }
                }

                timePickers

                startButton
            }

            // Spacer()
            Spacer()
        }
    }

    private func resumePill(checkpoint: SessionStore.SessionCheckpoint) -> some View {
        Button(action: { showHistory = true }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text(checkpoint.currentGoal.isEmpty ? "Session in progress" : checkpoint.currentGoal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var timePickers: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                RotaryTimePicker(
                    value: $focusMinutes,
                    values: Array(stride(from: 5, through: 90, by: 5)),
                    label: "Focus"
                )
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 120)

                RotaryTimePicker(
                    value: $breakMinutes,
                    values: Array(stride(from: 5, through: 30, by: 1)),
                    label: "Break"
                )
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 120)

                RotaryTimePicker(
                    value: $loopCount,
                    values: Array(1...6),
                    label: "Loops",
                    unit: "amount"
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
        }
    }

    private func lastSessionPill(artifact: SessionArtifact) -> some View {
        VStack(spacing: 4) {
            Text("Last session")
                .font(.caption2)
                .kerning(1.2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(artifact.goal)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }


    private var startButton: some View {
        Button(action: {
            session.workDuration = Double(focusMinutes) * 60
            session.shortBreakDuration = Double(breakMinutes) * 60
            session.longBreakDuration = Double(breakMinutes * 4) * 60
            session.totalLoops = loopCount
            session.startSession(userName: settings.userName)
        }) {
            Text("Begin")
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Self score

    private var motivationView: some View {
        VStack(spacing: 40) {
            Spacer()
            MotivationSelector(
                onSelect: { level in
                    session.submitMotivation(level)
                },
                onTapAdjust: {
                    session.playRateCue()
                }
            )
            Spacer()
            sessionControls(canSkip: false)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Work timer

    private func workView(loopNumber: Int) -> some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                loopDots(current: loopNumber)
                    .padding(.top, 60)

                Spacer()

                TimerRingView(
                    progress: session.timerProgress,
                    isWork: true,
                    remainingTime: session.remainingTime
                )
                .frame(width: 280, height: 280)



                Spacer()

                sessionControls(canSkip: true)
                    .padding(.bottom, 48)
            }
        }
    }

    @ViewBuilder
    private func loopDots(current: Int) -> some View {
        let loops = max(1, session.totalLoops)
        HStack(spacing: 8) {
            ForEach(1...loops, id: \.self) { i in
                Circle()
                    .fill(i <= session.completedLoops.count
                          ? Color(.label)
                          : (i == current ? Color(.label).opacity(0.5) : Color(.systemGray5))
                    )
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Break timer

    private func breakView(loopNumber: Int) -> some View {
        ZStack {
            breakAmbientBackground

            VStack(spacing: 0) {
                loopDots(current: loopNumber)
                    .padding(.top, 60)

                Spacer()

                TimerRingView(
                    progress: session.timerProgress,
                    isWork: false,
                    remainingTime: session.remainingTime
                )
                .frame(width: 280, height: 280)

                Text("Rest")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)

                Spacer()

                sessionControls(canSkip: true)
                    .padding(.bottom, 48)
            }
        }
    }

    private var breakAmbientBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(.systemGray5).opacity(0.42))
                .frame(width: 230, height: 230)
                .blur(radius: 24)
                .offset(
                    x: breakAmbientShift ? -80 : 70,
                    y: breakAmbientShift ? -150 : -40
                )

            Circle()
                .fill(Color(.systemGray4).opacity(0.26))
                .frame(width: 260, height: 260)
                .blur(radius: 30)
                .offset(
                    x: breakAmbientShift ? 95 : -75,
                    y: breakAmbientShift ? 120 : 170
                )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                breakAmbientShift.toggle()
            }
        }
    }

    private func nextSessionView(loopNumber: Int) -> some View {
        VStack(spacing: 16) {
            loopDots(current: loopNumber)

            VStack(spacing: 8) {
                Text("Next session")
                    .font(.system(size: 13, weight: .medium))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                Text("Session \(loopNumber)")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .foregroundStyle(.primary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.5), value: loopNumber)
    }

    private func sessionControls(canSkip: Bool) -> some View {
        HStack(spacing: 32) {
            Button(action: { showEndAlert = true }) {
                Text("End")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if canSkip {
                Button(action: { session.skipPhase() }) {
                    Text("Skip →")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Capture (goal / score)

    private func captureView(title: String, hint: String) -> some View {
        VStack(spacing: 0) {
            Group {
                if session.isRecording {
                    RecordingPulse()
                } else if session.isProcessingSpeech {
                    ProgressView()
                } else {
                    Color.clear.frame(height: 20)
                }
            }
            .frame(height: 20)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 28) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .kerning(1.6)
                    .foregroundStyle(.tertiary)

                TextField(hint, text: $goalTranscriptText, axis: .vertical)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 36)
                    .focused($captureFieldFocused)
                    .submitLabel(.done)

                Button(action: {
                    session.toggleRecording()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: session.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(session.isRecording ? "Stop Recording" : "Record Voice")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(session.isRecording ? .red : .primary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
                .disabled(session.isProcessingSpeech && !session.isRecording)
            }

            Spacer()

            if !session.isRecording && !session.isProcessingSpeech {
                Button(action: {
                    captureFieldFocused = false
                    session.confirmGoal()
                }) {
                    Text("Next")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                .transition(.opacity)
                .padding(.bottom, 24)
            }

            sessionControls(canSkip: false)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Photo

    private func photoPromptView(isBaseline: Bool) -> some View {
        VStack(spacing: 0) {
            // Goal anchor
            VStack(spacing: 6) {
                Text("Goal")
                    .font(.system(size: 10, weight: .medium))
                    .kerning(1.6)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(session.currentGoal)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 36)
            }
            .padding(.top, 56)

            Spacer()

            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Text(isBaseline ? "Optional" : "Before you go")
                        .font(.caption)
                        .kerning(1.5)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(isBaseline
                        ? "Share a photo of what you are working on?"
                        : "Share a photo of your work"
                    )
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }

                HStack(spacing: 16) {
                    Button(action: { showCamera = true }) {
                        Label("Photo", systemImage: "camera")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: session.skipPhoto) {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                }
            }

            Spacer()

            if isBaseline {
                Button(action: session.backToGoal) {
                    Text("← Edit Goal")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 52)
                }
            }
        }
    }
    
    private var sessionReadyView: some View {
        SessionReadyView(session: session)
    }

    // MARK: - Transition overlay

    private var preparingAudioView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Preparing voice models…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func transitionView(text: String, showContinue: Bool) -> some View {
        VStack(spacing: 32) {
            Text(text)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    private var roundEndView: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Good.")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.gray)

            Spacer()

            VStack(spacing: 16) {
                Button(action: {
                    session.selectRoundEndAction(.workFiveMore)
                }) {
                    Text("Work for 5 more minutes")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(action: {
                    session.selectRoundEndAction(.startBreak)
                }) {
                    Text("Start break")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Dismiss") { session.cancelError() }
                .buttonStyle(.borderedProminent)
        }
    }
}

private extension FocusView {
    func promptTextColor(isPlaceholder: Bool) -> Color {
        if isPlaceholder {
            return session.isProcessingSpeech ? Color(.tertiaryLabel) : Color(.secondaryLabel)
        }
        return session.isProcessingSpeech ? Color(.secondaryLabel) : .primary
    }
}

// MARK: - Session ready (editable goal)

struct SessionReadyView: View {
    var session: SessionEngine
    @State private var goalText: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Text("Your goal")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(1.6)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    TextField("", text: $goalText, axis: .vertical)
                        .font(.title2.weight(.light))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 40)
                        .focused($fieldFocused)
                        .onChange(of: goalText) { _, new in
                            session.updateGoal(new)
                        }
                }

                Button(action: {
                    fieldFocused = false
                    session.confirmStartSession()
                }) {
                    Text("Start Session")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 18)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Button(action: session.backToGoal) {
                Text("← Record again")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 52)
        }
        .onAppear { goalText = session.currentGoal }
    }
}

// MARK: - Recording pulse animation

struct RecordingPulse: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.15))
                .frame(width: 40, height: 40)
                .scaleEffect(scale)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: scale)

            Circle()
                .fill(Color.red)
                .frame(width: 14, height: 14)
        }
        .onAppear { scale = 1.3 }
    }
}

#Preview {
    FocusView(
        session: SessionEngine(speech: SpeechEngine(), gemma: GemmaEngine()),
        gemma: GemmaEngine(),
        settings: SettingsStore()
    )
}
