import Foundation

struct LoopRecord: Codable {
    var goalText: String
    var answers: [String]
    var score: Int
    var scoreReason: String
    var duration: TimeInterval?
}

struct SessionArtifact: Codable, Identifiable {
    var id: String
    var date: Date
    var goal: String
    var motivationLevel: Int?
    var score: Double
    var blocker: String
    var intentNext: String
    var loopsCompleted: Int
    var closingSentence: String
    var finalAnswers: [String]
    var totalDurationWorked: TimeInterval?
    var loopDurations: [TimeInterval]?
    var progressRating: Int?
}

final class SessionStore {
    static let shared = SessionStore()
    private let fm = FileManager.default

    struct SessionCheckpoint: Codable {
        var userName: String
        var phaseRaw: String
        var currentGoal: String
        var completedLoops: [LoopRecord]
        var currentLoopAnswers: [String]
        var currentLoopNumber: Int
        var motivationLevel: Int?
        var totalLoops: Int?
        var workDuration: TimeInterval
        var shortBreakDuration: TimeInterval
        var longBreakDuration: TimeInterval
        var currentLoopDuration: TimeInterval?
        var timerEndDate: Date?
        var savedAt: Date
    }

    private var artifactsDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("artifacts", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var checkpointURL: URL {
        artifactsDir.appendingPathComponent("active_session_checkpoint.json")
    }

    func compareSimilarity(_ text1: String, _ text2: String) -> Double {
        return cosineSimilarity(semanticTokens(text1), semanticTokens(text2))
    }

    func save(_ artifact: SessionArtifact) {
        let url = artifactsDir.appendingPathComponent("\(artifact.id).json")
        if let data = try? JSONEncoder().encode(artifact) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func delete(_ id: String) {
        let url = artifactsDir.appendingPathComponent("\(id).json")
        try? fm.removeItem(at: url)
    }

    func loadAll() -> [SessionArtifact] {
        let urls = (try? fm.contentsOfDirectory(at: artifactsDir, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url -> SessionArtifact? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SessionArtifact.self, from: data)
        }.sorted { $0.date > $1.date }
    }

    func findRelevant(for goal: String, limit: Int = 3) -> [SessionArtifact] {
        let all = loadAll()
        guard !all.isEmpty else { return [] }

        let goalTokens = semanticTokens(goal)
        guard !goalTokens.isEmpty else { return [] }

        return all
            .map { a -> (SessionArtifact, Double) in
                let text = "\(a.goal) \(a.blocker) \(a.intentNext)"
                return (a, cosineSimilarity(goalTokens, semanticTokens(text)))
            }
            .filter { $0.1 > 0.18 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func saveCheckpoint(_ checkpoint: SessionCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        try? data.write(to: checkpointURL, options: .atomic)
    }

    func loadCheckpoint(maxAgeHours: Double = 12) -> SessionCheckpoint? {
        guard let data = try? Data(contentsOf: checkpointURL),
              let checkpoint = try? JSONDecoder().decode(SessionCheckpoint.self, from: data) else {
            return nil
        }

        let age = Date().timeIntervalSince(checkpoint.savedAt)
        return age <= maxAgeHours * 3600 ? checkpoint : nil
    }

    func clearCheckpoint() {
        try? fm.removeItem(at: checkpointURL)
    }

    private func semanticTokens(_ text: String) -> [String: Double] {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [:] }

        var counts: [String: Double] = [:]
        for word in words where word.count >= 3 {
            let chars = Array(word)
            if chars.count == 3 {
                counts[word, default: 0] += 1
                continue
            }
            for i in 0...(chars.count - 3) {
                let trigram = String(chars[i...(i + 2)])
                counts[trigram, default: 0] += 1
            }
        }
        return counts
    }

    private func cosineSimilarity(_ lhs: [String: Double], _ rhs: [String: Double]) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }

        let dot = lhs.reduce(0.0) { partial, pair in
            partial + pair.value * (rhs[pair.key] ?? 0)
        }
        let lNorm = sqrt(lhs.values.reduce(0.0) { $0 + $1 * $1 })
        let rNorm = sqrt(rhs.values.reduce(0.0) { $0 + $1 * $1 })
        guard lNorm > 0, rNorm > 0 else { return 0 }
        return dot / (lNorm * rNorm)
    }

    var latest: SessionArtifact? { loadAll().first }
}
