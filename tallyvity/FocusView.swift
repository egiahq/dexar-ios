import SwiftUI
import ActivityKit
import UserNotifications

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
            AnalyticsView(settings: settings)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(formatTodayTime(todayFocusSeconds))
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(todayFocusSeconds > 0 ? Color.appForeground : Color.appMutedForeground.opacity(0.4))
                    .monospacedDigit()
                Text("Today")
                    .font(.system(size: 10, weight: .medium))
                    .kerning(1.4)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 20)

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
                Button(action: session.backToIdle) {
                    Text("Back")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if session.phase == .motivationSelection {
                Button(action: session.backToGoalCapture) {
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
            Spacer()

            VStack(spacing: 28) {
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

            Spacer()

            VStack(spacing: 12) {
                Button(action: { showCamera = true }) {
                    Label("Take Photo", systemImage: "camera")
                        .font(.headline.weight(.medium))
                        .foregroundStyle(Color.appForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.appSecondaryBackground)
                        .clipShape(Rectangle())
                }

                Button(action: session.skipPhoto) {
                    Text("Skip")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appMutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.appTertiaryBackground)
                        .clipShape(Rectangle())
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 48)
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

    private var todayFocusSeconds: TimeInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return SessionStore.shared.loadAll()
            .filter { calendar.startOfDay(for: $0.date) == today }
            .compactMap { $0.totalDurationWorked }
            .reduce(0, +)
    }

    private func formatTodayTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
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
    var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private var artifacts: [SessionArtifact] { SessionStore.shared.loadAll() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    totalFocusCard
                } header: {
                    sectionHeader("Overview")
                }
                .listRowBackground(Color.appSecondaryBackground)

                Section {
                    weeklyTrendCard
                } header: {
                    sectionHeader("Weekly Trend")
                }
                .listRowBackground(Color.appSecondaryBackground)

                Section {
                    focusHeatmapCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.appBackground)
                } header: {
                    sectionHeader("Focus Heatmap")
                }
                .listRowBackground(Color.appBackground)

                Section {
                    peakHoursCard
                } header: {
                    sectionHeader("Peak Hours")
                }
                .listRowBackground(Color.appSecondaryBackground)

                Section {
                    motivationCorrelationCard
                } header: {
                    sectionHeader("Quality by Motivation")
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
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.appForeground)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(1.2)
    }

    // MARK: - Overview card

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

            Divider().frame(height: 50)

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

    // MARK: - Weekly trend

    private var weeklyTrendCard: some View {
        let data = weeklyTrendData
        let maxHours = max(1.0, data.map(\.hours).max() ?? 0.0)
        return VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(data) { item in
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        Text(item.hours > 0 ? String(format: "%.1fh", item.hours) : "")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.appForeground)
                        Rectangle()
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

    // MARK: - Focus heatmap (day-of-week × hour)

    private let heatmapHours = Array(5...23)
    private let heatmapDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var heatmapData: [[Double]] {
        let calendar = Calendar.current
        var grid = Array(repeating: Array(repeating: 0.0, count: 7), count: heatmapHours.count)
        for artifact in artifacts {
            guard let duration = artifact.totalDurationWorked else { continue }
            let weekday = calendar.component(.weekday, from: artifact.date)
            let hour = calendar.component(.hour, from: artifact.date)
            guard let hourIdx = heatmapHours.firstIndex(of: hour) else { continue }
            let dayIdx = (weekday + 5) % 7  // Sun=1 → 6, Mon=2 → 0
            grid[hourIdx][dayIdx] += duration / 60.0
        }
        return grid
    }

    private func heatmapColor(minutes: Double) -> Color {
        switch minutes {
        case 0: return Color.appTertiaryBackground
        case ..<15: return Color.appForeground.opacity(0.20)
        case ..<30: return Color.appForeground.opacity(0.42)
        case ..<60: return Color.appForeground.opacity(0.68)
        default: return Color.appForeground
        }
    }

    private let heatmapLabelWidth: CGFloat = 28
    private let heatmapCellGap: CGFloat = 2
    private let heatmapCellHeight: CGFloat = 13

    private var heatmapViewHeight: CGFloat {
        let rows = CGFloat(heatmapHours.count + 1)
        return rows * heatmapCellHeight + (rows - 1) * heatmapCellGap + 24
    }

    private var focusHeatmapCard: some View {
        let data = heatmapData
        return GeometryReader { geo in
            let cellW = (geo.size.width - heatmapLabelWidth - CGFloat(6) * heatmapCellGap - 32) / 7
            VStack(alignment: .leading, spacing: heatmapCellGap) {
                HStack(spacing: heatmapCellGap) {
                    Color.clear.frame(width: heatmapLabelWidth)
                    ForEach(heatmapDays, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.appMutedForeground)
                            .frame(width: cellW, alignment: .center)
                    }
                }
                ForEach(Array(heatmapHours.enumerated()), id: \.offset) { hIdx, hour in
                    HStack(spacing: heatmapCellGap) {
                        let label = hour == 12 ? "12p" : hour < 12 ? "\(hour)a" : "\(hour - 12)p"
                        Text(hIdx % 3 == 0 ? label : "")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(Color.appMutedForeground)
                            .frame(width: heatmapLabelWidth, alignment: .trailing)
                        ForEach(0..<7, id: \.self) { dIdx in
                            Rectangle()
                                .fill(heatmapColor(minutes: data[hIdx][dIdx]))
                                .frame(width: cellW, height: heatmapCellHeight)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: heatmapViewHeight)
    }

    // MARK: - Peak hours + notification toggle

    private var peakHours: [Int] {
        let calendar = Calendar.current
        var hourMinutes: [Int: Double] = [:]
        for artifact in artifacts {
            guard let duration = artifact.totalDurationWorked else { continue }
            let hour = calendar.component(.hour, from: artifact.date)
            hourMinutes[hour, default: 0] += duration / 60.0
        }
        return hourMinutes
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map(\.key)
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        return hour < 12 ? "\(h)am" : "\(h)pm"
    }

    private var peakHoursCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            let hours = peakHours
            if hours.isEmpty {
                Text("Log sessions at different times to find your peak.")
                    .font(.caption)
                    .foregroundStyle(Color.appMutedForeground)
            } else {
                Text("Most productive: " + hours.map { hourLabel($0) }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground)
            }

            if !hours.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify at peak hours")
                            .font(.subheadline.weight(.medium))
                        Text(hours.map { hourLabel($0) }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Color.appMutedForeground)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settings.peakHourNotificationEnabled },
                        set: { enabled in
                            settings.peakHourNotificationEnabled = enabled
                            if enabled {
                                settings.peakNotificationHours = hours
                                schedulePeakNotifications(hours: hours)
                            } else {
                                cancelPeakNotifications()
                            }
                        }
                    ))
                    .labelsHidden()
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func schedulePeakNotifications(hours: [Int]) {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            for hour in hours {
                let content = UNMutableNotificationContent()
                content.title = "Your peak focus window"
                content.body = "You focus best around \(hourLabel(hour)). Time to start."
                content.sound = .default
                var components = DateComponents()
                components.hour = hour
                components.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "dexar.peak-hour.\(hour)",
                    content: content,
                    trigger: trigger
                )
                try? await center.add(request)
            }
        }
    }

    private func cancelPeakNotifications() {
        let ids = (0..<24).map { "dexar.peak-hour.\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Motivation correlation

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
                        Text(String(format: "%.1f / 5.0", correlation.averageScore))
                            .font(.caption)
                            .foregroundStyle(Color.appMutedForeground)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.appTertiaryBackground).frame(height: 6)
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

    // MARK: - Data helpers

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
            if let diff = calendar.dateComponents([.day], from: dates[i + 1], to: dates[i]).day, diff == 1 {
                streak += 1
            } else { break }
        }
        return streak
    }

    private func formatTotalTime(totalSeconds: TimeInterval) -> String {
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
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
                  let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)) else { continue }
            let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
            let seconds = artifacts.filter { $0.date >= startOfWeek && $0.date < endOfWeek }
                .compactMap { $0.totalDurationWorked }.reduce(0, +)
            let label = offset == 0 ? "This Wk" : "\(offset) wk\(offset == 1 ? "" : "s") ago"
            list.append(WeeklyFocus(label: label, hours: seconds / 3600.0))
        }
        return list
    }

    struct MotivationCorrelation: Identifiable {
        let id = UUID()
        let levelLabel: String
        let averageScore: Double
    }

    private var motivationCorrelations: [MotivationCorrelation] {
        [(1...2, "Low / Warmed Up"), (3...3, "Steady"), (4...5, "Locked In / All In")].map { range, label in
            let filtered = artifacts.filter { range.contains($0.motivationLevel ?? 0) }
            let average = filtered.isEmpty ? 0.0 : filtered.map { $0.score }.reduce(0, +) / Double(filtered.count)
            return MotivationCorrelation(levelLabel: label, averageScore: average)
        }
    }
}
