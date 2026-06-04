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

    func clean(text: String, mode: ProcessingMode) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        if mode == .raw { return text }

        let prompt = buildPrompt(for: text, mode: mode)

        do {
            let session = try await getSession()
            await session.clear()
            let raw = try await session.respond(to: prompt)
            let cleaned = extractResult(from: raw)
            await session.clear()
            MLX.Memory.clearCache()
            return cleaned
        } catch {
            return text
        }
    }

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

    private func buildPrompt(for text: String, mode: ProcessingMode) -> String {
        if mode == .formal {
            return """
            Jesteś asystentem językowym. Otrzymujesz fragment tekstu wygenerowany przez system rozpoznawania mowy.
            Zadanie: przekształć otrzymany tekst na styl formalny, zachowując pierwotne znaczenie, kontekst oraz język oryginału.
            Ważne ograniczenia (koniecznie przestrzegaj):
            1) NIE zmieniaj sensu ani informacji zawartych w oryginalnym tekście.
            2) NIE dodawaj nowych informacji, treści, ani słów, których nie ma w oryginale.
            3) NIE usuwaj treści, nie ucinaj wypowiedzi. Zmieniaj tylko styl na formalny.
            4) Odpowiedz WYŁĄCZNIE poprawnym JSON-em, bez żadnego tekstu przed ani po:
            {"result": "<sformalizowany tekst>"}

            Tekst: \(text)
            """
        } else {
            return """
            Jesteś asystentem językowym. Otrzymujesz fragment tekstu wygenerowany przez system rozpoznawania mowy.
            Zadanie: Zrób z chaotycznej wypowiedzi ładną i uporządkowaną. Ułóż ją ładnie i schludnie. Dodaj punktacje, listę lub pozmieniaj słowa, aby ładnie i schludnie wyglądało.
            ZACHOWAJ cały zamysł, sens wypowiedzi oraz styl.
            Ważne ograniczenia (koniecznie przestrzegaj):
            1) NIE zmieniaj znaczenia ani sensu.
            2) NIE dodawaj nowych informacji, treści, ani słów, których użytkownik nie powiedział.
            3) NIE usuwaj treści, nie ucinaj wypowiedzi. Możesz pominąć jedynie ewidentne zająknięcia (yyyy, eeee).
            4) Odpowiedz WYŁĄCZNIE poprawnym JSON-em, bez żadnego tekstu przed ani po:
            {"result": "<uporządkowany tekst>"}

            Tekst: \(text)
            """
        }
    }



    private func extractResult(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonRange = findJSONObject(in: trimmed),
           let data = String(trimmed[jsonRange]).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? String {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func findJSONObject(in text: String) -> Range<String.Index>? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else { return nil }
        return start..<text.index(after: end)
    }
}
