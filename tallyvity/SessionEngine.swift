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
    var noBreak: Bool = false

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
    private(set) var finalPhotos: [UIImage] = []
    var finalPhoto: UIImage? { finalPhotos.last }
    private(set) var progressPhotos: [Int: [UIImage]] = [:]
    private(set) var comparisonText: String = ""
    private(set) var progressPhotoLoops: Set<Int> = []
    private(set) var reflectionTranscript: String = ""

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
    private(set) var currentLoopDuration: TimeInterval = 0
    private var haptic = UIImpactFeedbackGenerator(style: .light)
    private var liveActivity: Activity<DexarAttributes>?
    private var timerEndDate: Date?
    private let phaseEndNotificationIdentifier = "dexar.phase-end"
    private var sessionUserName: String = ""
    private var motivationContinuation: CheckedContinuation<Int, Never>?
    private var pendingMotivation: Int?
    private var sessionMotivationLevel: Int?
    private var needsStarterDecision: Bool = false
    private var wantsToRetryGoal: Bool = false
    private var wantsToGoBackToGoal: Bool = false
    private var wantsToGoBackToMotivation: Bool = false
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
        // Reconnect to existing live activity if one is running
        self.liveActivity = Activity<DexarAttributes>.activities.first
        if let activity = self.liveActivity {
            self.timerEndDate = activity.content.state.endDate
        }
    }

    // MARK: - Public API

    func startSession(userName: String) {
        sessionUserName = userName
        sessionTask?.cancel()
        sessionTask = Task { [weak self] in
            await self?.runSession(userName: userName)
        }
    }

    func loadPendingCheckpoint(userName: String) {
        guard let checkpoint = store.loadCheckpoint() else { return }
        guard checkpoint.userName == userName || checkpoint.userName.isEmpty || userName.isEmpty else { return }
        pendingCheckpoint = checkpoint
        if sessionUserName.isEmpty { sessionUserName = checkpoint.userName }
    }

    func resumePendingSession() {
        let checkpoint = pendingCheckpoint ?? store.loadCheckpoint()
        guard let checkpoint = checkpoint else { return }
        pendingCheckpoint = nil
        if sessionUserName.isEmpty { sessionUserName = checkpoint.userName }
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
        // Capture any final elapsed time before zeroing out
        let finalElapsed = timerElapsed
        
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
        
        // If we were in a work phase, we should ideally record the progress, 
        // but cancelSession is currently destructive. 
        // For now, we just ensure we don't leak background tasks.

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
        cancelPhaseEndNotification()
        updateScreenAwake(enabled: false)
        store.clearCheckpoint()
        timerEndDate = nil
        sessionUserName = ""
        timerElapsed = 0
        isOvertime = false
        withAnimation { phase = .idle }
    }

    func forceEndSession() {
        timerTask?.cancel()
        timerTask = nil
        sessionTask?.cancel()
        sessionTask = nil
        speech.stopAll()
        recordingStopped = true
        isRecording = false

        if let motivationContinuation {
            self.motivationContinuation = nil
            motivationContinuation.resume(returning: 3)
        }
        pendingMotivation = nil

        startSessionContinuation?.resume()
        startSessionContinuation = nil
        goalCaptureContinuation?.resume()
        goalCaptureContinuation = nil
        roundEndContinuation?.resume(returning: .startBreak)
        roundEndContinuation = nil
        pendingRoundEndChoice = nil

        if isWorkPhase && timerElapsed > 0 {
            currentLoopDuration += timerElapsed
        }
        if currentLoopDuration > 0 {
            completedLoops.append(LoopRecord(
                goalText: currentGoal,
                answers: [],
                score: 0,
                scoreReason: "",
                duration: currentLoopDuration
            ))
            currentLoopDuration = 0
        }

        endLiveActivity()
        cancelPhaseEndNotification()
        updateScreenAwake(enabled: false)
        store.clearCheckpoint()

        let totalDuration = completedLoops.reduce(0.0) { $0 + ($1.duration ?? 0.0) }
        let loopDurations = completedLoops.map { $0.duration ?? 0.0 }
        let goalText = currentGoal.isEmpty ? "Focus session" : currentGoal

        let artifact = SessionArtifact(
            id: UUID().uuidString,
            date: Date(),
            goal: goalText,
            motivationLevel: sessionMotivationLevel,
            score: completedLoops.isEmpty ? 0 : Double(completedLoops.map(\.score).reduce(0, +)) / Double(completedLoops.count),
            blocker: "",
            intentNext: "",
            loopsCompleted: completedLoops.count,
            closingSentence: "Session ended early.",
            finalAnswers: [],
            totalDurationWorked: totalDuration,
            loopDurations: loopDurations,
            totalLoops: totalLoops
        )

        store.save(artifact)

        withAnimation {
            self.finalArtifact = artifact
            self.phase = .sessionReport
        }
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
        addProgressPhoto(image)
    }

    func addProgressPhoto(_ image: UIImage) {
        let loop = currentLoopNumber
        progressPhotoLoops.insert(loop)
        var currentList = progressPhotos[loop] ?? []
        currentList.append(image)
        progressPhotos[loop] = currentList
        
        let index = currentList.count - 1
        savePhotoToDisk(image, name: "progress_photo_\(loop)_\(index).jpg")
        persistCheckpoint()
    }

    func deleteProgressPhoto(at index: Int, inLoop loop: Int) {
        guard var currentList = progressPhotos[loop], currentList.indices.contains(index) else { return }
        currentList.remove(at: index)
        if currentList.isEmpty {
            progressPhotos.removeValue(forKey: loop)
            progressPhotoLoops.remove(loop)
        } else {
            progressPhotos[loop] = currentList
        }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("photos", isDirectory: true)
        
        var i = 0
        while true {
            let fileURL = dir.appendingPathComponent("progress_photo_\(loop)_\(i).jpg")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
                i += 1
            } else {
                break
            }
        }
        
        if let remaining = progressPhotos[loop] {
            for (idx, img) in remaining.enumerated() {
                savePhotoToDisk(img, name: "progress_photo_\(loop)_\(idx).jpg")
            }
        }
        
        persistCheckpoint()
    }

    func addFinalPhoto(_ image: UIImage) {
        finalPhotos.append(image)
        let index = finalPhotos.count - 1
        savePhotoToDisk(image, name: "final_photo_\(index).jpg")
        pendingPhoto = image
        persistCheckpoint()
    }

    func deleteFinalPhoto(at index: Int) {
        guard finalPhotos.indices.contains(index) else { return }
        finalPhotos.remove(at: index)
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("photos", isDirectory: true)
        
        var i = 0
        while true {
            let fileURL = dir.appendingPathComponent("final_photo_\(i).jpg")
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
                i += 1
            } else {
                break
            }
        }
        
        for (idx, img) in finalPhotos.enumerated() {
            savePhotoToDisk(img, name: "final_photo_\(idx).jpg")
        }
        
        pendingPhoto = finalPhotos.last
        persistCheckpoint()
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
        if let continuation = photoDeltaContinuation {
            photoDeltaContinuation = nil
            continuation.resume()
        }
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
            finalPhotos = []
            progressPhotos = [:]
            comparisonText = ""
            spokenLine = ""
            reflectionTranscript = ""
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

    func backToMotivation() {
        wantsToGoBackToMotivation = true
        recordingStopped = true
        photoSkipped = true
        timerSkipped = true
        startSessionContinuation?.resume()
        startSessionContinuation = nil
        goalCaptureContinuation?.resume()
        goalCaptureContinuation = nil
    }

    func backToGoalCapture() {
        wantsToGoBackToGoal = true
        recordingStopped = true
        if let c = motivationContinuation {
            motivationContinuation = nil
            c.resume(returning: pendingMotivation ?? 3)
        }
        pendingMotivation = nil
    }

    func backToIdle() {
        cancelSession()
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
            Task {
                let ready = await speech.ensureReady()
                guard ready else { return }
                guard !recordingStopped else { return }
                isRecording = true
                try? speech.startRecording()
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

    func toggleReflectionRecording() {
        if isRecording {
            recordingStopped = true
        } else {
            reflectionTranscript = ""
            recordingStopped = false
            Task {
                let ready = await speech.ensureReady()
                guard ready else { return }
                guard !recordingStopped else { return }
                isRecording = true
                try? speech.startRecording()
                let deadline = Date().addingTimeInterval(60)
                while !recordingStopped && Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                withAnimation { isRecording = false }
                let text = await speech.transcribeRecording()
                withAnimation { self.reflectionTranscript = text }
            }
        }
    }

    var isProcessingSpeech: Bool {
        switch speech.state {
        case .transcribing, .speaking: return true
        default: return false
        }
    }

    var isVoiceLoading: Bool {
        if case .loadingModels = speech.state { return true }
        return false
    }

    // MARK: - Timer display helpers

    private(set) var isOvertime: Bool = false

    var remainingTime: TimeInterval {
        if isActiveTimerPhase, let timerEndDate {
            let r = timerEndDate.timeIntervalSinceNow
            if case .workActive = phase { return r }
            return max(0, r)
        }

        let total: TimeInterval
        switch phase {
        case .workActive, .backgroundPrep:
            total = workDuration
        case .breakTime:
            total = (totalLoops > 0 && completedLoops.count >= totalLoops) ? longBreakDuration : shortBreakDuration
        default:
            total = workDuration
        }
        return max(0, total - timerElapsed)
    }

    private var isActiveTimerPhase: Bool {
        if case .workActive = phase { return true }
        if case .backgroundPrep = phase { return true }
        if case .breakTime = phase { return true }
        return false
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

        clearPhotosDirectory()
        progressPhotoLoops = []
        progressPhotos = [:]
        completedLoops = []
        currentGoal = ""
        currentLoopNumber = 1
        currentLoopDuration = 0
        pendingPhoto = nil
        photoSkipped = false
        memoryRecallText = nil
        finalArtifact = nil
        baselinePhoto = nil
        finalPhotos = []
        comparisonText = ""
        spokenLine = ""

        var sessionConfirmed = false
        while !sessionConfirmed && !Task.isCancelled {
            wantsToGoBackToGoal = false

            // 1. Goal capture (first)
            var goalAccepted = false
            while !goalAccepted && !Task.isCancelled {
                wantsToRetryGoal = false
                wantsToStartNow = false
                withAnimation { phase = .goalCapture }
                guard !Task.isCancelled else { return }

                if !currentGoal.isEmpty && transcript.isEmpty {
                    transcript = currentGoal
                }

                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    goalCaptureContinuation = cont
                }
                guard !Task.isCancelled else { return }

                if Task.isCancelled { return }
                if wantsToRetryGoal { continue }

                currentGoal = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Focus session" : transcript
                shortGoal = String(currentGoal.prefix(20))
                goalAccepted = true
            }

            guard !Task.isCancelled else { return }

            // 2. Motivation selection
            wantsToGoBackToGoal = false
            withAnimation { phase = .motivationSelection }
            let motivation = await waitForMotivation()
            guard !Task.isCancelled else { return }

            if wantsToGoBackToGoal { continue }

            sessionMotivationLevel = motivation



            needsStarterDecision = motivation <= 2
            if needsStarterDecision {
                workDuration = 5 * 60
            }
            originalWorkDuration = workDuration

            if !wantsToStartNow {
                // 4. Photo baseline
                await sayFixed(cue: "photo_baseline_prompt", fallback: selectVoiceLine(
                    cue: "photo_baseline",
                    fallback: photoPromptPresets,
                    replacements: ["goal": currentGoal]
                ))
                withAnimation { phase = .photoBaseline }

                pendingPhoto = nil
                photoSkipped = false
                while !Task.isCancelled && !photoSkipped && !wantsToGoBackToGoal {
                    if let photo = pendingPhoto {
                        baselinePhoto = photo
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }

                guard !Task.isCancelled else { return }
                if wantsToGoBackToGoal { continue }
            }

            // 5. Session ready — user confirms start or goes back to edit goal
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
        
        let workEndDate = Date().addingTimeInterval(workDuration)
        timerEndDate = workEndDate
        persistCheckpoint()
        
        startLiveActivity(duration: workDuration, isWork: true, loopNumber: currentLoopNumber, endDate: workEndDate)
        let timerResult = await runTimer(duration: workDuration, totalDuration: workDuration, endDate: workEndDate)
        if timerResult == .completed {
            isOvertime = true
            markLiveActivityOvertime(loopNumber: currentLoopNumber)
        }
        isOvertime = false
        currentLoopDuration += timerElapsed
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
        timerEndDate = nil // No active timer during round end
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
                    scoreReason: "",
                    duration: currentLoopDuration
                ))
                currentLoopDuration = 0
            }

            guard !Task.isCancelled else { return .finish }

            let isLong = totalLoops > 0 && completedLoops.count >= totalLoops
            let breakDuration = isLong ? longBreakDuration : shortBreakDuration
            let breakMinutes = max(1, Int(round(breakDuration / 60)))

            sayFixedNonBlocking(cue: "break_start_prompt", fallback: selectVoiceLine(
                cue: "break_start",
                fallback: breakPromptPresets,
                replacements: ["breakMinutes": "\(breakMinutes) minutes", "goal": currentGoal]
            ))

            if !isLong { currentLoopNumber += 1 }
            timerEndDate = nil
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
        
        let breakEndDate = Date().addingTimeInterval(duration)
        timerEndDate = breakEndDate
        persistCheckpoint()
        
        sayFixedNonBlocking(cue: "break_recovery_prompt", fallback: breakRecoveryPresets.randomElement() ?? "")
        startLiveActivity(duration: duration, isWork: false, loopNumber: currentLoopNumber, endDate: breakEndDate)
        await runTimer(duration: duration, totalDuration: duration, endDate: breakEndDate)
        endLiveActivity()
        guard !Task.isCancelled else { return .finish }

        if isLong {
            return .finish
        }

        // Transition screen before next loop
        withAnimation { phase = .nextSessionCountdown(loopNumber: currentLoopNumber) }
        timerEndDate = nil
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
        endLiveActivity()
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

            let totalDuration = completedLoops.reduce(0.0) { $0 + ($1.duration ?? 0.0) }
            let loopDurations = completedLoops.map { $0.duration ?? 0.0 }

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
                finalAnswers: finalAnswers,
                totalDurationWorked: totalDuration,
                loopDurations: loopDurations,
                totalLoops: totalLoops
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

    private func runTimer(
        duration: TimeInterval,
        totalDuration: TimeInterval? = nil,
        endDate: Date? = nil
    ) async -> TimerResult {
        guard duration > 0, !Task.isCancelled else { return .cancelled }

        let resolvedEndDate = endDate ?? Date().addingTimeInterval(duration)
        let resolvedTotalDuration = max(totalDuration ?? duration, duration)

        timerSkipped = false
        timerEndDate = resolvedEndDate
        timerElapsed = min(max(0, resolvedTotalDuration - max(0, resolvedEndDate.timeIntervalSinceNow)), resolvedTotalDuration)
        timerProgress = min(timerElapsed / resolvedTotalDuration, 1.0)
        persistCheckpoint()

        while true {
            guard !Task.isCancelled else { return .cancelled }
            guard !timerSkipped else { break }

            let remaining = max(0, resolvedEndDate.timeIntervalSinceNow)
            let elapsed = min(max(0, resolvedTotalDuration - remaining), resolvedTotalDuration)
            timerElapsed = elapsed
            timerProgress = min(elapsed / resolvedTotalDuration, 1.0)

            // 5-min haptics
            if resolvedTotalDuration >= 300 {
                let prevElapsed = max(0, elapsed - 0.15)
                if Int(elapsed / 300) > Int(prevElapsed / 300) && elapsed > 1 {
                    haptic.impactOccurred(intensity: 0.25)
                }
            }

            if timerProgress >= 1.0 { break }

            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return .cancelled
            }
        }

        let skipped = timerSkipped
        timerProgress = 1.0
        if skipped {
            cancelPhaseEndNotification()
        }
        timerEndDate = nil // Only clear on natural finish or skip
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
        
        let phaseTag = phaseCheckpointTag(phase)
        let loopDur = phaseTag == "work" ? (currentLoopDuration + timerElapsed) : currentLoopDuration
        
        let currentPhase = phase
        let tEndDate = timerEndDate
        
        let uName = userName.isEmpty ? sessionUserName : userName

        Task.detached(priority: .background) {
            SessionStore.shared.saveCheckpoint(.init(
                userName: uName,
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
                currentLoopDuration: loopDur,
                timerEndDate: tEndDate,
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

    private var photoDeltaContinuation: CheckedContinuation<Void, Never>? = nil

    func completePhotoDelta() {
        photoDeltaContinuation?.resume()
        photoDeltaContinuation = nil
    }

    private func capturePhotoDelta() async {
        guard let baseline = baselinePhoto, !Task.isCancelled else { return }
        withAnimation { phase = .photoDelta }
        pendingPhoto = nil
        photoSkipped = false
        
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            photoDeltaContinuation = cont
        }
        
        guard !Task.isCancelled else { return }
        guard let final = finalPhotos.first else { return }
        
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
        currentLoopDuration = checkpoint.currentLoopDuration ?? 0
        currentGoal = checkpoint.currentGoal
        sessionMotivationLevel = checkpoint.motivationLevel
        totalLoops = min(6, max(1, checkpoint.totalLoops ?? 4))
        workDuration = checkpoint.workDuration
        shortBreakDuration = checkpoint.shortBreakDuration
        longBreakDuration = checkpoint.longBreakDuration
        originalWorkDuration = checkpoint.workDuration
        needsStarterDecision = (sessionMotivationLevel ?? 5) <= 2

        // Restore timer state: Live Activity is the absolute source of truth if available
        var remainingTime: TimeInterval? = nil
        var resumeIsWork = checkpoint.phaseRaw != "break"
        
        // Retry loop for activity detection (sometimes takes a moment on cold start)
        var activityFound = false
        for _ in 0..<3 {
            if let activity = Activity<DexarAttributes>.activities.first {
                self.liveActivity = activity
                let activityEndDate = activity.content.state.endDate
                let activityIsWork = activity.content.state.isWork
                let activityLoop = activity.content.state.loopNumber
                
                let now = Date()
                if activityEndDate > now {
                    remainingTime = activityEndDate.timeIntervalSince(now)
                } else {
                    remainingTime = 0.1
                }
                
                resumeIsWork = activityIsWork
                currentLoopNumber = activityLoop
                self.timerEndDate = activityEndDate
                activityFound = true
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        if !activityFound, let endDate = checkpoint.timerEndDate {
            let now = Date()
            if endDate > now {
                remainingTime = endDate.timeIntervalSince(now)
            } else {
                remainingTime = 0.1
            }
            self.timerEndDate = endDate
        }

        baselinePhoto = loadPhotoFromDisk(name: "baseline_photo.jpg")
        
        finalPhotos = []
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("photos", isDirectory: true)
        
        var fIdx = 0
        while true {
            let name = "final_photo_\(fIdx).jpg"
            let fileURL = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: fileURL.path), let img = loadPhotoFromDisk(name: name) {
                finalPhotos.append(img)
                fIdx += 1
            } else {
                break
            }
        }
        if finalPhotos.isEmpty, let oldFinal = loadPhotoFromDisk(name: "final_photo.jpg") {
            finalPhotos.append(oldFinal)
        }
        
        progressPhotoLoops = []
        progressPhotos = [:]
        for i in 1...totalLoops {
            var loopPhotos: [UIImage] = []
            var pIdx = 0
            while true {
                let name = "progress_photo_\(i)_\(pIdx).jpg"
                let fileURL = dir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: fileURL.path), let img = loadPhotoFromDisk(name: name) {
                    loopPhotos.append(img)
                    pIdx += 1
                } else {
                    break
                }
            }
            let oldName = "progress_photo_\(i).jpg"
            let oldFileURL = dir.appendingPathComponent(oldName)
            if loopPhotos.isEmpty && FileManager.default.fileExists(atPath: oldFileURL.path), let img = loadPhotoFromDisk(name: oldName) {
                loopPhotos.append(img)
            }
            
            if !loopPhotos.isEmpty {
                progressPhotoLoops.insert(i)
                progressPhotos[i] = loopPhotos
            }
        }

        guard !Task.isCancelled else { return }

        if !resumeIsWork {
            if let remaining = remainingTime {
                let endDate = timerEndDate ?? checkpoint.timerEndDate ?? Date().addingTimeInterval(remaining)
                let totalDuration = completedLoops.count >= totalLoops ? longBreakDuration : shortBreakDuration
                withAnimation { phase = .breakTime(loopNumber: currentLoopNumber) }
                timerEndDate = endDate
                startLiveActivity(duration: remaining, isWork: false, loopNumber: currentLoopNumber, endDate: endDate)
                await runTimer(duration: remaining, totalDuration: totalDuration, endDate: endDate)
                endLiveActivity()
                guard !Task.isCancelled else { return }
                
                let isLong = totalLoops > 0 && completedLoops.count >= totalLoops
                if isLong {
                    await capturePhotoDelta()
                    await finishSession()
                } else {
                    await mainLoop()
                }
            } else {
                let breakResult = await runBreak()
                if breakResult == .continueNext {
                    await mainLoop()
                } else {
                    guard !Task.isCancelled else { return }
                    await capturePhotoDelta()
                    guard !Task.isCancelled else { return }
                    await finishSession()
                }
            }
        } else {
            if let remaining = remainingTime {
                // Resume active work timer
                let endDate = timerEndDate ?? checkpoint.timerEndDate ?? Date().addingTimeInterval(remaining)
                withAnimation { phase = .workActive(loopNumber: currentLoopNumber) }
                updateScreenAwake(enabled: true)
                timerEndDate = endDate
                startLiveActivity(duration: remaining, isWork: true, loopNumber: currentLoopNumber, endDate: endDate)
                let timerResult = await runTimer(duration: remaining, totalDuration: workDuration, endDate: endDate)
                currentLoopDuration += timerElapsed
                endLiveActivity()
                updateScreenAwake(enabled: false)
                guard !Task.isCancelled && timerResult != .cancelled else { return }
                
                withAnimation { phase = .roundEnd }
                if timerResult == .completed || timerResult == .skipped {
                    speech.playCue(named: "end")
                }
                
                let choice = await runRoundEnd()
                if choice == .finish {
                    await capturePhotoDelta()
                    await finishSession()
                } else if choice == .workAgain {
                    await mainLoop()
                } else {
                    let breakAction = await runBreak()
                    if breakAction == .continueNext {
                        await mainLoop()
                    } else {
                        await capturePhotoDelta()
                        await finishSession()
                    }
                }
            } else {
                await mainLoop()
            }
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

    private func startLiveActivity(duration: TimeInterval, isWork: Bool, loopNumber: Int, endDate: Date? = nil) {
        let resolvedEndDate = endDate ?? timerEndDate ?? Date().addingTimeInterval(duration)
        timerEndDate = resolvedEndDate
        schedulePhaseEndNotification(endDate: resolvedEndDate, isWork: isWork, loopNumber: loopNumber)

        let info = ActivityAuthorizationInfo()
        guard info.areActivitiesEnabled else { return }
        
        let state = DexarAttributes.ContentState(
            endDate: resolvedEndDate,
            isWork: isWork,
            loopNumber: loopNumber
        )
        
        if let activity = liveActivity {
            let content = ActivityContent(
                state: state,
                staleDate: resolvedEndDate.addingTimeInterval(60),
                relevanceScore: 100
            )
            Task { await activity.update(content) }
            return
        }
        
        let attributes = DexarAttributes(goal: currentGoal, shortGoal: shortGoal, totalLoops: totalLoops)
        let content = ActivityContent(
            state: state,
            staleDate: resolvedEndDate.addingTimeInterval(60),
            relevanceScore: 100
        )
        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("[LiveActivity] request failed: \(error)")
        }
    }

    private func updateLiveActivity(remainingDuration: TimeInterval, isWork: Bool, loopNumber: Int) {
        guard let activity = liveActivity else { return }
        let resolvedEndDate = Date().addingTimeInterval(remainingDuration)
        timerEndDate = resolvedEndDate
        schedulePhaseEndNotification(endDate: resolvedEndDate, isWork: isWork, loopNumber: loopNumber)
        let state = DexarAttributes.ContentState(
            endDate: resolvedEndDate,
            isWork: isWork,
            loopNumber: loopNumber
        )
        Task { await activity.update(.init(state: state, staleDate: resolvedEndDate.addingTimeInterval(60))) }
    }

    private func markLiveActivityOvertime(loopNumber: Int) {
        guard let activity = liveActivity, let endDate = timerEndDate else { return }
        let state = DexarAttributes.ContentState(
            endDate: endDate,
            isWork: true,
            loopNumber: loopNumber,
            isOvertime: true
        )
        Task { await activity.update(.init(state: state, staleDate: endDate.addingTimeInterval(120))) }
    }

    private func schedulePhaseEndNotification(endDate: Date, isWork: Bool, loopNumber: Int) {
        let interval = max(1, endDate.timeIntervalSinceNow)
        let goal = currentGoal
        let title = isWork ? "Focus phase over" : "Break over"
        let body = isWork
            ? "Loop \(loopNumber) is done. Open Dexar to wrap it up."
            : "Break is done. Open Dexar for the next loop."

        Task {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [phaseEndNotificationIdentifier])

            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                var options: UNAuthorizationOptions = [.alert, .sound]
                if #available(iOS 15.0, *) {
                    options.insert(.timeSensitive)
                }
                _ = try? await center.requestAuthorization(options: options)
            }

            let updatedSettings = await center.notificationSettings()
            guard updatedSettings.authorizationStatus == .authorized ||
                    updatedSettings.authorizationStatus == .provisional ||
                    updatedSettings.authorizationStatus == .ephemeral else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = isWork ? .defaultCritical : .default
            content.userInfo = [
                "phase": isWork ? "work" : "break",
                "loopNumber": loopNumber,
                "goal": goal
            ]
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: phaseEndNotificationIdentifier,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    private func cancelPhaseEndNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [phaseEndNotificationIdentifier]
        )
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        liveActivity = nil
        Task { await activity.end(dismissalPolicy: .immediate) }
    }
}
