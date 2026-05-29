import SwiftUI

struct SessionHistoryView: View {
    var session: SessionEngine
    var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private var artifacts: [SessionArtifact] { SessionStore.shared.loadAll() }
    private var checkpoint: SessionStore.SessionCheckpoint? { SessionStore.shared.loadCheckpoint() }

    var body: some View {
        NavigationStack {
            Group {
                if artifacts.isEmpty && checkpoint == nil {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let cp = checkpoint {
                    resumeCard(cp)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                }

                if !artifacts.isEmpty {
                    Text("Completed")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(1.4)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, checkpoint == nil ? 20 : 12)
                        .padding(.bottom, 8)

                    ForEach(Array(artifacts.enumerated()), id: \.element.id) { idx, artifact in
                        artifactRow(artifact)
                            .padding(.horizontal, 20)

                        if idx < artifacts.count - 1 {
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func resumeCard(_ cp: SessionStore.SessionCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "timer")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.orange)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("In Progress")
                        .font(.caption2)
                        .kerning(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(.orange.opacity(0.8))

                    Text(cp.currentGoal.isEmpty ? "Untitled session" : cp.currentGoal)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 16) {
                Label("Loop \(cp.completedLoops.count + 1) of \(cp.totalLoops ?? 4)", systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(cp.savedAt.formatted(.relative(presentation: .named)), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(action: {
                    session.discardPendingSession()
                    dismiss()
                }) {
                    Text("Discard")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        session.resumePendingSession()
                    }
                }) {
                    Text("Resume")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func artifactRow(_ artifact: SessionArtifact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(artifact.goal)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(artifact.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                scoreTag(artifact.score)
            }

            HStack(spacing: 16) {
                Label("\(artifact.loopsCompleted) loop\(artifact.loopsCompleted == 1 ? "" : "s")", systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let total = artifact.totalDurationWorked {
                    Label(formatDuration(total), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !artifact.blocker.isEmpty {
                    Label("Blocked", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !artifact.intentNext.isEmpty {
                Text(artifact.intentNext)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 14)
    }

    private func scoreTag(_ score: Double) -> some View {
        let rounded = Int(score.rounded())
        let color: Color = score >= 4 ? .green : score >= 3 ? .primary : .orange
        return Text("\(rounded)/5")
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func formatDuration(_ sec: TimeInterval) -> String {
        let minutes = Int(sec) / 60
        let seconds = Int(sec) % 60
        if minutes > 0 {
            if seconds > 0 {
                return "\(minutes)m \(seconds)s"
            }
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.tertiary)

            Text("No sessions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SessionHistoryView(
        session: SessionEngine(speech: SpeechEngine(), gemma: GemmaEngine()),
        settings: SettingsStore()
    )
}
