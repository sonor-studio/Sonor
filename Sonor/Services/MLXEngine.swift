import Foundation
import Darwin
import MachO
import MLXAudioSTT
import MLX
import Hub

final class MLXEngine: TranscriptionEngine {
    var isReady: Bool = false
    var name: String { "MLX (\(repoId))" }
    
    // We store the model as Any because different models might have different types,
    // though they might all conform to a common protocol in MLXAudioSTT.
    // For now, we will handle them specifically.
    private nonisolated(unsafe) var senseVoiceModel: SenseVoiceModel?
    private nonisolated(unsafe) var moonshineModel: MoonshineModel?
    private nonisolated(unsafe) var parakeetModel: ParakeetModel?
    private nonisolated(unsafe) var qwen3ASRModel: Qwen3ASRModel?
    private nonisolated(unsafe) var canaryModel: CanaryModel?
    private nonisolated(unsafe) var nemotronModel: NemotronASRModel?
    private nonisolated(unsafe) var graniteModel: GraniteSpeechModel?
    private nonisolated(unsafe) var fireRedModel: FireRedASR2Model?
    private nonisolated(unsafe) var cohereModel: CohereTranscribeModel?
    
    private let modelId: String
    private let repoId: String
    
    init(modelId: String, repoId: String) {
        self.modelId = modelId
        self.repoId = repoId
    }
    

    
    func prepare() async throws {
        if isReady { return }
        
        let api = HubApi(downloadBase: ModelManager.shared.modelsDirectory, cache: nil, useBackgroundSession: false)
        let repo = Hub.Repo(id: repoId)
        let modelDir = api.localRepoLocation(repo)
        
        // Instantiate the correct model based on the family or id
        // Usually fromPretrained takes a String for the HF repo id or local path. 
        // We will pass the local path.

        
        if repoId.lowercased().contains("sensevoice") {
            self.senseVoiceModel = try SenseVoiceModel.fromDirectory(modelDir)
        } else if repoId.lowercased().contains("moonshine") {
            self.moonshineModel = try await MoonshineModel.fromModelDirectory(modelDir)
        } else if repoId.lowercased().contains("parakeet") {
            self.parakeetModel = try ParakeetModel.fromDirectory(modelDir)
        } else if repoId.lowercased().contains("qwen3") {
            self.qwen3ASRModel = try await Qwen3ASRModel.fromModelDirectory(modelDir)
        } else if repoId.lowercased().contains("canary") {
            self.canaryModel = try await CanaryModel.fromModelDirectory(modelDir)
        } else if repoId.lowercased().contains("nemotron") {
            self.nemotronModel = try NemotronASRModel.fromDirectory(modelDir)
        } else if repoId.lowercased().contains("granite") {
            self.graniteModel = try await GraniteSpeechModel.fromModelDirectory(modelDir)
        } else if repoId.lowercased().contains("firered") {
            self.fireRedModel = try FireRedASR2Model.fromDirectory(modelDir)
        } else if repoId.lowercased().contains("cohere") {
            self.cohereModel = try CohereTranscribeModel.fromDirectory(modelDir)
        } else {
            throw NSError(domain: "MLXEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported MLX model type: \(repoId)"])
        }
        
        isReady = true
    }
    
    func transcribe(audioSamples: [Float], language: String, initialPrompt: String?) async throws -> String {
        guard isReady else {
            throw NSError(domain: "MLXEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        guard !audioSamples.isEmpty else { return "" }
        
        if repoId.lowercased().contains("qwen3") && !CommandLine.arguments.contains("--worker-mode") {
            return try await runInWorker(audioSamples: audioSamples, language: language)
        }
        
        return try await performTranscription(audioSamples: audioSamples, language: language, initialPrompt: initialPrompt)
    }
    
    private func runInWorker(audioSamples: [Float], language: String) async throws -> String {
        // Write audio samples to a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let audioFile = tempDir.appendingPathComponent(UUID().uuidString + ".raw")
        
        let audioData = audioSamples.withUnsafeBufferPointer { Data(buffer: $0) }
        try audioData.write(to: audioFile)
        
        return try await Task.detached {
            defer {
                try? FileManager.default.removeItem(at: audioFile)
            }
            
            guard let executablePath = Bundle.main.executablePath else {
                throw NSError(domain: "MLXEngine", code: 10, userInfo: [NSLocalizedDescriptionKey: "Cannot find executable path"])
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = [
                "--worker-mode",
                "--repo-id", self.repoId,
                "--audio", audioFile.path,
                "--language", language
            ]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            // Run process
            try process.run()
            
            // READ FIRST to prevent deadlock! If the child process writes more than 64KB, 
            // it will block waiting for the parent to read. If the parent is blocked in 
            // waitUntilExit(), both will hang forever.
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            let outputString = String(data: outputData, encoding: .utf8) ?? ""
            
            if process.terminationStatus != 0 || process.terminationReason == .uncaughtSignal {
                // This is the magic! If Qwen3 crashes with OOM (abort), we catch it here instead of crashing the main app!
                throw NSError(domain: "MLXEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: String(localized: "OOM Warning: Brakuje RAMu dla tego nagrania. Zamknij inne programy, albo użyj lżejszego modelu.")])
            }
            
            for line in outputString.components(separatedBy: .newlines) {
                if line.hasPrefix("SUCCESS:") {
                    let base64 = String(line.dropFirst("SUCCESS:".count))
                    if let data = Data(base64Encoded: base64), let text = String(data: data, encoding: .utf8) {
                        return text
                    }
                } else if line.hasPrefix("ERROR:") {
                    let errorText = String(line.dropFirst("ERROR:".count))
                    throw NSError(domain: "MLXEngine", code: 5, userInfo: [NSLocalizedDescriptionKey: errorText])
                }
            }
            
            throw NSError(domain: "MLXEngine", code: 6, userInfo: [NSLocalizedDescriptionKey: "Worker process failed silently"])
        }.value
    }
    
    func performTranscription(audioSamples: [Float], language: String, initialPrompt: String?) async throws -> String {
        
        // MLXAudioSTT models usually have a generate function taking audio data. 
        // Some also take language or prompts depending on the model struct.
        
        return await Task.detached {
            defer {
                MLX.Memory.clearCache()
            }
            let mlxAudio = MLXArray(audioSamples)
            eval(mlxAudio)
            
            if let model = self.senseVoiceModel {
                let output = model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.moonshineModel {
                let output = model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.parakeetModel {
                let output = model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.qwen3ASRModel {
                let output = model.generate(audio: mlxAudio, language: language)
                return output.text
            } else if let model = self.canaryModel {
                let output = model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.nemotronModel {
                let output = model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.graniteModel {
                let output = model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.fireRedModel {
                let output = model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.cohereModel {
                let output = model.generate(audio: mlxAudio)
                return output.text
            }
            
            return ""
        }.value
    }
    
    func unload() {
        self.senseVoiceModel = nil
        self.moonshineModel = nil
        self.parakeetModel = nil
        self.qwen3ASRModel = nil
        self.canaryModel = nil
        self.nemotronModel = nil
        self.graniteModel = nil
        self.fireRedModel = nil
        self.cohereModel = nil
        self.isReady = false
        // Force garbage collection of MLX memory
        MLX.Memory.clearCache()
    }
}
