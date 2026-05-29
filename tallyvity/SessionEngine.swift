import Foundation
import SwiftUI
import AVFoundation
import UIKit
import ActivityKit
import UserNotifications

@MainActor
@Observable
final class SessionEngine {

    enum RoundEndChoice {
        case workFiveMore
        case startBreak
    }

    private enum TimerResult {
        case completed
        case skipped
        case cancelled
    }

    private enum SessionFlowAction {
        case continueNext
        case finish
        case workAgain
    }

    enum Phase: Equatable {
        case idle
        case motivationSelection
        case preparingAudio
        case goalCapture
        case photoBaseline
        case backgroundPrep(loopNumber: Int)
        case workActive(loopNumber: Int)
        case roundEnd
        case photoDelta
        case storing
        case breakTime(loopNumber: Int)
        case nextSessionCountdown(loopNumber: Int)
        case sessionReady
        case sessionReport
        case error(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
              case (.idle, .idle), (.motivationSelection, .motivationSelection), (.preparingAudio, .preparingAudio), (.goalCapture, .goalCapture), (.photoBaseline, .photoBaseline),
                 (.roundEnd, .roundEnd), (.photoDelta, .photoDelta),
                 (.storing, .storing), (.sessionReady, .sessionReady), (.sessionReport, .sessionReport): return true
            case (.backgroundPrep(let a), .backgroundPrep(let b)): return a == b
            case (.workActive(let a), .workActive(let b)): return a == b
            case (.breakTime(let a), .breakTime(let b)): return a == b
            case (.nextSessionCountdown(let a), .nextSessionCountdown(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    var totalLoops: Int = 4

    var workDuration: TimeInterval = 25 * 60
    var shortBreakDuration: TimeInterval = 5 * 60
    var longBreakDuration: TimeInterval = 20 * 60

    private(set) var phase: Phase = .idle
    private(set) var timerProgress: Double = 0
    private(set) var timerElapsed: TimeInterval = 0
    private(set) var currentGoal: String = ""
    private(set) var shortGoal: String = "Work"
    private(set) var memoryRecallText: String? = nil
    private(set) var isRecording: Bool = false
    private(set) var transcript: String = ""
    private(set) var completedLoops: [LoopRecord] = []
    private(set) var finalArtifact: SessionArtifact? = nil
    private(set) var currentLoopAnswers: [String] = []
    private(set) var pendingCheckpoint: SessionStore.SessionCheckpoint? = nil
    private(set) var spokenLine: String = ""
    private(set) var baselinePhoto: UIImage? = nil
    private(set) var finalPhoto: UIImage? = nil
    private(set) var comparisonText: String = ""
    private(set) var progressPhotoLoops: Set<Int> = []

    private let speech: SpeechEngine
    private let gemma: GemmaEngine
    private let store = SessionStore.shared

    private var sessionTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    private var recordingStopped = false
    private var goalCaptureContinuation: CheckedContinuation<Void, Never>?
    private var roundEndContinuation: CheckedContinuation<RoundEndChoice, Never>?
    private var pendingRoundEndChoice: RoundEndChoice?
    private var originalWorkDuration: TimeInterval = 25 * 60
    private var pendingPhoto: UIImage? = nil
    private var photoSkipped = false
    private var timerSkipped = false
    private(set) var currentLoopNumber: Int = 0
    private var haptic = UIImpactFeedbackGenerator(style: .light)
    private var liveActivity: Activity<TallyvityAttributes>?
    private var sessionUserName: String = ""
    private var motivationContinuation: CheckedContinuation<Int, Never>?
    private var pendingMotivation: Int?
    private var sessionMotivationLevel: Int?
    private var needsStarterDecision: Bool = false
    private var wantsToRetryGoal: Bool = false
    private var wantsToGoBackToGoal: Bool = false
    private var wantsToStartNow: Bool = false
    private var startSessionContinuation: CheckedContinuation<Void, Never>?
    private var workStartPrompts: [String] { PromptStore.shared.presets(for: "work_start") }
    private var goalPromptPresets: [String] { PromptStore.shared.presets(for: "goal_capture") }
    private var photoPromptPresets: [String] { PromptStore.shared.presets(for: "photo_baseline") }
    private var roundEndPresets: [String] { PromptStore.shared.presets(for: "round_end") }
    private var breakRecoveryPresets: [String] { PromptStore.shared.presets(for: "break_recovery") }
    private var breakPromptPresets: [String] { PromptStore.shared.presets(for: "break_start") }
    private var nextSessionPromptPresets: [String] { PromptStore.shared.presets(for: "next_session") }
    private var sessionDonePresets: [String] { PromptStore.shared.presets(for: "session_done") }
    private var generatedVoiceLines: [String: [String]] = [:]

    init(speech: SpeechEngine, gemma: GemmaEngine) {
        self.speech = speech
        self.gemma = gemma
    }

    // MARK: - Public API

    func startSession(userName: String) {
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            await self?.runSession(userName: userName)
        }
    }

    func loadPendingCheckpoint(userName: String) {
        guard let checkpoint = store.loadCheckpoint() else { return }
        guard checkpoint.userName == userName || checkpoint.userName.isEmpty || userName.isEmpty else { return }
        pendingCheckpoint = checkpoint
    }

    func resumePendingSession() {
        guard let checkpoint = pendingCheckpoint else { return }
        pendingCheckpoint = nil
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            await self?.resumeSession(from: checkpoint)
        }
    }

    func discardPendingSession() {
        pendingCheckpoint = nil
        store.clearCheckpoint()
    }

    func cancelSession() {
        sessionTask?.cancel()
        sessionTask = nil
        timerTask?.cancel()
        timerTask = nil
        speech.stopAll()

        // Force-stop any active capture loop and release waiting UI continuations.
        recordingStopped = true
        if let motivationContinuation {
            self.motivationContinuation = nil
            motivationContinuation.resume(returning: 3)
        }
        pendingMotivation = nil

        // Reset per-session transient state so a new start cannot reuse stale values.
        currentLoopAnswers = []
        transcript = ""
        isRecording = false
        pendingPhoto = nil
        photoSkipped = false
        timerSkipped = false
        needsStarterDecision = false
        wantsToRetryGoal = false
        wantsToGoBackToGoal = false
        wantsToStartNow = false
        startSessionContinuation?.resume()
        startSessionContinuation = nil
        goalCaptureContinuation?.resume()
        goalCaptureContinuation = nil
        roundEndContinuation?.resume(returning: .startBreak)
        roundEndContinuation = nil
        pendingRoundEndChoice = nil

        endLiveActivity()
        updateScreenAwake(enabled: false)
        store.clearCheckpoint()
        withAnimation { phase = .idle }
    }

    func stopListening() {
        recordingStopped = true
    }

    func skipPhase() {
        timerSkipped = true
    }

    func setBaselinePhoto(_ image: UIImage) {
        pendingPhoto = image
        savePhotoToDisk(image, name: "baseline_photo.jpg")
    }

    func setProgressPhoto(_ image: UIImage) {
        let loop = currentLoopNumber
        progressPhotoLoops.insert(loop)
        savePhotoToDisk(image, name: "progress_photo_\(loop).jpg")
        finalPhoto = image
        savePhotoToDisk(image, name: "final_photo.jpg")
    }

    func savePhotoToDisk(_ image: UIImage, name: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(name)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
    }

    func loadPhotoFromDisk(name: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("photos", isDirectory: true)
        let fileURL = dir.appendingPathComponent(name)
        if let data = try? Data(contentsOf: fileURL) {
            return UIImage(data: data)
        }
        return nil
    }

    func clearPhotosDirectory() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    func skipPhoto() {
        photoSkipped = true
    }

    func dismissReport() {
        withAnimation {
            phase = .idle
            finalArtifact = nil
            completedLoops = []
            currentGoal = ""
            memoryRecallText = nil
            timerProgress = 0
            timerElapsed = 0
            baselinePhoto = nil
            finalPhoto = nil
            comparisonText = ""
            spokenLine = ""
        }
    }

    func submitMotivation(_ level: Int) {
        if let continuation = motivationContinuation {
            motivationContinuation = nil
            continuation.resume(returning: level)
        } else {
            pendingMotivation = level
        }
    }

    func cancelError() {
        withAnimation { phase = .idle }
    }

    func retryGoal() {
        wantsToRetryGoal = true
        recordingStopped = true
        goalCaptureContinuation?.resume()
        goalCaptureContinuation = nil
    }

    func startNow() {
        wantsToStartNow = true
        recordingStopped = true
        photoSkipped = true
        timerSkipped = true
        goalCaptureContinuation?.resume()
        goalCaptureContinuation = nil
    }

    func backToGoal() {
        wantsToGoBackToGoal = true
        recordingStopped = true
        photoSkipped = true
        timerSkipped = true
        startSessionContinuation?.resume()
        startSessionContinuation = nil
        goalCaptureContinuation?.resume()
        goalCaptureContinuation = nil
    }

    func updateGoal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        currentGoal = trimmed.isEmpty ? currentGoal : trimmed
    }

    func updateTranscript(_ text: String) {
        transcript = text
    }

    func toggleRecording() {
        if isRecording {
            recordingStopped = true
        } else {
            recordingStopped = false
            isRecording = true
            try? speech.startRecording()
            Task {
                let deadline = Date().addingTimeInterval(30)
                while !recordingStopped && Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                withAnimation { isRecording = false }
                let text = await speech.transcribeRecording()
                withAnimation {
                    if !text.isEmpty {
                        if self.transcript.isEmpty {
                            self.transcript = text
                        } else {
                            self.transcript += " " + text
                        }
                    }
                }
            }
        }
    }

    func confirmGoal() {
        goalCaptureContinuation?.resume()
        goalCaptureContinuation = nil
    }

    func selectRoundEndAction(_ choice: RoundEndChoice) {
        recordingStopped = true
        speech.stopAll()
        withAnimation {
            switch choice {
            case .workFiveMore:
                phase = .backgroundPrep(loopNumber: currentLoopNumber)
            case .startBreak:
                phase = .storing
            }
        }
        if let continuation = roundEndContinuation {
            continuation.resume(returning: choice)
            roundEndContinuation = nil
        } else {
            pendingRoundEndChoice = choice
        }
    }

    func confirmStartSession() {
        startSessionContinuation?.resume()
        startSessionContinuation = nil
    }

    func playRateCue() {
        speech.playCue(named: "rate")
    }

    var isProcessingSpeech: Bool {
        switch speech.state {
        case .transcribing, .speaking, .loadingModels: return true
        default: return false
        }
    }

    // MARK: - Timer display helpers

    var remainingTime: TimeInterval {
        let total: TimeInterval
        switch phase {
        case .workActive, .backgroundPrep:
            total = workDuration
        case .breakTime:
            total = completedLoops.count >= totalLoops ? longBreakDuration : shortBreakDuration
        default:
            total = workDuration
        }
        return max(0, total - timerElapsed)
    }

    var isWorkPhase: Bool {
        if case .workActive = phase { return true }
        if case .backgroundPrep = phase { return true }
        return false
    }

    var usesAutoStopCapture: Bool {
        true
    }

    // MARK: - Session runner

    private func runSession(userName: String) async {
        guard !Task.isCancelled else { return }
        sessionUserName = userName

        withAnimation { phase = .motivationSelection }
        let motivation = await waitForMotivation()
        guard !Task.isCancelled else { return }
        sessionMotivationLevel = motivation

        withAnimation { phase = .preparingAudio }
        let speechReady = await speech.ensureReady()
        guard speechReady else {
            withAnimation { phase = .error(PromptStore.shared.string(for: "error_models_unavailable")) }
            return
        }

        clearPhotosDirectory()
        progressPhotoLoops = []
        completedLoops = []
        currentGoal = ""
        currentLoopNumber = 1
        pendingPhoto = nil
        photoSkipped = false
        memoryRecallText = nil
        finalArtifact = nil
        sessionMotivationLevel = motivation
        baselinePhoto = nil
        finalPhoto = nil
        comparisonText = ""
        spokenLine = ""
        needsStarterDecision = motivation <= 2

        if needsStarterDecision {
            workDuration = 5 * 60
        }

        originalWorkDuration = workDuration

        var sessionConfirmed = false
        while !sessionConfirmed && !Task.isCancelled {
            wantsToGoBackToGoal = false

            var goalAccepted = false
            while !goalAccepted && !Task.isCancelled {
                wantsToRetryGoal = false
                wantsToStartNow = false
                withAnimation { phase = .goalCapture }
                await sayFixed(cue: "goal_prompt", fallback: PromptStore.shared.fallback(for: "goal_capture"))
                guard !Task.isCancelled else { return }

                if !currentGoal.isEmpty && transcript.isEmpty {
                    transcript = currentGoal
                }

                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    goalCaptureContinuation = cont
                }
                guard !Task.isCancelled else { return }

                if wantsToRetryGoal { continue }

                currentGoal = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Focus session" : transcript
                shortGoal = String(currentGoal.prefix(20))
                goalAccepted = true
            }

            guard !Task.isCancelled else { return }

            if !wantsToStartNow {
                // 2. Photo baseline
                await sayFixed(cue: "photo_baseline_prompt", fallback: selectVoiceLine(
                    cue: "photo_baseline",
                    fallback: photoPromptPresets,
                    replacements: ["goal": currentGoal]
                ))
                withAnimation { phase = .photoBaseline }

                pendingPhoto = nil
                photoSkipped = false
                let deadline = Date().addingTimeInterval(15)
                while !Task.isCancelled && !photoSkipped && !wantsToGoBackToGoal && Date() < deadline {
                    if let photo = pendingPhoto {
                        baselinePhoto = photo
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }

                guard !Task.isCancelled else { return }
                if wantsToGoBackToGoal { continue }
            }

            // 3. Session ready — user confirms start or goes back to edit goal
            withAnimation { phase = .sessionReady }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                startSessionContinuation = cont
            }
            guard !Task.isCancelled else { return }
            if wantsToGoBackToGoal { continue }

            sessionConfirmed = true
        }

        guard !Task.isCancelled else { return }

        // Begin work loop
        persistCheckpoint(userName: userName)
        await mainLoop()
    }

    private func runLoop() async -> SessionFlowAction {
        guard !Task.isCancelled else { return .finish }

        withAnimation { phase = .backgroundPrep(loopNumber: currentLoopNumber) }
        persistCheckpoint()

        if needsStarterDecision && currentLoopNumber == 1 {
            sayFixedNonBlocking(cue: "motivation_low_framing_prompt", fallback: PromptStore.shared.fallback(for: "motivation_low_framing"))
        } else {
            sayFixedNonBlocking(cue: "work_start_prompt", fallback: workStartPrompt())
        }
        updateScreenAwake(enabled: true)
        withAnimation { phase = .workActive(loopNumber: currentLoopNumber) }
        persistCheckpoint()
        startLiveActivity(duration: workDuration, isWork: true, loopNumber: currentLoopNumber)
        let timerResult = await runTimer(duration: workDuration)
        endLiveActivity()
        guard !Task.isCancelled else { updateScreenAwake(enabled: false); return .finish }
        guard timerResult != .cancelled else { updateScreenAwake(enabled: false); return .finish }

        withAnimation { phase = .roundEnd }
        haptic.impactOccurred(intensity: 0.7)
        if timerResult == .completed || timerResult == .skipped {
            speech.playCue(named: "end")
        }
        updateScreenAwake(enabled: false)

        if needsStarterDecision {
            needsStarterDecision = false
            await sayFixed(cue: "starter_continue_prompt", fallback: PromptStore.shared.fallback(for: "starter_continue"))
            let decision = await listen(maxDuration: 6).lowercased()
            if decision.contains("no") || decision.contains("stop") {
                return .finish
            }
            workDuration = 25 * 60
        }

        return await runRoundEnd()
    }

    private func runRoundEnd() async -> SessionFlowAction {
        guard !Task.isCancelled else { return .finish }

        withAnimation { phase = .roundEnd }
        persistCheckpoint()

        let choice: RoundEndChoice
        if let pending = pendingRoundEndChoice {
            choice = pending
            pendingRoundEndChoice = nil
        } else {
            choice = await withCheckedContinuation { (cont: CheckedContinuation<RoundEndChoice, Never>) in
                roundEndContinuation = cont
            }
        }

        guard !Task.isCancelled else { return .finish }

        switch choice {
        case .workFiveMore:
            workDuration = 5 * 60
            return .workAgain
        case .startBreak:
            workDuration = originalWorkDuration
            withAnimation {
                phase = .storing
                completedLoops.append(LoopRecord(
                    goalText: currentGoal,
                    answers: [],
                    score: 0,
                    scoreReason: ""
                ))
            }

            guard !Task.isCancelled else { return .finish }

            let isLong = completedLoops.count >= totalLoops
            let breakDuration = isLong ? longBreakDuration : shortBreakDuration
            let breakMinutes = max(1, Int(round(breakDuration / 60)))

            sayFixedNonBlocking(cue: "break_start_prompt", fallback: selectVoiceLine(
                cue: "break_start",
                fallback: breakPromptPresets,
                replacements: ["breakMinutes": "\(breakMinutes) minutes", "goal": currentGoal]
            ))

            if !isLong { currentLoopNumber += 1 }
            persistCheckpoint()
            return .continueNext
        }
    }

    private func runBreak() async -> SessionFlowAction {
        guard !Task.isCancelled else { return .finish }

        let isLong = completedLoops.count >= totalLoops
        let duration = isLong ? longBreakDuration : shortBreakDuration

        guard duration > 0 else {
            return isLong ? .finish : .continueNext
        }

        withAnimation { phase = .breakTime(loopNumber: currentLoopNumber) }
        persistCheckpoint()
        sayFixedNonBlocking(cue: "break_recovery_prompt", fallback: breakRecoveryPresets.randomElement() ?? "")
        startLiveActivity(duration: duration, isWork: false, loopNumber: currentLoopNumber)
        await runTimer(duration: duration)
        endLiveActivity()
        guard !Task.isCancelled else { return .finish }

        if isLong {
            return .finish
        }

        // Transition screen before next loop
        withAnimation { phase = .nextSessionCountdown(loopNumber: currentLoopNumber) }
        persistCheckpoint()
        await sayFixed(cue: "next_session_prompt", fallback: selectVoiceLine(
            cue: "next_session",
            fallback: nextSessionPromptPresets,
            replacements: ["sessionNumber": "\(currentLoopNumber)", "goal": currentGoal]
        ))
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return .finish }

        return .continueNext
    }

    private func finishSession(finalAnswers: [String] = []) async {
        guard !Task.isCancelled else { return }
        withAnimation { phase = .storing }

        let names = sessionUserName.isEmpty ? "there" : sessionUserName

        // Start processing background tasks concurrently with session end audio
        Task {
            await gemma.generate(prompt: GemmaPrompts.createArtifact(goal: currentGoal, loops: completedLoops, finalAnswers: finalAnswers))
            let artifactJSON = gemma.output
            
            var blocker = ""
            var intentNext = ""
            if let data = artifactJSON.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                blocker = dict["blocker"] ?? ""
                intentNext = dict["intent_next"] ?? ""
            }

            await gemma.generate(prompt: GemmaPrompts.closingSentence(
                name: names, goal: currentGoal, loops: completedLoops,
                blocker: blocker, intentNext: intentNext
            ))
            var closing = gemma.output.trimmingCharacters(in: .whitespacesAndNewlines)

            // Clean up closing sentence (keep existing logic)
            let exclamationsCount = closing.filter { $0 == "!" }.count
            if exclamationsCount >= 2 {
                closing = ""
            } else {
                let prefixes = ["Well done", "Great job", "Amazing", "Fantastic", "You did", "Excellent work"]
                for prefix in prefixes {
                    if closing.lowercased().hasPrefix(prefix.lowercased()) {
                        let start = closing.index(closing.startIndex, offsetBy: prefix.count)
                        var remainder = closing[start...]
                        while remainder.hasPrefix(",") || remainder.hasPrefix(" ") {
                            remainder.removeFirst()
                        }
                        if let firstChar = remainder.first {
                            closing = String(firstChar).uppercased() + String(remainder.dropFirst())
                        } else {
                            closing = ""
                        }
                        break
                    }
                }
            }

            let artifact = SessionArtifact(
                id: UUID().uuidString,
                date: Date(),
                goal: currentGoal,
                motivationLevel: sessionMotivationLevel,
                score: Double(completedLoops.map(\.score).reduce(0, +)) / Double(max(completedLoops.count, 1)),
                blocker: blocker,
                intentNext: intentNext,
                loopsCompleted: completedLoops.count,
                closingSentence: closing,
                finalAnswers: finalAnswers
            )
            
            // Save in background
            Task.detached(priority: .background) {
                SessionStore.shared.save(artifact)
                SessionStore.shared.clearCheckpoint()
            }

            // Sync back to UI when ready
            await MainActor.run {
                withAnimation { 
                    self.finalArtifact = artifact
                    self.phase = .sessionReport
                }
            }
            
            if !closing.isEmpty { await say(closing) }
        }

        // Play feedback immediately
        await sayFixed(cue: "session_done_prompt", fallback: selectVoiceLine(
            cue: "session_done",
            fallback: sessionDonePresets,
            replacements: ["goal": currentGoal]
        ))
    }

    // MARK: - Timer

    private func runTimer(duration: TimeInterval) async -> TimerResult {
        guard duration > 0, !Task.isCancelled else { return .cancelled }

        timerElapsed = 0
        timerProgress = 0
        timerSkipped = false

        let clock = ContinuousClock()
        let start = clock.now

        while true {
            guard !Task.isCancelled else { return .cancelled }  // cancel → do NOT set progress = 1
            guard !timerSkipped else { break }       // skip  → fall through to set progress = 1

            let d = clock.now - start
            let elapsed = Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
            timerElapsed = min(elapsed, duration)
            timerProgress = min(elapsed / duration, 1.0)

            // 5-min haptics (only meaningful for work timers ≥ 5 min)
            if duration >= 300 {
                let prevElapsed = max(0, elapsed - 0.15)
                if Int(elapsed / 300) > Int(prevElapsed / 300) && elapsed > 1 {
                    haptic.impactOccurred(intensity: 0.25)
                }
            }

            if timerProgress >= 1.0 { break }

            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return .cancelled  // CancellationError → hard exit, do NOT complete timer
            }
        }

        // Only reached on natural finish or skip — not on cancel
        let skipped = timerSkipped
        timerProgress = 1.0
        timerElapsed = duration
        return skipped ? .skipped : .completed
    }

    // MARK: - Audio helpers

    private func say(_ text: String) async {
        guard !text.isEmpty, !Task.isCancelled else { return }
        withAnimation { spokenLine = text }
    }

    private func sayFixed(cue: String, fallback: String) async {
        guard !Task.isCancelled else { return }
        await say(fallback)
    }

    private func sayNonBlocking(_ text: String) {
        guard !text.isEmpty else { return }
        withAnimation { spokenLine = text }
    }

    private func sayFixedNonBlocking(cue: String, fallback: String) {
        sayNonBlocking(fallback)
    }

    private func listen(maxDuration: TimeInterval, silenceThreshold: TimeInterval = 2.5) async -> String {
        recordingStopped = false
        withAnimation {
            isRecording = true
        }
        try? speech.startRecording()

        let silenceLevel: Float = 0.04
        let deadline = Date().addingTimeInterval(maxDuration)
        var silentStart: Date? = nil
        while !Task.isCancelled && !recordingStopped && Date() < deadline {
            if let loudness = speech.currentInputLevel {
                if loudness < silenceLevel {
                    if silentStart == nil { silentStart = Date() }
                    if let silentStart, Date().timeIntervalSince(silentStart) >= silenceThreshold {
                        recordingStopped = true
                    }
                } else {
                    silentStart = nil
                }
            }
            try? await Task.sleep(for: .milliseconds(60))
        }

        withAnimation { isRecording = false }
        let text = await speech.transcribeRecording()
        withAnimation {
            if !text.isEmpty {
                if transcript.isEmpty {
                    transcript = text
                } else {
                    transcript += " " + text
                }
            }
        }
        return text
    }

    private func waitForPhoto(timeout: TimeInterval) async -> UIImage? {
        let deadline = Date().addingTimeInterval(timeout)
        pendingPhoto = nil
        photoSkipped = false
        while !Task.isCancelled && !photoSkipped && Date() < deadline {
            if let photo = pendingPhoto { return photo }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return pendingPhoto
    }

    // MARK: - Helpers

    private func workStartPrompt() -> String {
        let minutes = max(1, Int(round(workDuration / 60)))
        let minuteText = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        let template = workStartPrompts.randomElement() ?? "Lets go. {minutes}."
        return template.replacingOccurrences(of: "{minutes}", with: minuteText)
    }

    private func selectVoiceLine(cue: String, fallback: [String], replacements: [String: String]) -> String {
        let generated = generatedVoiceLines[cue] ?? []
        let pool = generated.isEmpty ? fallback : generated
        var line = pool.randomElement() ?? fallback.first ?? ""
        for (key, value) in replacements {
            line = line.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return line
    }



    private func waitForMotivation() async -> Int {
        if let pendingMotivation {
            self.pendingMotivation = nil
            return pendingMotivation
        }
        return await withCheckedContinuation { cont in
            motivationContinuation = cont
        }
    }

    private func persistCheckpoint(userName: String = "") {
        guard phase != .idle, phase != .sessionReport else { return }
        let currentLoops = completedLoops
        let currentAnswers = currentLoopAnswers
        let currentNumber = currentLoopNumber
        let goal = currentGoal
        let motivation = sessionMotivationLevel
        let total = totalLoops
        let work = workDuration
        let short = shortBreakDuration
        let long = longBreakDuration
        let currentPhase = phase

        let phaseTag = phaseCheckpointTag(currentPhase)

        Task.detached(priority: .background) {
            SessionStore.shared.saveCheckpoint(.init(
                userName: userName,
                phaseRaw: phaseTag,
                currentGoal: goal,
                completedLoops: currentLoops,
                currentLoopAnswers: currentAnswers,
                currentLoopNumber: currentNumber,
                motivationLevel: motivation,
                totalLoops: total,
                workDuration: work,
                shortBreakDuration: short,
                longBreakDuration: long,
                savedAt: Date()
            ))
        }
    }

    private func mainLoop() async {
        while !Task.isCancelled {
            let action = await runLoop()
            if action == .finish { break }
            if action == .workAgain { continue }

            if action == .continueNext {
                let breakAction = await runBreak()
                if breakAction == .finish { break }
            }
        }
        guard !Task.isCancelled else { return }
        await capturePhotoDelta()
        guard !Task.isCancelled else { return }
        await finishSession()
    }

    private func capturePhotoDelta() async {
        guard let baseline = baselinePhoto, !Task.isCancelled else { return }
        withAnimation { phase = .photoDelta }
        pendingPhoto = nil
        photoSkipped = false
        let final = await waitForPhoto(timeout: 60)
        guard !Task.isCancelled else { return }
        guard let final else { return }
        withAnimation { finalPhoto = final }
        let prompt = """
        The first image is a workspace at the START of a focus session. The second image is the SAME workspace at the END. The goal was: \(currentGoal).
        Describe the concrete visual differences between the two images and what progress they show. Be specific and factual. Two or three sentences.
        """
        let result = await gemma.compareImages(baseline, final, prompt: prompt)
        withAnimation { comparisonText = result }
    }

    private func resumeSession(from checkpoint: SessionStore.SessionCheckpoint) async {
        sessionUserName = checkpoint.userName
        completedLoops = checkpoint.completedLoops
        currentLoopAnswers = checkpoint.currentLoopAnswers
        currentLoopNumber = max(1, checkpoint.currentLoopNumber)
        currentGoal = checkpoint.currentGoal
        sessionMotivationLevel = checkpoint.motivationLevel
        totalLoops = min(6, max(1, checkpoint.totalLoops ?? 4))
        workDuration = checkpoint.workDuration
        shortBreakDuration = checkpoint.shortBreakDuration
        longBreakDuration = checkpoint.longBreakDuration
        originalWorkDuration = checkpoint.workDuration

        baselinePhoto = loadPhotoFromDisk(name: "baseline_photo.jpg")
        finalPhoto = loadPhotoFromDisk(name: "final_photo.jpg")
        progressPhotoLoops = []
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("photos", isDirectory: true)
        for i in 1...totalLoops {
            let fileURL = dir.appendingPathComponent("progress_photo_\(i).jpg")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                progressPhotoLoops.insert(i)
            }
        }

        withAnimation { phase = .preparingAudio }
        let speechReady = await speech.ensureReady()
        guard speechReady else {
            withAnimation { phase = .error(PromptStore.shared.string(for: "error_models_unavailable")) }
            return
        }
        guard !Task.isCancelled else { return }

        if checkpoint.phaseRaw == "break" {
            let breakResult = await runBreak()
            if breakResult == .continueNext {
                await mainLoop()
            } else {
                guard !Task.isCancelled else { return }
                await capturePhotoDelta()
                guard !Task.isCancelled else { return }
                await finishSession()
            }
        } else {
            await mainLoop()
        }
    }

    private func phaseCheckpointTag(_ phase: Phase) -> String {
        switch phase {
        case .breakTime: return "break"
        case .workActive, .backgroundPrep: return "work"
        default: return "other"
        }
    }

    private func updateScreenAwake(enabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = enabled
    }

    // MARK: - Live Activity

    private func startLiveActivity(duration: TimeInterval, isWork: Bool, loopNumber: Int) {
        let info = ActivityAuthorizationInfo()
        print("[LiveActivity] areActivitiesEnabled=\(info.areActivitiesEnabled) frequentUpdatesEnabled=\(info.frequentPushesEnabled)")
        guard info.areActivitiesEnabled else {
            print("[LiveActivity] blocked — user may have disabled in Settings > [App] > Live Activities")
            return
        }
        endLiveActivity()
        let attributes = TallyvityAttributes(goal: currentGoal, shortGoal: shortGoal, totalLoops: totalLoops)
        let state = TallyvityAttributes.ContentState(
            endDate: Date().addingTimeInterval(duration),
            isWork: isWork,
            loopNumber: loopNumber
        )
        let content = ActivityContent(
            state: state,
            staleDate: Date().addingTimeInterval(duration + 60),
            relevanceScore: 100
        )
        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("[LiveActivity] started id=\(liveActivity?.id ?? "nil") state=\(String(describing: liveActivity?.activityState))")
        } catch {
            print("[LiveActivity] request failed: \(error)")
        }
    }

    private func updateLiveActivity(remainingDuration: TimeInterval, isWork: Bool, loopNumber: Int) {
        guard let activity = liveActivity else { return }
        let state = TallyvityAttributes.ContentState(
            endDate: Date().addingTimeInterval(remainingDuration),
            isWork: isWork,
            loopNumber: loopNumber
        )
        Task { await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(remainingDuration + 60))) }
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        liveActivity = nil
        Task { await activity.end(dismissalPolicy: .immediate) }
    }
}
