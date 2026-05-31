import SwiftUI

struct SessionHistoryView: View {
    var session: SessionEngine
    var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var localArtifacts: [SessionArtifact] = []
    @State private var localCheckpoint: SessionStore.SessionCheckpoint?
    @State private var selectedArtifact: SessionArtifact? = nil

    var body: some View {
        NavigationStack {
            Group {
                if localArtifacts.isEmpty && localCheckpoint == nil {
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
                        .foregroundStyle(Color.appForeground)
                }
            }
            .onAppear {
                localArtifacts = SessionStore.shared.loadAll()
                localCheckpoint = SessionStore.shared.loadCheckpoint()
            }
            .sheet(item: $selectedArtifact) { artifact in
                SessionReportView(
                    loops: (artifact.loopDurations ?? []).enumerated().map { i, dur in
                        LoopRecord(goalText: artifact.goal, answers: [], score: 0, scoreReason: "", duration: dur)
                    },
                    artifact: artifact,
                    onDismiss: { selectedArtifact = nil }
                )
            }
        }
    }

    private var list: some View {
        List {
            if let cp = localCheckpoint {
                resumeCard(cp)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            }

            if !localArtifacts.isEmpty {
                Section {
                    ForEach(Array(localArtifacts.enumerated()), id: \.element.id) { idx, artifact in
                        VStack(alignment: .leading, spacing: 0) {
                            Button(action: { selectedArtifact = artifact }) {
                                artifactRow(artifact)
                                    .padding(.horizontal, 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(SpringButtonStyle())

                            if idx < localArtifacts.count - 1 {
                                Divider()
                                    .padding(.leading, 20)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteArtifacts)
                } header: {
                    Text("Completed")
                        .font(.system(size: 11, weight: .medium))
                        .kerning(1.4)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .padding(.leading, 20)
                        .padding(.top, localCheckpoint == nil ? 20 : 12)
                        .padding(.bottom, 8)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .background(Color.appBackground)
    }

    private func deleteArtifacts(at offsets: IndexSet) {
        for index in offsets {
            let artifact = localArtifacts[index]
            SessionStore.shared.delete(artifact.id)
        }
        withAnimation {
            localArtifacts.remove(atOffsets: offsets)
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
                HStack(spacing: 4) {
                    Image(systemName: "repeat")
                    Text("Loop \(cp.completedLoops.count + 1) of \(cp.totalLoops ?? 4)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(cp.savedAt.formatted(.relative(presentation: .named)))
                }
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
                        .foregroundStyle(Color.appMutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.appTertiaryBackground)
                        .clipShape(Rectangle())
                }
                .buttonStyle(SpringButtonStyle())

                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        session.resumePendingSession()
                    }
                }) {
                    Text("Resume")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appPrimaryForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.appPrimary)
                        .clipShape(Rectangle())
                }
                .buttonStyle(SpringButtonStyle())
            }
        }
        .padding(16)
        .background(Color.appSecondaryBackground)
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
                let loopMax = artifact.totalLoops ?? artifact.loopsCompleted
                HStack(spacing: 4) {
                    Image(systemName: "repeat")
                    Text("\(artifact.loopsCompleted)/\(loopMax)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let total = artifact.totalDurationWorked {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(formatDuration(total))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let motivation = artifact.motivationLevel {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt")
                        Text("\(motivation)/5")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !artifact.blocker.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle")
                        Text("Blocked")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let on = artifact.onTaskSeconds, let off = artifact.offTaskSeconds {
                let total = on + off
                let pct = total > 0 ? Int(on / total * 100) : 0
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                    Text("\(pct)% on-task")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
