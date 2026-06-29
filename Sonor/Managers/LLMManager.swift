import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Hub
import Tokenizers

struct NativeHubDownloader: MLXLMCommon.Downloader {
    let api: HubApi
    init(downloadBase: URL) {
        self.api = HubApi(downloadBase: downloadBase, cache: nil)
    }
    func download(id: String, revision: String?, matching patterns: [String], useLatest: Bool, progressHandler: @Sendable @escaping (Progress) -> Void) async throws -> URL {
        return try await api.snapshot(from: id, revision: revision ?? "main", matching: patterns, progressHandler: progressHandler)
    }
}


extension ChatSession: @unchecked @retroactive Sendable {}

@MainActor
final class LLMManager {
    static let shared = LLMManager()

    private var modelContainer: ModelContainer?
    private(set) var isReady = false

    private init() {}



    func cleanStream(text: String, systemPrompt: String, onToken: @escaping (String) -> Bool) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        if systemPrompt.isEmpty { return text }

        let prompt = "\(systemPrompt)\n\nTekst: \(text)"
        var fullText = ""

        do {
            let session = try await getSession()
            await session.clear()
            for try await token in session.streamResponse(to: prompt) {
                if Task.isCancelled {
                    break
                }
                fullText += token
                let shouldContinue = onToken(token)
                if !shouldContinue {
                    break
                }
            }
            await session.clear()
            MLX.Memory.clearCache()
            return fullText
        } catch {
            return text
        }
    }

    func ensureModelWarmed() async {
        if isReady { return }
        do {
            let session = try await getSession()
            await session.clear()
            let _ = try await session.respond(to: "Say \"hello\" and return {\"result\": \"ok\"}")
            isReady = true
        } catch {
        }
    }

    func releaseModel() {
        self.modelContainer = nil
        self.isReady = false
        MLX.Memory.clearCache()
    }

    private var containerTask: Task<ModelContainer, Error>?

    private func getContainer() async throws -> ModelContainer {
        if let container = self.modelContainer { return container }
        if let task = containerTask { return try await task.value }

        let task = Task {
            let config = ModelConfiguration(id: ModelManager.shared.gemmaModelId)
            let container = try await LLMModelFactory.shared.loadContainer(
                from: NativeHubDownloader(downloadBase: ModelManager.shared.modelsDirectory),
                using: #huggingFaceTokenizerLoader(),
                configuration: config
            )
            return container
        }
        self.containerTask = task
        let container = try await task.value
        self.modelContainer = container
        self.containerTask = nil
        return container
    }

    private func getSession() async throws -> ChatSession {
        let container = try await getContainer()
        let params = GenerateParameters(temperature: 0.7)
        return ChatSession(container, instructions: "", generateParameters: params)
    }


}
