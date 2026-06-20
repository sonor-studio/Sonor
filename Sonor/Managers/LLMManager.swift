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
    private var chatSession: ChatSession?
    private(set) var isReady = false
    private var generationTask: Task<ChatSession, Error>?

    private init() {}



    func cleanStream(text: String, systemPrompt: String, onToken: @escaping (String) -> Void) async -> String {
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
                onToken(token)
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
        self.chatSession = nil
        self.modelContainer = nil
        self.isReady = false
        MLX.Memory.clearCache()
    }

    private func getSession() async throws -> ChatSession {
        if let session = self.chatSession { return session }
        if let task = generationTask { return try await task.value }

        let task = Task {
            let config = ModelConfiguration(id: "mlx-community/gemma-3-4b-it-qat-4bit")
            let container = try await LLMModelFactory.shared.loadContainer(
                from: NativeHubDownloader(downloadBase: ModelManager.shared.modelsDirectory),
                using: #huggingFaceTokenizerLoader(),
                configuration: config
            )
            let params = GenerateParameters(temperature: 0.3)
            let session = ChatSession(container, instructions: "", generateParameters: params)
            return session
        }
        self.generationTask = task
        let session = try await task.value
        self.chatSession = session
        self.generationTask = nil
        return session
    }


}
