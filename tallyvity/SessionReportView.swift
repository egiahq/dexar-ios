import SwiftUI
import UIKit

struct SessionReportView: View {
    let loops: [LoopRecord]
    let artifact: SessionArtifact
    var beforeImage: UIImage? = nil
    var afterImage: UIImage? = nil
    var comparison: String = ""
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    if beforeImage != nil || afterImage != nil { comparisonSection }
                    if loops.contains(where: { $0.score > 0 }) { scores }
                    if !artifact.finalAnswers.isEmpty { answersSection }
                    if let level = artifact.motivationLevel { motivationRow(level) }
                    if !artifact.blocker.isEmpty { blockerRow }
                    if !artifact.intentNext.isEmpty { nextRow }
                    if !artifact.closingSentence.isEmpty { closing }
                    dismissButton
                }
                .padding(.horizontal, 28)
                .padding(.top, 48)
                .padding(.bottom, 60)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session complete")
                .font(.caption)
                .kerning(1.5)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(artifact.goal)
                .font(.title2.weight(.regular))
                .foregroundStyle(.primary)

            Text("\(loops.count) loop\(loops.count == 1 ? "" : "s") · \(formattedDate)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before / After")
                .font(.caption)
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                photoTile(label: "Before", image: beforeImage)
                photoTile(label: "After", image: afterImage)
            }

            if !comparison.isEmpty {
                Text(comparison)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func photoTile(label: String, image: UIImage?) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 140)
                    .overlay(Text("—").foregroundStyle(.tertiary))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var scores: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loop scores")
                .font(.caption)
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                ForEach(Array(loops.enumerated()), id: \.offset) { i, loop in
                    VStack(spacing: 6) {
                        Text("\(loop.score)")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Loop \(i + 1)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private var answersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reflection")
                .font(.caption)
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            let qs = PromptStore.shared.presets(for: "default_qa_questions")
            ForEach(0..<min(3, artifact.finalAnswers.count), id: \.self) { j in
                VStack(alignment: .leading, spacing: 6) {
                    Text(qs.indices.contains(j) ? qs[j] : "Question \(j+1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(artifact.finalAnswers[j].isEmpty ? "—" : artifact.finalAnswers[j])
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func motivationRow(_ level: Int) -> some View {
        factRow(label: "Starting motivation", value: "\(level)/5")
    }

    @ViewBuilder
    private var blockerRow: some View {
        factRow(label: "Main friction", value: artifact.blocker)
    }

    @ViewBuilder
    private var nextRow: some View {
        factRow(label: "Next intent", value: artifact.intentNext)
    }

    private func factRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private var closing: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(artifact.closingSentence)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.top, 4)
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Done")
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.top, 8)
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: artifact.date)
    }
}

#Preview {
    let loops = [
        LoopRecord(goalText: "write report", answers: ["Finished intro", "Got distracted", "Start with outline"], score: 3, scoreReason: "three"),
        LoopRecord(goalText: "write report", answers: ["Finished section 2", "Coffee break too long", "Set a timer"], score: 4, scoreReason: "four")
    ]
    let artifact = SessionArtifact(
        id: "1", date: Date(), goal: "Write quarterly report",
        motivationLevel: 4,
        score: 3.5, blocker: "kept rewriting same paragraph",
        intentNext: "set word count target first",
        loopsCompleted: 2,
        closingSentence: "Alex, today you completed 2 loops on writing quarterly report. Kept rewriting same paragraph was the main friction. Set word count target first is where to start next time.",
        finalAnswers: ["Finished the intro section", "Got distracted by email", "Set a word count target first"]
    )
    return SessionReportView(loops: loops, artifact: artifact) {}
}
