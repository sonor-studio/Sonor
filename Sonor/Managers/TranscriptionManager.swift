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
    private var unloadTimer: Timer?
    
    public var activeModelName: String {
        switch currentEngineType {
        case .whisper:
            return ModelManager.shared.selectedWhisperModelId
        case .mlx:
            return ModelManager.shared.selectedMLXModelId ?? "MLX Model"
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
        
        switch currentEngineType {
        case .whisper:
            let modelPath = ModelManager.shared.whisperModelURL.path
            if FileManager.default.fileExists(atPath: modelPath) {
                let engine = WhisperEngine(modelPath: modelPath)
                try await engine.prepare()
                self.activeEngine = engine
            } else {
                throw NSError(domain: "TranscriptionManager", code: 10, userInfo: [NSLocalizedDescriptionKey: "Whisper model file not found."])
            }
        case .appleSpeech:
            let engine = AppleSpeechEngine()
            try await engine.prepare()
            self.activeEngine = engine
        case .mlx:
            let selectedMLXId = ModelManager.shared.selectedMLXModelId ?? "sensevoice-small"
            guard let config = ModelManager.shared.availableMLXModels.first(where: { $0.id == selectedMLXId }) else {
                throw NSError(domain: "TranscriptionManager", code: 12, userInfo: [NSLocalizedDescriptionKey: "Selected MLX model not found in config."])
            }
            let engine = MLXEngine(modelId: config.id, repoId: config.repoId)
            try await engine.prepare()
            self.activeEngine = engine
        }
        
        self.isLoaded = true
    }
    
    public func transcribe(audioSamples: [Float], language: String, initialPrompt: String?) async throws -> String {
        try await ensureEngineReady()
        
        guard let engine = activeEngine else {
            throw NSError(domain: "TranscriptionManager", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize active engine."])
        }
        
        return try await engine.transcribe(audioSamples: audioSamples, language: language, initialPrompt: initialPrompt)
    }
}
