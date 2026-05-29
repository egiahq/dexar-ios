import SwiftUI
import UIKit

struct ReportPhoto: Identifiable {
    let id = UUID()
    let label: String
    let image: UIImage
}

struct SessionReportView: View {
    let loops: [LoopRecord]
    let artifact: SessionArtifact
    var beforeImage: UIImage? = nil
    var afterImage: UIImage? = nil
    var progressPhotos: [Int: UIImage] = [:]
    var comparison: String = ""
    var onDismiss: () -> Void

    @State private var selectedPhotoForEnlargement: ReportPhoto? = nil
    @State private var progressRating: Int?

    private var allPhotos: [ReportPhoto] {
        var list: [ReportPhoto] = []
        if let beforeImage {
            list.append(ReportPhoto(label: "Before", image: beforeImage))
        }
        let sortedLoops = progressPhotos.keys.sorted()
        for loop in sortedLoops {
            if let img = progressPhotos[loop] {
                let label = (loop == loops.count) ? "Loop \(loop) (After)" : "Loop \(loop)"
                list.append(ReportPhoto(label: label, image: img))
            }
        }
        if let afterImage, !list.contains(where: { $0.image == afterImage }) {
            list.append(ReportPhoto(label: "After", image: afterImage))
        }
        return list
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
 
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    if artifact.totalDurationWorked != nil { timeWorkedSection }
                    progressRatingSelector
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
        .fullScreenCover(item: $selectedPhotoForEnlargement) { reportPhoto in
            PhotoDetailView(image: reportPhoto.image, label: reportPhoto.label)
        }
        .onAppear {
            progressRating = artifact.progressRating
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(allPhotos) { reportPhoto in
                        photoTile(label: reportPhoto.label, image: reportPhoto.image)
                            .frame(width: 140)
                            .onTapGesture {
                                selectedPhotoForEnlargement = reportPhoto
                            }
                    }
                }
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
                .foregroundStyle(Color.appForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.appSecondaryBackground)
                .clipShape(Rectangle())
        }
        .padding(.top, 8)
    }

    private var timeWorkedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus Time")
                .font(.caption)
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDuration(artifact.totalDurationWorked ?? 0))
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Total Work")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(artifact.loopsCompleted)")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Completed Rounds")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 6)

            if let loopDurations = artifact.loopDurations, !loopDurations.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(loopDurations.enumerated()), id: \.offset) { i, dur in
                        HStack {
                            Text("Round \(i + 1)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatDuration(dur))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        if i < loopDurations.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
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

    private var progressRatingSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rate your progress")
                .font(.caption)
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { level in
                    Circle()
                        .fill(progressFillColor(for: level))
                        .overlay(
                            Circle()
                                .strokeBorder(progressBorderColor(for: level), lineWidth: 1.5)
                        )
                        .frame(width: 38, height: 38)
                        .scaleEffect(progressScale(for: level))
                        .contentShape(Circle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                                selectProgressRating(level)
                            }
                        }
                }
            }

            if let progressRating {
                Text(progressLabel(for: progressRating))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
    }

    private func selectProgressRating(_ level: Int) {
        progressRating = level
        var updated = artifact
        updated.progressRating = level
        SessionStore.shared.save(updated)
    }

    private func progressFillColor(for level: Int) -> Color {
        guard let progressRating else { return .clear }
        return level <= progressRating ? .primary : .clear
    }

    private func progressScale(for level: Int) -> CGFloat {
        guard let progressRating else { return 1.0 }
        return progressRating == level ? 1.06 : 1.0
    }

    private func progressBorderColor(for level: Int) -> Color {
        guard let progressRating else { return Color.primary.opacity(0.28) }
        return level <= progressRating ? Color.primary.opacity(0.0) : Color.primary.opacity(0.28)
    }

    private func progressLabel(for level: Int) -> String {
        switch level {
        case 1: return "slow progress"
        case 2: return "some progress"
        case 3: return "steady progress"
        case 4: return "great progress"
        case 5: return "fully accomplished"
        default: return ""
        }
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: artifact.date)
    }
}

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = context.coordinator

        let hostedView = UIHostingController(rootView: content)
        hostedView.view.backgroundColor = .clear
        hostedView.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostedView.view)

        NSLayoutConstraint.activate([
            hostedView.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.hostingController = hostedView
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController?.view
        }
    }
}

struct PhotoDetailView: View {
    let image: UIImage
    let label: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ZoomableScrollView {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 20)
                    .padding(.top, 10)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                            .background(Circle().fill(Color.black.opacity(0.3)))
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 10)
                }
                Spacer()
            }
            .padding(.top, 10)
        }
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
