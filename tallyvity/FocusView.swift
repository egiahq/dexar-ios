import SwiftUI
import ActivityKit

struct FocusView: View {
    var session: SessionEngine
    var gemma: GemmaEngine
    var settings: SettingsStore

    @State private var showSettings = false
    @State private var showCamera = false
    @State private var showHistory = false
    @State private var showAnalytics = false
    @State private var showResumeAlert = false
    @State private var checkpointToResume: SessionStore.SessionCheckpoint? = nil
    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
    @State private var loopCount = 4
    @State private var breakAmbientShift = false
    @State private var showEndAlert = false
    @State private var showStopConfirmation = false
    @State private var goalTranscriptText = ""
    @FocusState private var captureFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            phaseContent
        }
        .overlay(alignment: .topLeading) {
            if session.phase != .idle && session.phase != .sessionReport {
                Button(action: {
                    showStopConfirmation = true
                }) {
                    Image(systemName: "square")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red.opacity(0.65))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.08))
                        )
                }
                .padding(.leading, 24)
                .padding(.top, 16)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            SettingsView(gemma: gemma, settings: settings)
        }
        .sheet(isPresented: $showHistory) {
            SessionHistoryView(session: session, settings: settings)
        }
        .sheet(isPresented: $showAnalytics) {
            AnalyticsView()
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in
                if session.phase == .roundEnd {
                    session.setProgressPhoto(image)
                } else {
                    session.setBaselinePhoto(image)
                }
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .task {
            session.loadPendingCheckpoint(userName: settings.userName)
            if let cp = SessionStore.shared.loadCheckpoint() {
                // If there's an active live activity, resume silently to maintain context
                if !Activity<DexarAttributes>.activities.isEmpty {
                    session.resumePendingSession()
                } else {
                    checkpointToResume = cp
                    showResumeAlert = true
                }
            }
        }
        .alert("Resume Session?", isPresented: $showResumeAlert, presenting: checkpointToResume) { cp in
            Button("Resume") {
                session.loadPendingCheckpoint(userName: settings.userName)
                session.resumePendingSession()
            }
            Button("Discard", role: .destructive) {
                session.discardPendingSession()
            }
            Button("Cancel", role: .cancel) { }
        } message: { cp in
            Text("Continue '\(cp.currentGoal.isEmpty ? "Untitled session" : cp.currentGoal)' at Loop \(cp.completedLoops.count + 1) (\(cp.phaseRaw == "break" ? "Break" : "Work")).")
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
        .confirmationDialog(
            "Really end session?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("End and Show Overview", role: .destructive) {
                session.forceEndSession()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will stop the timer and show your session overview.")
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
                    progressPhotos: session.progressPhotos,
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
                HStack(spacing: 24) {
                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.secondary)
                    }

                    Button(action: { showAnalytics = true }) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.secondary)
                    }
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
                VStack(spacing: 12) {
                    Text("Work past 30 days")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(1.4)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    activityGraph
                }
                .padding(.horizontal, 28)

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
                    .foregroundStyle(Color.appMutedForeground)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.appMutedForeground.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.appSecondaryBackground)
            .clipShape(Rectangle())
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
                .foregroundStyle(Color.appForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.appSecondaryBackground)
                .clipShape(Rectangle())
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
            Color.appBackground.ignoresSafeArea()

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
            if session.phase == .goalCapture {
                Button(action: session.backToMotivation) {
                    Text("Back")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Button(action: { showEndAlert = true }) {
                    Text("End")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
                    .foregroundStyle(session.isRecording ? Color.appDestructive : Color.appForeground)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.appSecondaryBackground)
                    .clipShape(Rectangle())
                }
                .disabled(session.isProcessingSpeech && !session.isRecording)
            }

            let goals = priorGoals
            if !goals.isEmpty {
                VStack(spacing: 8) {
                    Text("Prior tasks")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.appMutedForeground.opacity(0.7))
                        .textCase(.uppercase)
                        .kerning(1.2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(goals, id: \.self) { g in
                                Button(action: {
                                    goalTranscriptText = g
                                }) {
                                    Text(g)
                                        .font(.caption)
                                        .foregroundStyle(Color.appMutedForeground)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.appSecondaryBackground)
                                        .clipShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.top, 20)
            }

            Spacer()

            if !session.isRecording && !session.isProcessingSpeech {
                Button(action: {
                    captureFieldFocused = false
                    session.confirmGoal()
                }) {
                    Text("Next")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(Color.appForeground)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(Color.appSecondaryBackground)
                        .clipShape(Rectangle())
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
                            .foregroundStyle(Color.appForeground)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.appSecondaryBackground)
                            .clipShape(Rectangle())
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
                let hasPhoto = session.progressPhotoLoops.contains(session.currentLoopNumber)
                Button(action: {
                    showCamera = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: hasPhoto ? "checkmark.circle.fill" : "camera")
                        Text(hasPhoto ? "Photo captured" : "Take progress photo")
                    }
                    .font(.headline.weight(.medium))
                    .foregroundStyle(hasPhoto ? .green : Color.appForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appSecondaryBackground)
                    .clipShape(Rectangle())
                }

                Button(action: {
                    session.selectRoundEndAction(.workFiveMore)
                }) {
                    Text("Work for 5 more minutes")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(Color.appDestructive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.appDestructive.opacity(0.08))
                        .clipShape(Rectangle())
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
                        .clipShape(Rectangle())
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

    private var past30Days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<30).reversed().compactMap { dayOffset in
            calendar.date(byAdding: .day, value: -dayOffset, to: today)
        }
    }

    private func workDuration(forDate date: Date, artifacts: [SessionArtifact]) -> TimeInterval {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return artifacts
            .filter { calendar.isDate($0.date, inSameDayAs: startOfDay) }
            .compactMap { $0.totalDurationWorked }
            .reduce(0, +)
    }

    private func cellColor(for duration: TimeInterval) -> Color {
        if duration == 0 {
            return Color(.systemGray6)
        } else if duration < 600 {
            return Color.purple.opacity(0.18)
        } else if duration < 1500 {
            return Color.purple.opacity(0.4)
        } else if duration < 3000 {
            return Color.purple.opacity(0.65)
        } else {
            return Color.purple
        }
    }

    private var activityGraph: some View {
        let days = past30Days
        let allArtifacts = SessionStore.shared.loadAll()
        
        return HStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { col in
                VStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { row in
                        let index = col * 3 + row
                        if index < days.count {
                            let date = days[index]
                            let duration = workDuration(forDate: date, artifacts: allArtifacts)
                            let isToday = Calendar.current.isDateInToday(date)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cellColor(for: duration))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.primary.opacity(0.35), lineWidth: isToday ? 1.2 : 0)
                                )
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                if col < 9 {
                    Spacer(minLength: 6)
                }
            }
        }
    }

    private var priorGoals: [String] {
        let calendar = Calendar.current
        let all = SessionStore.shared.loadAll()
        var unique: [String] = []
        for a in all {
            let g = a.goal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !g.isEmpty && !unique.contains(g) {
                unique.append(g)
            }
        }
        return Array(unique.prefix(4))
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
                        .foregroundStyle(Color.appForeground)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 18)
                        .background(Color.appSecondaryBackground)
                        .clipShape(Rectangle())
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

struct AnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    
    private var artifacts: [SessionArtifact] {
        SessionStore.shared.loadAll()
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    totalFocusCard
                } header: {
                    Text("Overview")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(1.2)
                }
                .listRowBackground(Color.appSecondaryBackground)
                
                Section {
                    weeklyTrendCard
                } header: {
                    Text("Weekly Focus Trend")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(1.2)
                }
                .listRowBackground(Color.appSecondaryBackground)
                
                if !topCategories.isEmpty {
                    Section {
                        focusCategoriesCard
                    } header: {
                        Text("Focus Distribution")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(1.2)
                    }
                    .listRowBackground(Color.appSecondaryBackground)
                }
                
                Section {
                    flowPacingCard
                } header: {
                    Text("Flow & Pacing Insights")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(1.2)
                }
                .listRowBackground(Color.appSecondaryBackground)
                
                Section {
                    psychologicalWinsCard
                } header: {
                    Text("Psychological Resilience")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(1.2)
                }
                .listRowBackground(Color.appSecondaryBackground)
                
                Section {
                    motivationCorrelationCard
                } header: {
                    Text("Quality by Starting Motivation")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(1.2)
                }
                .listRowBackground(Color.appSecondaryBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.appForeground)
                }
            }
        }
    }
    
    private var totalFocusCard: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatTotalTime(totalSeconds: totalFocusSeconds))
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.appForeground)
                Text("Total Focus Time")
                    .font(.caption)
                    .foregroundStyle(Color.appMutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(streakCount)")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.appForeground)
                Text("Day Streak")
                    .font(.caption)
                    .foregroundStyle(Color.appMutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
    
    private var weeklyTrendCard: some View {
        let data = weeklyTrendData
        let maxHours = max(1.0, data.map(\.hours).max() ?? 0.0)
        
        return VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(data) { item in
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        
                        Text(String(format: "%.1fh", item.hours))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(item.hours > 0 ? Color.appForeground : Color.clear)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(item.hours > 0 ? Color.appForeground : Color.appMutedForeground.opacity(0.15))
                            .frame(height: max(4, CGFloat(item.hours / maxHours) * 100))
                        
                        Text(item.label)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.appMutedForeground)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 140)
        }
        .padding(.vertical, 8)
    }
    
    private var focusCategoriesCard: some View {
        let categories = topCategories
        return VStack(spacing: 12) {
            ForEach(categories) { category in
                VStack(spacing: 6) {
                    HStack {
                        Text(category.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.appForeground)
                        
                        Spacer()
                        
                        Text(String(format: "%.0f%%", category.percentage))
                            .font(.caption)
                            .foregroundStyle(Color.appMutedForeground)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.appTertiaryBackground)
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(Color.appForeground)
                                .frame(width: geometry.size.width * CGFloat(category.percentage / 100.0), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var flowPacingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "hourglass")
                    .font(.title2)
                    .foregroundStyle(Color.appMutedForeground)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Work-Break Harmony")
                        .font(.subheadline.weight(.medium))
                    Text(recoveryBalanceMessage)
                        .font(.caption)
                        .foregroundStyle(Color.appMutedForeground)
                }
            }
            
            Divider()
            
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(Color.appMutedForeground)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Biological Focus Peak")
                        .font(.subheadline.weight(.medium))
                    Text(timeOfDayPeak)
                        .font(.caption)
                        .foregroundStyle(Color.appMutedForeground)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var psychologicalWinsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(Color.appMutedForeground)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Showed Up Anyway")
                        .font(.subheadline.weight(.medium))
                    Text(showedUpAnywayMessage)
                        .font(.caption)
                        .foregroundStyle(Color.appMutedForeground)
                }
            }
            
            Divider()
            
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "bolt.heart.fill")
                    .font(.title2)
                    .foregroundStyle(Color.appMutedForeground)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Average Session Focus Quality")
                        .font(.subheadline.weight(.medium))
                    Text(qualityMessage)
                        .font(.caption)
                        .foregroundStyle(Color.appMutedForeground)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var motivationCorrelationCard: some View {
        let correlations = motivationCorrelations
        
        return VStack(spacing: 14) {
            ForEach(correlations) { correlation in
                VStack(spacing: 6) {
                    HStack {
                        Text(correlation.levelLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.appForeground)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f / 5.0 quality", correlation.averageScore))
                            .font(.caption)
                            .foregroundStyle(Color.appMutedForeground)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.appTertiaryBackground)
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(Color.appForeground)
                                .frame(width: geometry.size.width * CGFloat(correlation.averageScore / 5.0), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            
            Text("Complete focus sessions to see insights")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var totalFocusSeconds: TimeInterval {
        artifacts.compactMap { $0.totalDurationWorked }.reduce(0, +)
    }
    
    private var streakCount: Int {
        let calendar = Calendar.current
        let dates = Array(Set(artifacts.map { calendar.startOfDay(for: $0.date) })).sorted(by: >)
        guard !dates.isEmpty else { return 0 }
        
        let today = calendar.startOfDay(for: Date())
        guard let first = dates.first,
              first == today || calendar.isDate(first, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today)!) else {
            return 0
        }
        
        var streak = 1
        for i in 0..<(dates.count - 1) {
            if let diff = calendar.dateComponents([.day], from: dates[i+1], to: dates[i]).day, diff == 1 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }
    
    private func formatTotalTime(totalSeconds: TimeInterval) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    struct WeeklyFocus: Identifiable {
        let id = UUID()
        let label: String
        let hours: Double
    }
    
    private var weeklyTrendData: [WeeklyFocus] {
        let calendar = Calendar.current
        let now = Date()
        var list: [WeeklyFocus] = []
        
        for offset in (0...3).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: now),
                  let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)) else {
                continue
            }
            let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
            
            let weekArtifacts = artifacts.filter { $0.date >= startOfWeek && $0.date < endOfWeek }
            let seconds = weekArtifacts.compactMap { $0.totalDurationWorked }.reduce(0, +)
            let hours = seconds / 3600.0
            
            let label = offset == 0 ? "This Wk" : "\(offset) wk\(offset == 1 ? "" : "s") ago"
            list.append(WeeklyFocus(label: label, hours: hours))
        }
        return list
    }
    
    struct CategoryShare: Identifiable {
        let id = UUID()
        let name: String
        let percentage: Double
    }
    
    private var topCategories: [CategoryShare] {
        var counts: [String: Int] = [:]
        let stopWords: Set<String> = ["the", "a", "an", "to", "for", "and", "in", "on", "my", "with", "at", "session", "focus", "work", "some", "of", "about", "me", "this", "that", "it"]
        
        for a in artifacts {
            let words = a.goal.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && !stopWords.contains($0) && $0.count > 2 }
            for w in words {
                counts[w, default: 0] += 1
            }
        }
        
        let total = Double(counts.values.reduce(0, +))
        guard total > 0 else { return [] }
        
        return counts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { CategoryShare(name: $0.key.capitalized, percentage: (Double($0.value) / total) * 100) }
    }
    
    private var recoveryBalanceMessage: String {
        let totalSessions = artifacts.count
        guard totalSessions > 0 else { return "Begin focusing to trace your recovery balance." }
        
        let healthySessions = artifacts.filter { $0.loopsCompleted >= 2 }.count
        let percentage = Int((Double(healthySessions) / Double(totalSessions)) * 100)
        
        return "You maintained a sustainable pace in \(percentage)% of sessions (2+ loops), allowing your brain to rest."
    }
    
    private var timeOfDayPeak: String {
        let calendar = Calendar.current
        var morningScores: [Double] = []
        var afternoonScores: [Double] = []
        var eveningScores: [Double] = []
        
        for a in artifacts {
            let hour = calendar.component(.hour, from: a.date)
            if hour >= 5 && hour < 12 {
                morningScores.append(a.score)
            } else if hour >= 12 && hour < 17 {
                afternoonScores.append(a.score)
            } else {
                eveningScores.append(a.score)
            }
        }
        
        var peaks: [(String, Double)] = []
        if !morningScores.isEmpty {
            peaks.append(("Morning", morningScores.reduce(0, +) / Double(morningScores.count)))
        }
        if !afternoonScores.isEmpty {
            peaks.append(("Afternoon", afternoonScores.reduce(0, +) / Double(afternoonScores.count)))
        }
        if !eveningScores.isEmpty {
            peaks.append(("Evening / Night", eveningScores.reduce(0, +) / Double(eveningScores.count)))
        }
        
        guard let best = peaks.max(by: { $0.1 < $1.1 }) else {
            return "Start focusing at different times of day to find your natural peak."
        }
        
        return String(format: "Your peak focus window is %@ with an average score of %.1f/5.0.", best.0, best.1)
    }
    
    private var showedUpAnywayMessage: String {
        let count = artifacts.filter { ($0.motivationLevel ?? 5) <= 2 }.count
        if count == 0 {
            return "You haven't logged sessions starting with low motivation yet."
        }
        return "You successfully started and focused \(count) times when motivation was low. Action creates motivation."
    }
    
    private var qualityMessage: String {
        guard !artifacts.isEmpty else { return "No data yet." }
        let average = artifacts.map { $0.score }.reduce(0, +) / Double(artifacts.count)
        return String(format: "Your average session quality is %.1f out of 5.0.", average)
    }
    
    struct MotivationCorrelation: Identifiable {
        let id = UUID()
        let levelLabel: String
        let averageScore: Double
    }
    
    private var motivationCorrelations: [MotivationCorrelation] {
        let levels = [
            (1...2, "Low / Warmed Up"),
            (3...3, "Steady"),
            (4...5, "Locked In / All In")
        ]
        
        return levels.map { range, label in
            let filtered = artifacts.filter { range.contains($0.motivationLevel ?? 0) }
            let average = filtered.isEmpty ? 0.0 : filtered.map { $0.score }.reduce(0, +) / Double(filtered.count)
            return MotivationCorrelation(levelLabel: label, averageScore: average)
        }
    }
}
