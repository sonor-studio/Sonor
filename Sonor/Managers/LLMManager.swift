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

    private init() {
        NotificationCenter.default.addObserver(forName: Notification.Name("GemmaOffloadTimeoutChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if ModelManager.shared.isGemmaLoaded {
                    self.startIdleTimer()
                }
            }
        }
    }

    private var idleOffloadTimer: Timer?

    private func startIdleTimer() {
        idleOffloadTimer?.invalidate()
        idleOffloadTimer = nil
        let actualTimeout = UserDefaults.standard.integer(forKey: "gemmaOffloadTimeout")
        // If 0 or missing (default 5 but let's check), though AppStorage default is 5.
        // Actually AppStorage default is 5. Let's read from UserDefaults directly.
        let actualTimeoutValue = UserDefaults.standard.object(forKey: "gemmaOffloadTimeout") as? Int ?? 5
        guard actualTimeoutValue > 0 else { return }
        
        idleOffloadTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(actualTimeoutValue * 60), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.releaseModel()
            }
        }
    }
    
    private func cancelIdleTimer() {
        idleOffloadTimer?.invalidate()
        idleOffloadTimer = nil
    }

    func cleanStream(text: String, systemPrompt: String, onToken: @escaping (String) -> Bool) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        if systemPrompt.isEmpty { return text }

        await MainActor.run {
            cancelIdleTimer()
            ModelManager.shared.lastGemmaUsageTime = Date()
        }

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
            await MainActor.run {
                ModelManager.shared.lastGemmaUsageTime = Date()
                self.startIdleTimer()
            }
            return fullText
        } catch {
            print("Error in cleanStream loading Gemma: \(error)")
            await MainActor.run {
                self.startIdleTimer()
            }
            return text
        }
    }

    func ensureModelWarmed() async {
        if isReady { return }
        await MainActor.run {
            cancelIdleTimer()
        }
        do {
            let session = try await getSession()
            await session.clear()
            let _ = try await session.respond(to: "Say \"hello\" and return {\"result\": \"ok\"}")
            isReady = true
            await MainActor.run {
                ModelManager.shared.isGemmaLoaded = true
                ModelManager.shared.lastGemmaUsageTime = Date()
                self.startIdleTimer()
            }
        } catch {
            print("Error in ensureModelWarmed loading Gemma: \(error)")
            await MainActor.run {
                self.startIdleTimer()
            }
        }
    }

    func releaseModel() {
        self.modelContainer = nil
        self.isReady = false
        ModelManager.shared.isGemmaLoaded = false
        idleOffloadTimer?.invalidate()
        idleOffloadTimer = nil
        MLX.Memory.clearCache()
    }

    private var containerTask: Task<ModelContainer, Error>?

    private func getContainer() async throws -> ModelContainer {
        if let container = self.modelContainer { return container }
        if let task = containerTask { return try await task.value }

        let task = Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            let config = ModelConfiguration(id: ModelManager.shared.gemmaModelId)
            let container = try await LLMModelFactory.shared.loadContainer(
                from: NativeHubDownloader(downloadBase: ModelManager.shared.modelsDirectory),
                using: #huggingFaceTokenizerLoader(),
                configuration: config
            )
            let timeTaken = CFAbsoluteTimeGetCurrent() - startTime
            await MainActor.run {
                ModelManager.shared.gemmaInitializeTime = timeTaken
            }
            return container
        }
        self.containerTask = task
        let container = try await task.value
        self.modelContainer = container
        self.containerTask = nil
        await MainActor.run {
            ModelManager.shared.isGemmaLoaded = true
        }
        return container
    }

    private func getSession() async throws -> ChatSession {
        let container = try await getContainer()
        let params = GenerateParameters(temperature: 0.7)
        return ChatSession(container, instructions: "", generateParameters: params)
    }


}
