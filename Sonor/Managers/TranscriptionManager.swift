import Foundation
import Combine
import SwiftUI

public enum EngineType: String, Equatable, Codable {
    case whisper
    case appleSpeech
    case mlx
}

@MainActor
public class TranscriptionManager: ObservableObject {
    public static let shared = TranscriptionManager()
    
    @Published public private(set) var activeEngine: TranscriptionEngine?
    @Published public var currentEngineType: EngineType = .whisper
    @Published public var isLoaded: Bool = false
    @Published public var lastUsedTime: Date? = nil
    @Published public var initializeTime: TimeInterval? = nil
    private var unloadTimer: Timer?
    public var modelOverrideId: String? = nil
    
    public var activeModelName: String {
        if let override = modelOverrideId, override != "default" {
            if let w = ModelManager.shared.availableWhisperModels.first(where: { $0.id == override }) {
                return w.name
            } else if let m = ModelManager.shared.availableMLXModels.first(where: { $0.id == override }) {
                return m.name
            } else if override == "appleSpeech" {
                return "Apple Speech"
            }
        }
        
        switch currentEngineType {
        case .whisper:
            let id = ModelManager.shared.selectedWhisperModelId
            return ModelManager.shared.availableWhisperModels.first(where: { $0.id == id })?.name ?? id
        case .mlx:
            let id = ModelManager.shared.selectedMLXModelId
            return ModelManager.shared.availableMLXModels.first(where: { $0.id == id })?.name ?? id ?? "MLX Model"
        case .appleSpeech:
            return "Apple Speech"
        }
    }
    
    private init() {
        // Load preference from UserDefaults if exists
        if let savedTypeStr = UserDefaults.standard.string(forKey: "selectedEngineType"),
           let savedType = EngineType(rawValue: savedTypeStr) {
            self.currentEngineType = savedType
        }
    }
    
    public func setEngineType(_ type: EngineType) {
        self.currentEngineType = type
        UserDefaults.standard.set(type.rawValue, forKey: "selectedEngineType")
        resetEngine() // Force unload the old engine to free memory
    }
    
    public func applyModelOverride(_ overrideId: String?) {
        if self.modelOverrideId != overrideId {
            self.modelOverrideId = overrideId
            resetEngine()
        }
    }
    
    public func resetEngine() {
        // Stop current operations and free resources
        activeEngine?.unload()
        activeEngine = nil
        isLoaded = false
        unloadTimer?.invalidate()
        unloadTimer = nil
    }
    
    public func cancelUnloadTimer() {
        unloadTimer?.invalidate()
        unloadTimer = nil
    }
    
    public func resetUnloadTimer() {
        unloadTimer?.invalidate()
        let timeout = UserDefaults.standard.integer(forKey: "transcriptionUnloadTimeout")
        guard timeout > 0 else { return }
        
        unloadTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeout * 60), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetEngine()
            }
        }
    }
    
    public func ensureEngineReady() async throws {
        if activeEngine != nil && activeEngine!.isReady {
            return
        }
        
        let targetEngineType: EngineType
        var targetModelId: String? = nil
        
        if let override = modelOverrideId, override != "default" {
            if ModelManager.shared.availableWhisperModels.contains(where: { $0.id == override }) {
                targetEngineType = .whisper
                targetModelId = override
            } else if ModelManager.shared.availableMLXModels.contains(where: { $0.id == override }) {
                targetEngineType = .mlx
                targetModelId = override
            } else if override == "appleSpeech" {
                targetEngineType = .appleSpeech
                targetModelId = nil
            } else {
                targetEngineType = currentEngineType
            }
        } else {
            targetEngineType = currentEngineType
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        switch targetEngineType {
        case .whisper:
            let selectedId = targetModelId ?? ModelManager.shared.selectedWhisperModelId
            guard let modelURL = ModelManager.shared.urlForWhisperModel(id: selectedId) else {
                throw NSError(domain: "TranscriptionManager", code: 10, userInfo: [NSLocalizedDescriptionKey: "Whisper model URL not found."])
            }
            let modelPath = modelURL.path
            if FileManager.default.fileExists(atPath: modelPath) {
                let engine = WhisperEngine(modelPath: modelPath)
                try await engine.prepare()
                self.activeEngine = engine
            } else {
                throw NSError(domain: "TranscriptionManager", code: 10, userInfo: [NSLocalizedDescriptionKey: "Whisper model file not found at path: \(modelPath)"])
            }
        case .appleSpeech:
            let engine = AppleSpeechEngine()
            try await engine.prepare()
            self.activeEngine = engine
        case .mlx:
            let selectedMLXId = targetModelId ?? ModelManager.shared.selectedMLXModelId ?? "sensevoice-small"
            guard let config = ModelManager.shared.availableMLXModels.first(where: { $0.id == selectedMLXId }) else {
                throw NSError(domain: "TranscriptionManager", code: 12, userInfo: [NSLocalizedDescriptionKey: "Selected MLX model not found in config."])
            }
            let engine = MLXEngine(modelId: config.id, repoId: config.repoId)
            try await engine.prepare()
            self.activeEngine = engine
        }

        self.initializeTime = CFAbsoluteTimeGetCurrent() - startTime
        self.isLoaded = true
    }

    public func transcribe(audioSamples: [Float], language: String, initialPrompt: String?) async throws -> String {
        try await ensureEngineReady()

        guard let engine = activeEngine else {
            throw NSError(domain: "TranscriptionManager", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize active engine."])
        }

        let result = try await engine.transcribe(audioSamples: audioSamples, language: language, initialPrompt: initialPrompt)
        self.lastUsedTime = Date()
        return result
    }
}
