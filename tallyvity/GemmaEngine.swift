import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import MLXHuggingFace
import HuggingFace
import Tokenizers
import UIKit

@MainActor
@Observable
final class GemmaEngine {

    enum State: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case generating
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var output: String = ""

    private var container: ModelContainer?

    var isLoaded: Bool {
        container != nil && (state == .ready || state == .generating)
    }

    private static let downloadedKey = "gemmaModelDownloaded"

    var wasDownloaded: Bool {
        UserDefaults.standard.bool(forKey: Self.downloadedKey)
    }

    func load() async {
        guard !isLoaded else { return }
        state = .loading
        do {
            let config = ModelConfiguration(id: "mlx-community/gemma-4-e2b-it-4bit")
            let downloader = HubDownloader()
            let loader = HFTokenizerLoader()
            let loaded = try await VLMModelFactory.shared.loadContainer(
                from: downloader,
                using: loader,
                configuration: config,
                progressHandler: { [weak self] progress in
                    guard let self else { return }
                    Task { @MainActor in
                        self.state = .downloading(progress.fractionCompleted)
                    }
                }
            )
            container = loaded
            UserDefaults.standard.set(true, forKey: Self.downloadedKey)
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func generate(image: UIImage? = nil, prompt: String) async {
        guard let container else { return }
        state = .generating
        output = ""
        do {
            var images: [UserInput.Image] = []
            let content: Any
            if let uiImage = image {
                let normalized = uiImage.normalizedForVLM()
                let ci = normalized.cgImage.map { CIImage(cgImage: $0) } ?? CIImage(image: normalized)
                if let ci { images = [.ciImage(ci)] }
                content = [["type": "image"], ["type": "text", "text": prompt]] as [[String: String]]
            } else {
                content = prompt
            }
            let userInput = UserInput(
                prompt: .messages([["role": "user", "content": content]]),
                images: images
            )
            let lmInput = try await container.prepare(input: userInput)
            let stream = try await container.generate(
                input: lmInput,
                parameters: GenerateParameters(maxTokens: 512)
            )
            var publishBuffer = ""
            var lastPublish = Date()
            for await event in stream {
                if case .chunk(let text) = event {
                    publishBuffer += text
                    if Date().timeIntervalSince(lastPublish) >= 0.2 {
                        output += publishBuffer
                        publishBuffer = ""
                        lastPublish = Date()
                    }
                }
            }
            if !publishBuffer.isEmpty {
                output += publishBuffer
            }
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func compareImages(_ first: UIImage, _ second: UIImage, prompt: String) async -> String {
        guard let container else { return "" }
        state = .generating
        let firstN = first.normalizedForVLM()
        let secondN = second.normalizedForVLM()
        let ci1 = firstN.cgImage.map { CIImage(cgImage: $0) } ?? CIImage(image: firstN)
        let ci2 = secondN.cgImage.map { CIImage(cgImage: $0) } ?? CIImage(image: secondN)
        guard let ci1, let ci2 else { state = .ready; return "" }
        let content = [["type": "image"], ["type": "image"], ["type": "text", "text": prompt]] as [[String: String]]
        do {
            let userInput = UserInput(
                prompt: .messages([["role": "user", "content": content]]),
                images: [.ciImage(ci1), .ciImage(ci2)]
            )
            let lmInput = try await container.prepare(input: userInput)
            let stream = try await container.generate(
                input: lmInput,
                parameters: GenerateParameters(maxTokens: 512)
            )
            var result = ""
            for await event in stream {
                if case .chunk(let text) = event { result += text }
            }
            state = .ready
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            state = .error(error.localizedDescription)
            return ""
        }
    }

    func cancelError() { state = isLoaded ? .ready : .idle }
}

// MARK: - HuggingFace bridge (inlined from MLXHuggingFace macros)

private struct HubDownloader: MLXLMCommon.Downloader {
    private let hub = HubClient()

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = Repo.ID(rawValue: id) else {
            throw HubClientError.invalidRepoID(id)
        }
        return try await hub.downloadSnapshot(
            of: repoID,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in progressHandler(progress) }
        )
    }
}

private struct HFTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return HFTokenizerBridge(upstream)
    }
}

private struct HFTokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

extension UIImage {
    func normalizedForVLM() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return out
    }
}

private enum HubClientError: LocalizedError {
    case invalidRepoID(String)
    var errorDescription: String? {
        if case .invalidRepoID(let id) = self {
            return "Invalid HuggingFace repo ID: '\(id)'"
        }
        return nil
    }
}
