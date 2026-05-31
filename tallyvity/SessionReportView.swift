import SwiftUI
import UIKit

struct ReportPhoto: Identifiable {
    let id = UUID()
    let label: String
    let image: UIImage
}

struct PhotoGallery: Identifiable {
    let id = UUID()
    let photos: [ReportPhoto]
    let initialIndex: Int
}

struct SessionReportView: View {
    let loops: [LoopRecord]
    let artifact: SessionArtifact
    var beforeImage: UIImage? = nil
    var afterImage: UIImage? = nil
    var afterImages: [UIImage] = []
    var progressPhotos: [Int: [UIImage]] = [:]
    var comparison: String = ""
    var session: SessionEngine? = nil
    var onDismiss: () -> Void

    @State private var photoGallery: PhotoGallery? = nil
    @State private var progressRating: Int?
    @State private var reflectionText: String = ""
    @State private var beforeImageLoaded: UIImage? = nil
    @State private var afterImagesLoaded: [UIImage] = []
    @State private var progressPhotosLoaded: [Int: [UIImage]] = [:]
    private let haptic = UISelectionFeedbackGenerator()

    private var allPhotos: [ReportPhoto] {
        var list: [ReportPhoto] = []
        if let beforeImageLoaded {
            list.append(ReportPhoto(label: "Before", image: beforeImageLoaded))
        }
        let sortedLoops = progressPhotosLoaded.keys.sorted()
        for loop in sortedLoops {
            if let imgs = progressPhotosLoaded[loop] {
                for (idx, img) in imgs.enumerated() {
                    let suffix = imgs.count > 1 ? " (\(idx + 1)/\(imgs.count))" : ""
                    let label = "Loop \(loop)\(suffix)"
                    list.append(ReportPhoto(label: label, image: img))
                }
            }
        }
        for (idx, img) in afterImagesLoaded.enumerated() {
            let suffix = afterImagesLoaded.count > 1 ? " (\(idx + 1)/\(afterImagesLoaded.count))" : ""
            let label = "After\(suffix)"
            list.append(ReportPhoto(label: label, image: img))
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
                    if beforeImageLoaded != nil || !afterImagesLoaded.isEmpty || !progressPhotosLoaded.isEmpty { comparisonSection }
                    progressRatingSelector
                    if loops.contains(where: { $0.score > 0 }) { scores }
                    if !artifact.finalAnswers.isEmpty { answersSection }
                    if let level = artifact.motivationLevel { motivationRow(level) }
                    reflectionSection
                    dismissButton
                }
                .padding(.horizontal, 28)
                .padding(.top, 48)
                .padding(.bottom, 60)
            }
        }
        .fullScreenCover(item: $photoGallery) { gallery in
            PhotoGalleryView(photos: gallery.photos, initialIndex: gallery.initialIndex)
        }
        .onAppear {
            progressRating = artifact.progressRating
            reflectionText = artifact.reflection ?? ""

            if let baselineName = artifact.baselinePhotoPath {
                beforeImageLoaded = loadPhotoFromDisk(name: baselineName)
            } else {
                beforeImageLoaded = beforeImage
            }
            
            if let finalNames = artifact.finalPhotoPaths {
                afterImagesLoaded = finalNames.compactMap { loadPhotoFromDisk(name: $0) }
            } else {
                afterImagesLoaded = afterImages.isEmpty && afterImage != nil ? [afterImage!] : afterImages
            }
            
            if let progressMap = artifact.progressPhotoPaths {
                var loadedMap: [Int: [UIImage]] = [:]
                for (loopStr, paths) in progressMap {
                    if let loopInt = Int(loopStr) {
                        loadedMap[loopInt] = paths.compactMap { loadPhotoFromDisk(name: $0) }
                    }
                }
                progressPhotosLoaded = loadedMap
            } else {
                progressPhotosLoaded = progressPhotos
            }
        }
        .onChange(of: reflectionText) { _, new in
            var updated = artifact
            updated.reflection = new.isEmpty ? nil : new
            SessionStore.shared.save(updated)
        }
        .onChange(of: session?.reflectionTranscript ?? "") { _, new in
            guard !new.isEmpty else { return }
            withAnimation {
                reflectionText = reflectionText.isEmpty ? new : reflectionText + " " + new
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(allPhotos.enumerated()), id: \.element.id) { idx, reportPhoto in
                        Button(action: {
                            photoGallery = PhotoGallery(photos: allPhotos, initialIndex: idx)
                        }) {
                            photoTile(label: reportPhoto.label, image: reportPhoto.image)
                                .frame(width: 140)
                        }
                        .buttonStyle(SpringButtonStyle())
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
                    .clipShape(Rectangle())
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
                    .clipShape(Rectangle())
            } else {
                Rectangle()
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
                    .clipShape(Rectangle())
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
                .clipShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private func motivationRow(_ level: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Starting motivation")
                .font(.caption)
                .kerning(1.2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(level)/5")
                .font(.body)
                .foregroundStyle(.primary)
        }
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if reflectionText.isEmpty {
                    Text("What went well, what slowed you down…")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $reflectionText)
                    .font(.subheadline)
                    .frame(minHeight: 96)
                    .scrollContentBackground(.hidden)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if session != nil {
                HStack {
                    Spacer()
                    Button(action: { session?.toggleReflectionRecording() }) {
                        Group {
                            if session?.isVoiceLoading == true {
                                ProgressView()
                                    .scaleEffect(0.9)
                            } else {
                                Image(systemName: session?.isRecording == true ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(session?.isRecording == true ? .white : Color.primary)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(
                            session?.isRecording == true
                                ? Color.red
                                : Color(.tertiarySystemBackground)
                        )
                        .clipShape(Circle())
                    }
                    .buttonStyle(SpringButtonStyle())
                    .disabled(session?.isVoiceLoading == true)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(Rectangle())
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
        .buttonStyle(SpringButtonStyle())
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
                .clipShape(Rectangle())
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
                        .opacity(progressOpacity(for: level))
                        .contentShape(Circle())
                        .onTapGesture {
                            withAnimation(.bouncySpring) {
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
        haptic.selectionChanged()
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
        return progressRating == level ? 1.25 : 0.9
    }

    private func progressOpacity(for level: Int) -> Double {
        guard let progressRating else { return 1.0 }
        return progressRating == level ? 1.0 : 0.45
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

    private func loadPhotoFromDisk(name: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("photos", isDirectory: true)
        let fileURL = dir.appendingPathComponent(name)
        if let data = try? Data(contentsOf: fileURL) {
            return UIImage(data: data)
        }
        return nil
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

struct PhotoGalleryView: View {
    let photos: [ReportPhoto]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { idx, photo in
                    ZoomableScrollView {
                        Image(uiImage: photo.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                    .ignoresSafeArea()
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    Text(photos.indices.contains(currentIndex) ? photos[currentIndex].label : "")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.leading, 20)
                        .padding(.top, 10)

                    Spacer()

                    Button { dismiss() } label: {
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
        .onAppear { currentIndex = initialIndex }
    }
}

#Preview {
    let loops = [
        LoopRecord(goalText: "write report", answers: ["Finished intro", "Got distracted", "Start with outline"], score: 3, scoreReason: "three"),        LoopRecord(goalText: "write report", answers: ["Finished intro", "Got distracted", "Start with outline"], score: 3, scoreReason: "three"),        LoopRecord(goalText: "write report", answers: ["Finished intro", "Got distracted", "Start with outline"], score: 3, scoreReason: "three"),        LoopRecord(goalText: "write report", answers: ["Finished intro", "Got distracted", "Start with outline"], score: 3, scoreReason: "three"),        LoopRecord(goalText: "write report", answers: ["Finished intro", "Got distracted", "Start with outline"], score: 3, scoreReason: "three"),        LoopRecord(goalText: "write report", answers: ["Finished intro", "Got distracted", "Start with outline"], score: 3, scoreReason: "three"),
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
