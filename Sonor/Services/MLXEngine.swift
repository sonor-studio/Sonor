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
    private var senseVoiceModel: SenseVoiceModel?
    private var moonshineModel: MoonshineModel?
    private var parakeetModel: ParakeetModel?
    private var qwen3ASRModel: Qwen3ASRModel?
    
    private let modelId: String
    private let repoId: String
    
    init(modelId: String, repoId: String) {
        self.modelId = modelId
        self.repoId = repoId
    }
    
    private func getFreeMemoryGB() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let freeMemory = Double(stats.free_count) * Double(vm_kernel_page_size)
            let inactiveMemory = Double(stats.inactive_count) * Double(vm_kernel_page_size)
            return (freeMemory + inactiveMemory) / 1073741824.0
        }
        return 8.0 // Fallback
    }
    
    func prepare() async throws {
        if isReady { return }
        
        let api = HubApi(downloadBase: ModelManager.shared.modelsDirectory, cache: nil, useBackgroundSession: false)
        let repo = Hub.Repo(id: repoId)
        let modelDir = api.localRepoLocation(repo)
        
        // Instantiate the correct model based on the family or id
        // Usually fromPretrained takes a String for the HF repo id or local path. 
        // We will pass the local path.
        let path = modelDir.path
        
        if repoId.lowercased().contains("sensevoice") {
            self.senseVoiceModel = try await Task.detached { try SenseVoiceModel.fromDirectory(modelDir) }.value
        } else if repoId.lowercased().contains("moonshine") {
            self.moonshineModel = try await Task.detached { try await MoonshineModel.fromModelDirectory(modelDir) }.value
        } else if repoId.lowercased().contains("parakeet") {
            self.parakeetModel = try await Task.detached { try ParakeetModel.fromDirectory(modelDir) }.value
        } else if repoId.lowercased().contains("qwen3") {
            self.qwen3ASRModel = try await Task.detached { try await Qwen3ASRModel.fromModelDirectory(modelDir) }.value
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
        
        return try await Task.detached {
            defer {
                MLX.GPU.clearCache()
            }
            let mlxAudio = MLXArray(audioSamples)
            eval(mlxAudio)
            
            if let model = self.senseVoiceModel {
                let output = try model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.moonshineModel {
                let output = try model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.parakeetModel {
                let output = try model.generate(audio: mlxAudio)
                return output.text
            } else if let model = self.qwen3ASRModel {
                let output = try model.generate(audio: mlxAudio, language: language)
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
        self.isReady = false
        // Force garbage collection of MLX memory
        MLX.GPU.clearCache()
    }
}
