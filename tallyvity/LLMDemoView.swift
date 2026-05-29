import SwiftUI
import PhotosUI

struct LLMDemoView: View {
    var gemma: GemmaEngine

    @State private var prompt: String = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var showCamera = false
    @State private var messages: [ChatMessage] = []
    @State private var scrollProxy: ScrollViewProxy? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                switch gemma.state {
                case .idle:
                    notLoadedView
                case .downloading(let p):
                    loadingOverlay(message: "Downloading model…", progress: p)
                case .loading:
                    loadingOverlay(message: "Loading Gemma…", progress: nil)
                case .ready, .generating:
                    chatView
                case .error(let msg):
                    errorView(msg)
                }
            }
            .navigationTitle("Gemma 4")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in
                withAnimation { pendingImage = image }
            }
            .ignoresSafeArea()
        }
    }

    private var notLoadedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Gemma 4 E2B not loaded")
                .font(.title3)
            Text("Load from Settings → Gemma Model")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                        }
                        if case .generating = gemma.state {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .id("typing")
                        }
                    }
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                .onAppear { scrollProxy = proxy }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: gemma.state) { _, new in
                    if case .generating = new {
                        withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                    }
                }
            }

            Divider()
            inputBar
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data) else { return }
                withAnimation { pendingImage = img }
            }
        }
        .onChange(of: gemma.output) { _, new in
            guard !new.isEmpty else { return }
            if let last = messages.last, last.role == .assistant {
                messages[messages.count - 1] = ChatMessage(id: last.id, role: .assistant, text: new, image: nil)
            } else {
                messages.append(ChatMessage(role: .assistant, text: new, image: nil))
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if let img = pendingImage {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button {
                            withAnimation { pendingImage = nil; pickerItem = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                        .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: pendingImage == nil ? "photo" : "photo.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(pendingImage == nil ? .secondary : .primary)
                }

                TextField("Ask anything…", text: $prompt, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)

                Button(action: runInference) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? Color.appForeground : Color.appMutedForeground.opacity(0.3))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.appMutedForeground)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appMutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Dismiss") { gemma.cancelError() }
                .font(.body.weight(.medium))
                .foregroundStyle(Color.appPrimaryForeground)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.appPrimary)
                .clipShape(Rectangle())
        }
    }

    private func loadingOverlay(message: String, progress: Double?) -> some View {
        VStack(spacing: 20) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.primary)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().scaleEffect(1.4)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        gemma.state == .ready
    }

    private func runInference() {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let img = pendingImage
        withAnimation {
            prompt = ""
            pendingImage = nil
            pickerItem = nil
            messages.append(ChatMessage(role: .user, text: p, image: img))
        }
        Task { await gemma.generate(image: img, prompt: p) }
    }
}

struct ChatMessage: Identifiable {
    var id = UUID()
    var role: Role
    var text: String
    var image: UIImage?

    enum Role { case user, assistant }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if let img = message.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.role == .user ? Color.appForeground : Color.appSecondaryBackground)
                        .foregroundStyle(message.role == .user ? Color.appBackground : Color.appForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }
}

struct TypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(.secondary)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onAppear { animate() }
    }

    private func animate() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { t in
            withAnimation(.easeInOut(duration: 0.3)) { phase = (phase + 1) % 3 }
        }
    }
}

struct CameraPickerView: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                let normalized = img.normalizedOrientation()
                onImage(normalized)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return normalized
    }
}

#Preview {
    LLMDemoView(gemma: GemmaEngine())
}
