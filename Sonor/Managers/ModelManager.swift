import Foundation
import Combine
import MLXHuggingFace
import Hub
import HuggingFace
import CryptoKit
import SwiftUI

/// Represents the current state of a model file on disk.
enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case paused(progress: Double)
    case downloaded
    
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
    
    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

// Handles downloading and caching AI models locally.
@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()
    struct DownloadStats: Equatable {
        var downloadedBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var speedBytesPerSecond: Double = 0
        var speedHistory: [Double] = []
    }
    
    @Published var whisperStates: [String: DownloadState] = [:]
    @Published var gemmaState: DownloadState = .notDownloaded
    @Published var isTranscriptionLoaded: Bool = false
    @Published var lastTranscriptionUsageTime: Date? = nil
    @Published var transcriptionInitializeTime: TimeInterval? = nil
    @Published var isAssistantLoaded: Bool = false
    @Published var lastAssistantUsageTime: Date? = nil
    @Published var assistantInitializeTime: TimeInterval? = nil
    @Published var mlxDownloadStats: [String: DownloadStats] = [:]
    @Published var whisperDownloadStats: [String: DownloadStats] = [:]
    
    private var downloadBytesTracker: [String: (bytes: Int64, date: Date)] = [:]
    private var speedTimer: Timer?
    
    @Published var showModelsRequiredModal = false
    @Published var downloadError: String? = nil
    @Published var showDownloadErrorModal = false
    @Published var showModelSelector = false
    @Published var mlxStates: [String: DownloadState] = [:]
    @Published var selectedMLXModelId: String? {
        didSet {
            UserDefaults.standard.set(selectedMLXModelId, forKey: "selectedMLXModelId")
            NotificationCenter.default.post(name: Notification.Name("ReleaseMLXContext"), object: nil)
        }
    }
    
    let modelsDirectory: URL
    let gemmaModelId = "mlx-community/gemma-3-4b-it-qat-4bit"
    
    static let whisperLanguageList: [String] = [
        "Afrikaans (Afrikaans)", "Albanian (Shqip)", "Amharic (አማርኛ)", "Arabic (العربية)", "Armenian (Հայերեն)", "Assamese (অসমীয়া)", "Azerbaijani (Azərbaycan)", "Bashkir (Башҡорт)", "Basque (Euskara)", "Belarusian (Беларуская)", "Bengali (বাংলা)", "Bosnian (Bosanski)", "Breton (Brezhoneg)", "Bulgarian (Български)", "Catalan (Català)", "Chinese (中文)", "Croatian (Hrvatski)", "Czech (Čeština)", "Danish (Dansk)", "Dutch (Nederlands)", "English (English)", "Estonian (Eesti)", "Faroese (Føroyskt)", "Finnish (Suomi)", "French (Français)", "Galician (Galego)", "Georgian (ქართული)", "German (Deutsch)", "Greek (Ελληνικά)", "Gujarati (ગુજરાતી)", "Haitian Creole (Kreyòl Ayisyen)", "Hausa (Hausa)", "Hawaiian (ʻŌlelo Hawaiʻi)", "Hebrew (עברית)", "Hindi (हिन्दी)", "Hungarian (Magyar)", "Icelandic (Íslenska)", "Indonesian (Bahasa Indonesia)", "Italian (Italiano)", "Japanese (日本語)", "Javanese (Basa Jawa)", "Kannada (ಕನ್ನಡ)", "Kazakh (Қазақ)", "Khmer (ខ្មែរ)", "Korean (한국어)", "Lao (ລາວ)", "Latin (Latina)", "Latvian (Latviešu)", "Lingala (Lingála)", "Lithuanian (Lietuvių)", "Luxembourgish (Lëtzebuergesch)", "Macedonian (Македонски)", "Malagasy (Malagasy)", "Malay (Bahasa Melayu)", "Malayalam (മലയാളം)", "Maltese (Malti)", "Maori (Māori)", "Marathi (मराठी)", "Mongolian (Монгол)", "Myanmar (မြန်မာ)", "Nepali (नेपाली)", "Norwegian (Norsk)", "Nynorsk (Norsk Nynorsk)", "Occitan (Occitan)", "Pashto (پښتو)", "Persian (فارسی)", "Polish (Polski)", "Portuguese (Português)", "Punjabi (ਪੰਜਾਬੀ)", "Romanian (Română)", "Russian (Русский)", "Sanskrit (संस्कृतम्)", "Serbian (Српски)", "Shona (ChiShona)", "Sindhi (سنڌي)", "Sinhala (සිංහල)", "Slovak (Slovenčina)", "Slovenian (Slovenščina)", "Somali (Soomaali)", "Spanish (Español)", "Sundanese (Basa Sunda)", "Swahili (Kiswahili)", "Swedish (Svenska)", "Tagalog (Tagalog)", "Tajik (Тоҷикӣ)", "Tamil (தமிழ்)", "Tatar (Татар)", "Telugu (తెలుగు)", "Thai (ไทย)", "Tibetan (བོད་སྐད་)", "Turkish (Türkçe)", "Turkmen (Türkmen)", "Ukrainian (Українська)", "Urdu (اردو)", "Uzbek (Oʻzbek)", "Vietnamese (Tiếng Việt)", "Welsh (Cymraeg)", "Yiddish (ייִדיש)", "Yoruba (Yorùbá)"
    ]
    
    protocol ModelMetadata {
        var weight: String { get }
        var languages: String { get }
        var accuracy: Double { get }
        var speed: Double { get }
        var company: String { get }
        var parameters: String? { get }
        var supportedLanguagesList: [String] { get }
    }

    let modelFamilyDescriptions: [String: String] = [
        "Whisper": String(localized: "Industry standard open-source transcription model from OpenAI. Highly accurate."),
        "SenseVoice": String(localized: "Ultra-fast multilingual model with excellent accent recognition from Alibaba."),
        "Moonshine": String(localized: "Tiny, highly optimized models for resource-constrained environments from UsefulSensors."),
        "Parakeet": String(localized: "High accuracy ASR models built on the NeMo framework from NVIDIA."),
        "Qwen3": String(localized: "Large, powerful multilingual models with high reasoning capability from Alibaba."),
        "Canary": String(localized: "High precision end-to-end model from NVIDIA, specializing in punctuation and formatting."),
        "Nemotron": String(localized: "Extremely fast and accurate transcription model from NVIDIA."),
        "Granite": String(localized: "Enterprise-grade speech model from IBM, highly reliable for clear speech."),
        "FireRed": String(localized: "Next-gen highly efficient STT system offering high accuracy across diverse languages."),
        "Cohere": String(localized: "Business-oriented model designed for high accuracy with specialized vocabulary.")
    ]

    struct WhisperModel: Identifiable, Equatable, ModelMetadata {
        let id: String
        let name: String
        let repoId: String
        let filename: String
        let description: String
        let expectedSize: Int64
        let expectedSHA256: String?
        let weight: String
        let languages: String
        let accuracy: Double
        let speed: Double
        let company: String
        let parameters: String?
        
        var supportedLanguagesList: [String] {
            return languages == "English" ? ["English (English)"] : ModelManager.whisperLanguageList
        }
    }

    let availableWhisperModels: [WhisperModel] = [
        WhisperModel(
            id: "tiny.en",
            name: "Whisper Tiny",
            repoId: "ggerganov/whisper.cpp",
            filename: "ggml-tiny.en.bin",
            description: String(localized: "Extremely fast, very low memory usage. Good for basic english dictation."),
            expectedSize: 77_704_715,
            expectedSHA256: nil,
            weight: "75 MB",
            languages: "EN",
            accuracy: 0.6,
            speed: 1.0,
            company: "OpenAI",
            parameters: "39M"
        ),
        WhisperModel(
            id: "base.en",
            name: "Whisper Base",
            repoId: "ggerganov/whisper.cpp",
            filename: "ggml-base.en.bin",
            description: String(localized: "Fast, low memory usage. Better accuracy than Tiny."),
            expectedSize: 147_964_211,
            expectedSHA256: nil,
            weight: "142 MB",
            languages: "EN",
            accuracy: 0.7,
            speed: 0.9,
            company: "OpenAI",
            parameters: "74M"
        ),
        WhisperModel(
            id: "small.en",
            name: "Whisper Small",
            repoId: "ggerganov/whisper.cpp",
            filename: "ggml-small.en.bin",
            description: String(localized: "Good balance of speed and accuracy for English."),
            expectedSize: 487_614_201,
            expectedSHA256: nil,
            weight: "466 MB",
            languages: "EN",
            accuracy: 0.85,
            speed: 0.7,
            company: "OpenAI",
            parameters: "244M"
        ),
        WhisperModel(
            id: "large-v3-turbo",
            name: "Whisper Large",
            repoId: "ggerganov/whisper.cpp",
            filename: "ggml-large-v3-turbo-q5_0.bin",
            description: String(localized: "Best overall accuracy, multilingual support."),
            expectedSize: 574_041_195,
            expectedSHA256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
            weight: "547 MB",
            languages: "Multilingual",
            accuracy: 0.95,
            speed: 0.8,
            company: "OpenAI",
            parameters: "1.55B"
        )
    ]
    
    struct MLXModel: Identifiable, Equatable, ModelMetadata {
        let id: String
        let family: String
        let name: String
        let repoId: String
        let description: String
        let weight: String
        let languages: String
        let accuracy: Double
        let speed: Double
        let company: String
        let parameters: String?
        
        var supportedLanguagesList: [String] {
            if languages == "English" { return ["English (English)"] }
            if family == "SenseVoice" { return ["English (English)", "Chinese (中文)", "Japanese (日本語)", "Korean (한국어)", "Cantonese (粵語)"] }
            return ModelManager.whisperLanguageList
        }
    }

    let availableMLXModels: [MLXModel] = [
        MLXModel(
            id: "sensevoice-small",
            family: "SenseVoice",
            name: "SenseVoice Small",
            repoId: "mlx-community/SenseVoiceSmall",
            description: String(localized: "Extremely fast, excellent multilingual support and accent recognition."),
            weight: "~1 GB",
            languages: String(localized: "Multilingual (EN, ZH, JA, KO, YUE)"),
            accuracy: 0.85,
            speed: 0.95,
            company: "Alibaba",
            parameters: "~50M"
        ),
        MLXModel(
            id: "moonshine-tiny",
            family: "Moonshine",
            name: "Moonshine Tiny",
            repoId: "UsefulSensors/moonshine-tiny",
            description: String(localized: "Very small and fast, optimized for resource-constrained environments."),
            weight: "~110 MB",
            languages: String(localized: "English"),
            accuracy: 0.6,
            speed: 1.0,
            company: "UsefulSensors",
            parameters: "27M"
        ),
        MLXModel(
            id: "moonshine-base",
            family: "Moonshine",
            name: "Moonshine Base",
            repoId: "UsefulSensors/moonshine-base",
            description: String(localized: "Balanced accuracy and speed."),
            weight: "~250 MB",
            languages: String(localized: "English"),
            accuracy: 0.75,
            speed: 0.9,
            company: "UsefulSensors",
            parameters: "85M"
        ),
        MLXModel(
            id: "parakeet-0.6b",
            family: "Parakeet",
            name: "Parakeet",
            repoId: "mlx-community/parakeet-tdt-0.6b-v3",
            description: String(localized: "High accuracy model from NVIDIA NeMo."),
            weight: "~2.5 GB",
            languages: String(localized: "English"),
            accuracy: 0.85,
            speed: 0.7,
            company: "NVIDIA",
            parameters: "0.6B"
        ),
        MLXModel(
            id: "qwen3-asr-1.7b",
            family: "Qwen3",
            name: "Qwen3 ASR",
            repoId: "mlx-community/Qwen3-ASR-1.7B-4bit",
            description: String(localized: "Large and powerful ASR model for advanced transcription."),
            weight: "~1.6 GB",
            languages: String(localized: "Multilingual"),
            accuracy: 0.95,
            speed: 0.5,
            company: "Alibaba",
            parameters: "1.7B"
        ),

        MLXModel(
            id: "canary-1b",
            family: "Canary",
            name: "Canary 1B",
            repoId: "qfuxa/canary-mlx",
            description: String(localized: "High precision end-to-end model from NVIDIA. Natural formatting and punctuation."),
            weight: "~3.92 GB",
            languages: String(localized: "Multilingual (EN, DE, ES, FR)"),
            accuracy: 0.96,
            speed: 0.7,
            company: "NVIDIA",
            parameters: "1.0B"
        ),
        MLXModel(
            id: "nemotron-asr",
            family: "Nemotron",
            name: "Nemotron ASR",
            repoId: "mlx-community/nemotron-3.5-asr-streaming-0.6b",
            description: String(localized: "Fast and highly accurate transcription model from NVIDIA."),
            weight: "~1.2 GB",
            languages: String(localized: "Multilingual"),
            accuracy: 0.92,
            speed: 0.9,
            company: "NVIDIA",
            parameters: "0.6B"
        ),
        MLXModel(
            id: "granite-speech",
            family: "Granite",
            name: "Granite Speech",
            repoId: "mlx-community/granite-speech-4.1-2b-nar-mlx",
            description: String(localized: "Enterprise-focused speech model. Reliable and clear transcriptions."),
            weight: "~4.5 GB",
            languages: String(localized: "English"),
            accuracy: 0.88,
            speed: 0.85,
            company: "IBM",
            parameters: "2B"
        ),
        MLXModel(
            id: "firered-asr2",
            family: "FireRed",
            name: "FireRed ASR2",
            repoId: "FireRedTeam/FireRedASR-AED-L",
            description: String(localized: "High-performance ASR system capable of accurately transcribing diverse speech patterns."),
            weight: "~4.6 GB",
            languages: String(localized: "Multilingual"),
            accuracy: 0.90,
            speed: 0.8,
            company: "FireRedTeam",
            parameters: "Unknown"
        ),
        MLXModel(
            id: "cohere-transcribe",
            family: "Cohere",
            name: "Cohere Transcribe",
            repoId: "aufklarer/Cohere-Transcribe-2B-MLX-5bit",
            description: String(localized: "Business-oriented model designed to handle specialized terminology and complex phrasing."),
            weight: "~1.8 GB",
            languages: String(localized: "Multilingual"),
            accuracy: 0.93,
            speed: 0.75,
            company: "Cohere",
            parameters: "2B"
        )
    ]

    @Published var selectedWhisperModelId: String {
        didSet {
            UserDefaults.standard.set(selectedWhisperModelId, forKey: "selectedWhisperModelId")
            NotificationCenter.default.post(name: Notification.Name("ReleaseWhisperContext"), object: nil)
        }
    }

    private var gemmaDownloadTask: Task<Void, Never>?
    private var activeWhisperDownloader: WhisperDownloader?
    private var activeWhisperModelId: String?
    @Published var activeWhisperDownloadText: String?
    
    private var activeGemmaDownloader: GemmaDownloader?
    @Published var activeGemmaDownloadText: String?
    
    private var activeMLXDownloaders: [String: MLXModelDownloader] = [:]
    @Published var activeMLXDownloadTexts: [String: String] = [:]

    
    var whisperModelURL: URL {
        return urlForWhisperModel(id: selectedWhisperModelId) ?? urlForWhisperModel(id: "large-v3-turbo")!
    }

    func urlForWhisperModel(id: String) -> URL? {
        guard let model = availableWhisperModels.first(where: { $0.id == id }) else { return nil }
        let api = HubApi(downloadBase: modelsDirectory, cache: nil, useBackgroundSession: false)
        return api.localRepoLocation(Hub.Repo(id: model.repoId)).appendingPathComponent(model.filename)
    }
    private init() {
        self.selectedWhisperModelId = UserDefaults.standard.string(forKey: "selectedWhisperModelId") ?? "large-v3-turbo"
        self.selectedMLXModelId = UserDefaults.standard.string(forKey: "selectedMLXModelId")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = appSupport.appendingPathComponent("Sonor").appendingPathComponent("Models")
        createModelsDirectoryIfNeeded()
        checkInitialStates()
        checkMLXInitialStates()
        
        speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDownloadSpeeds()
            }
        }
        RunLoop.main.add(speedTimer!, forMode: .common)
    }
    
    private func updateDownloadSpeeds() {
        let now = Date()
        
        // Update MLX stats
        var updatedMLXStats = self.mlxDownloadStats
        for (modelId, stats) in updatedMLXStats {
            let isDownloading = (self.mlxStates[modelId]?.isDownloading == true)
            if !isDownloading {
                if stats.speedBytesPerSecond > 0 {
                    updatedMLXStats[modelId]?.speedBytesPerSecond = 0
                    updatedMLXStats[modelId]?.speedHistory.append(0)
                }
                continue
            }
            let currentBytes = stats.downloadedBytes
            var speed = 0.0
            if let tracker = self.downloadBytesTracker[modelId] {
                let timeDiff = now.timeIntervalSince(tracker.date)
                if timeDiff > 0 {
                    speed = Double(currentBytes - tracker.bytes) / timeDiff
                }
            }
            if speed < 0 { speed = 0 }
            updatedMLXStats[modelId]?.speedBytesPerSecond = speed
            updatedMLXStats[modelId]?.speedHistory.append(speed)
            if (updatedMLXStats[modelId]?.speedHistory.count ?? 0) > 60 {
                updatedMLXStats[modelId]?.speedHistory.removeFirst()
            }
            self.downloadBytesTracker[modelId] = (currentBytes, now)
        }
        self.mlxDownloadStats = updatedMLXStats
        
        // Update Whisper stats
        var updatedWhisperStats = self.whisperDownloadStats
        for (modelId, stats) in updatedWhisperStats {
            let isDownloading = (self.whisperStates[modelId]?.isDownloading == true)
            if !isDownloading {
                if stats.speedBytesPerSecond > 0 {
                    updatedWhisperStats[modelId]?.speedBytesPerSecond = 0
                    updatedWhisperStats[modelId]?.speedHistory.append(0)
                }
                continue
            }
            let currentBytes = stats.downloadedBytes
            var speed = 0.0
            if let tracker = self.downloadBytesTracker[modelId] {
                let timeDiff = now.timeIntervalSince(tracker.date)
                if timeDiff > 0 {
                    speed = Double(currentBytes - tracker.bytes) / timeDiff
                }
            }
            if speed < 0 { speed = 0 }
            updatedWhisperStats[modelId]?.speedBytesPerSecond = speed
            updatedWhisperStats[modelId]?.speedHistory.append(speed)
            if (updatedWhisperStats[modelId]?.speedHistory.count ?? 0) > 60 {
                updatedWhisperStats[modelId]?.speedHistory.removeFirst()
            }
            self.downloadBytesTracker[modelId] = (currentBytes, now)
        }
        self.whisperDownloadStats = updatedWhisperStats
    }
    private func createModelsDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                // Ignore creation errors
            }
        }
    }
    /// Validates the existence and integrity of models on app startup.
    /// Uses SHA256 checksums to verify that downloaded models aren't corrupted.
    func checkInitialStates() {
        for model in availableWhisperModels {
            guard let url = urlForWhisperModel(id: model.id) else { continue }
            let whisperPath = url.path
            let whisperIncompletePath = whisperPath + ".incomplete"
            let whisperExists = FileManager.default.fileExists(atPath: whisperPath)
            let whisperIncompleteExists = FileManager.default.fileExists(atPath: whisperIncompletePath)
            
            let expectedSizeInBytes = model.expectedSize
            let expectedSize: Double = Double(expectedSizeInBytes)
            
            if whisperExists {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: whisperPath),
                   let size = attributes[.size] as? Int64 {
                    if size >= expectedSizeInBytes - 1000 {
                        if let expectedSHA256 = model.expectedSHA256 {
                            Task.detached {
                                if let fileData = try? Data(contentsOf: URL(fileURLWithPath: whisperPath), options: .mappedIfSafe) {
                                    let hash = CryptoKit.SHA256.hash(data: fileData)
                                    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
                                    await MainActor.run {
                                        if hashString != expectedSHA256 {
                                            try? FileManager.default.removeItem(atPath: whisperPath)
                                            self.whisperStates[model.id] = .notDownloaded
                                        }
                                    }
                                }
                            }
                        }
                        whisperStates[model.id] = .downloaded
                    } else {
                        try? FileManager.default.removeItem(atPath: whisperPath)
                        whisperStates[model.id] = .notDownloaded
                    }
                } else {
                    whisperStates[model.id] = .downloaded
                }
            } else if whisperIncompleteExists {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: whisperIncompletePath),
                   let size = attributes[.size] as? Int64 {
                    let progress = min(Double(size) / expectedSize, 0.99)
                    whisperStates[model.id] = .paused(progress: progress)
                } else {
                    whisperStates[model.id] = .paused(progress: 0.0)
                }
            } else {
                whisperStates[model.id] = .notDownloaded
            }
        }
        
        gemmaState = checkGemmaState(repoId: gemmaModelId, totalKey: "GemmaTotalExpectedBytes", downloadedKey: "GemmaTotalDownloadedBytes", defaultThreshold: 2_000_000_000, maxExpectedSize: 3_000_000_000.0)
    }

    func checkMLXInitialStates() {
        for model in availableMLXModels {
            let api = HubApi(downloadBase: modelsDirectory, cache: nil, useBackgroundSession: false)
            let repo = Hub.Repo(id: model.repoId)
            let dir = api.localRepoLocation(repo)
            
            if FileManager.default.fileExists(atPath: dir.path),
               let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
               !files.isEmpty {
                
                let hasIncomplete = files.contains(where: { $0.hasSuffix(".incomplete") })
                if hasIncomplete {
                    var downloadedBytes: Int64 = 0
                    for file in files {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(file).path),
                           let size = attrs[.size] as? Int64 {
                            downloadedBytes += size
                        }
                    }
                    var totalBytes: Int64 = 0
                    if let storedTotal = UserDefaults.standard.value(forKey: "MLXTotalExpectedBytes_\(model.id)") as? Int64, storedTotal > 0 {
                        totalBytes = storedTotal
                    } else {
                        let w = model.weight.replacingOccurrences(of: "~", with: "").trimmingCharacters(in: .whitespaces)
                        if w.hasSuffix("GB"), let val = Double(w.dropLast(2).trimmingCharacters(in: .whitespaces)) {
                            totalBytes = Int64(val * 1_000_000_000)
                        } else if w.hasSuffix("MB"), let val = Double(w.dropLast(2).trimmingCharacters(in: .whitespaces)) {
                            totalBytes = Int64(val * 1_000_000)
                        } else {
                            totalBytes = downloadedBytes * 2
                        }
                    }
                    
                    if totalBytes > 0 {
                        let progress = min(Double(downloadedBytes) / Double(totalBytes), 0.99)
                        mlxStates[model.id] = .paused(progress: progress)
                        
                        if mlxDownloadStats[model.id] == nil {
                            mlxDownloadStats[model.id] = DownloadStats()
                        }
                        mlxDownloadStats[model.id]?.downloadedBytes = downloadedBytes
                        mlxDownloadStats[model.id]?.totalBytes = totalBytes
                        let dl = formatBytes(downloadedBytes)
                        let tot = formatBytes(totalBytes)
                        activeMLXDownloadTexts[model.id] = "\(dl) / \(tot)"
                    } else {
                        mlxStates[model.id] = .paused(progress: 0.0)
                    }
                } else {
                    mlxStates[model.id] = .downloaded
                }
            } else {
                mlxStates[model.id] = .notDownloaded
            }
        }
    }

    func downloadMLXModel(modelId: String) {
        guard let model = availableMLXModels.first(where: { $0.id == modelId }) else { return }
        mlxStates[modelId] = .downloading(progress: 0.0)
        let repoId = model.repoId
        
        let downloader = MLXModelDownloader(modelsDirectory: modelsDirectory, repoId: repoId)
        activeMLXDownloaders[modelId] = downloader
        
        downloader.start { [weak self] fraction, downloaded, total in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.activeMLXDownloaders[modelId] != nil else { return }
                
                UserDefaults.standard.set(total, forKey: "MLXTotalExpectedBytes_\(modelId)")
                
                if self.mlxDownloadStats[modelId] == nil {
                    self.mlxDownloadStats[modelId] = DownloadStats()
                }
                self.mlxDownloadStats[modelId]?.downloadedBytes = downloaded
                self.mlxDownloadStats[modelId]?.totalBytes = total

                if total > 0 {
                    let dl = self.formatBytes(downloaded)
                    let tot = self.formatBytes(total)
                    self.activeMLXDownloadTexts[modelId] = "\(dl) / \(tot)"
                } else {
                    self.activeMLXDownloadTexts[modelId] = nil
                }
                
                if case .downloading(let currentProgress) = self.mlxStates[modelId], currentProgress > fraction && fraction < 0.1 {
                    return
                }
                self.mlxStates[modelId] = .downloading(progress: fraction)
            }
        } completion: { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                let wasCancelled = self.activeMLXDownloaders[modelId] == nil
                let intendedState = self.mlxStates[modelId]
                
                self.activeMLXDownloaders[modelId] = nil
                self.activeMLXDownloadTexts[modelId] = nil
                
                if wasCancelled {
                    if case .notDownloaded = intendedState {
                        let repo = Hub.Repo(id: model.repoId)
                        let api = HubApi(downloadBase: self.modelsDirectory, cache: nil, useBackgroundSession: false)
                        let dir = api.localRepoLocation(repo)
                        try? FileManager.default.removeItem(at: dir)
                    }
                    return
                }
                
                switch result {
                case .success:
                    self.mlxStates[modelId] = .downloaded
                case .failure(let error):
                    self.downloadError = error.localizedDescription
                    self.showDownloadErrorModal = true
                    if case .downloading(let p) = self.mlxStates[modelId] {
                        self.mlxStates[modelId] = .paused(progress: p)
                    } else {
                        self.checkMLXInitialStates()
                    }
                }
            }
        }
    }


    func pauseMLXDownload(modelId: String) {
        if let downloader = activeMLXDownloaders[modelId] {
            downloader.cancel()
            activeMLXDownloaders[modelId] = nil
            // activeMLXDownloadTexts[modelId] = nil // keeping it so user sees paused size
        }
        if case .downloading(let progress) = mlxStates[modelId] {
            mlxStates[modelId] = .paused(progress: progress)
        } else {
            mlxStates[modelId] = .paused(progress: 0.0)
        }
    }

    func cancelMLXDownload(modelId: String) {
        if let downloader = activeMLXDownloaders[modelId] {
            downloader.cancel()
            activeMLXDownloaders[modelId] = nil
            activeMLXDownloadTexts[modelId] = nil
        }
        mlxStates[modelId] = .notDownloaded
        let repo = Hub.Repo(id: availableMLXModels.first(where: { $0.id == modelId })!.repoId)
        let api = HubApi(downloadBase: modelsDirectory, cache: nil, useBackgroundSession: false)
        let dir = api.localRepoLocation(repo)
        try? FileManager.default.removeItem(at: dir)
    }

    func uninstallMLXModel(modelId: String) {
        cancelMLXDownload(modelId: modelId)
    }

    private func checkGemmaState(repoId: String, totalKey: String, downloadedKey: String, defaultThreshold: Int64, maxExpectedSize: Double) -> DownloadState {
        let api = HubApi(downloadBase: modelsDirectory, cache: nil, useBackgroundSession: false)
        let repo = Hub.Repo(id: repoId)
        let gemmaDir = api.localRepoLocation(repo)
        let gemmaExists = FileManager.default.fileExists(atPath: gemmaDir.path)
        if gemmaExists {
            let savedTotal = UserDefaults.standard.object(forKey: totalKey) as? Int64
            let savedDownloaded = UserDefaults.standard.object(forKey: downloadedKey) as? Int64
            if let total = savedTotal, let downloaded = savedDownloaded, total > 0 {
                if downloaded >= total {
                    return .downloaded
                } else {
                    let progress = min(Double(downloaded) / Double(total), 0.99)
                    return .paused(progress: progress)
                }
            } else {
                if let files = try? FileManager.default.contentsOfDirectory(atPath: gemmaDir.path), !files.isEmpty {
                    var totalSize: Int64 = 0
                    for file in files {
                        let filePath = gemmaDir.appendingPathComponent(file).path
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                           let s = attrs[.size] as? Int64 {
                            totalSize += s
                        }
                    }
                    if totalSize > defaultThreshold {
                        return .downloaded
                    } else {
                        let progress = min(Double(totalSize) / maxExpectedSize, 0.99)
                        return .paused(progress: progress)
                    }
                } else {
                    return .notDownloaded
                }
            }
        } else {
            return .notDownloaded
        }
    }
    /// Initiates or resumes the download of the Whisper model.
    /// Resumes from an `.incomplete` file if a previous download was paused or interrupted.
    func downloadWhisper(modelId: String) {
        guard let model = availableWhisperModels.first(where: { $0.id == modelId }),
              let modelURL = urlForWhisperModel(id: modelId) else { return }
        
        if case .downloading = whisperStates[modelId] { return }
        if case .downloaded = whisperStates[modelId] { return }
        var initialWhisperProgress: Double = 0.0
        let whisperIncompletePath = modelURL.path + ".incomplete"
        if FileManager.default.fileExists(atPath: whisperIncompletePath),
           let attributes = try? FileManager.default.attributesOfItem(atPath: whisperIncompletePath),
           let size = attributes[.size] as? Int64 {
            let expectedSize = Double(model.expectedSize)
            initialWhisperProgress = min(Double(size) / expectedSize, 0.99)
        }
        whisperStates[modelId] = .downloading(progress: initialWhisperProgress)
        activeWhisperDownloader?.cancel()
        
        if let activeId = activeWhisperModelId {
            pauseWhisperDownload(modelId: activeId)
        }
        
        let downloader = WhisperDownloader(destinationURL: modelURL)
        self.activeWhisperDownloader = downloader
        self.activeWhisperModelId = modelId
        let whisperDownloadURL = URL(string: "https://huggingface.co/\(model.repoId)/resolve/main/\(model.filename)")!

        downloader.start(from: whisperDownloadURL) { [weak self, weak downloader] fraction, downloaded, total in
            Task { @MainActor in
                guard let self = self, self.activeWhisperDownloader === downloader else { return }
                
                if self.whisperDownloadStats[modelId] == nil {
                    self.whisperDownloadStats[modelId] = DownloadStats()
                }
                self.whisperDownloadStats[modelId]?.downloadedBytes = downloaded
                self.whisperDownloadStats[modelId]?.totalBytes = total

                if total > 0 {
                    let dl = self.formatBytes(downloaded)
                    let tot = self.formatBytes(total)
                    self.activeWhisperDownloadText = "\(dl) / \(tot)"
                } else {
                    self.activeWhisperDownloadText = nil
                }
                
                if case .downloading(let currentProgress) = self.whisperStates[modelId], currentProgress > fraction && fraction < 0.1 {
                    return
                }
                self.whisperStates[modelId] = .downloading(progress: fraction)
            }
        } completion: { [weak self, weak downloader] result in
            Task { @MainActor in
                guard let self = self, self.activeWhisperDownloader === downloader else { return }
                self.activeWhisperDownloader = nil
                self.activeWhisperModelId = nil
                self.activeWhisperDownloadText = nil
                switch result {
                case .success:
                    self.whisperStates[modelId] = .downloaded
                case .failure(let error):
                    let nsError = error as NSError
                    if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                        var finalProgress = 0.0
                        if finalProgress == 0.0 {
                            let incompleteURL = modelURL.deletingLastPathComponent().appendingPathComponent(modelURL.lastPathComponent + ".incomplete")
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: incompleteURL.path),
                               let size = attrs[.size] as? Int64 {
                                finalProgress = min(Double(size) / Double(model.expectedSize), 0.99)
                            }
                        }
                        self.downloadError = error.localizedDescription
                        self.showDownloadErrorModal = true
                        self.whisperStates[modelId] = .paused(progress: finalProgress)
                    }
                }
            }
        }
    }
    
    func pauseWhisperDownload(modelId: String) {
        if activeWhisperModelId == modelId {
            activeWhisperDownloader?.cancel()
            activeWhisperDownloader = nil
            activeWhisperModelId = nil
        }
        guard let model = availableWhisperModels.first(where: { $0.id == modelId }),
              let modelURL = urlForWhisperModel(id: modelId) else { return }
              
        var finalProgress = 0.0
        let incompleteURL = modelURL.deletingLastPathComponent().appendingPathComponent(modelURL.lastPathComponent + ".incomplete")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: incompleteURL.path),
           let size = attrs[.size] as? Int64 {
            finalProgress = min(Double(size) / Double(model.expectedSize), 0.99)
        }
        whisperStates[modelId] = .paused(progress: finalProgress)
    }

    func cancelWhisperDownload(modelId: String) {
        if activeWhisperModelId == modelId {
            activeWhisperDownloader?.cancel()
            activeWhisperDownloader = nil
            activeWhisperModelId = nil
            activeWhisperDownloadText = nil
        }
        whisperStates[modelId] = .notDownloaded
        if let url = urlForWhisperModel(id: modelId) {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + ".incomplete")
        }
    }
    
    func pauseAllDownloads() {
        if let activeId = activeWhisperModelId {
            pauseWhisperDownload(modelId: activeId)
        }
        if case .downloading = gemmaState {
            pauseGemmaDownload()
        }
    }
    
    func uninstallWhisper(modelId: String) {
        cancelWhisperDownload(modelId: modelId)
        
        guard let _ = availableWhisperModels.first(where: { $0.id == modelId }),
              let modelURL = urlForWhisperModel(id: modelId) else { return }
              
        if selectedWhisperModelId == modelId {
            NotificationCenter.default.post(name: Notification.Name("ReleaseWhisperContext"), object: nil)
        }
        URLCache.shared.removeAllCachedResponses()
        do {
            if FileManager.default.fileExists(atPath: modelURL.path) {
                try FileManager.default.removeItem(at: modelURL)
            }
        } catch {
            // Ignore deletion errors
        }
        whisperStates[modelId] = .notDownloaded
    }
    /// Initiates or resumes the download of the Gemma LLM model from Hugging Face.
    func downloadGemma() {
        if case .downloading = gemmaState { return }
        if case .downloaded = gemmaState { return }
        var initialProgress: Double = 0.0
        if let savedTotal = UserDefaults.standard.object(forKey: "GemmaTotalExpectedBytes") as? Int64,
           let savedDownloaded = UserDefaults.standard.object(forKey: "GemmaTotalDownloadedBytes") as? Int64, savedTotal > 0 {
            initialProgress = min(Double(savedDownloaded) / Double(savedTotal), 0.99)
        }
        gemmaState = .downloading(progress: initialProgress)
        activeGemmaDownloader?.cancel()
        let downloader = GemmaDownloader(modelsDirectory: modelsDirectory, repoId: gemmaModelId)
        self.activeGemmaDownloader = downloader
        var lastEmittedProgress: Double = initialProgress
        var lastEmissionTime = Date()
        downloader.start { [weak self, weak downloader] progress in
            guard let self = self, let downloader = downloader else { return }
            let clampedProgress = max(progress, initialProgress)
            let now = Date()
            let diff = clampedProgress - lastEmittedProgress
            let timeDiff = now.timeIntervalSince(lastEmissionTime)
            if diff >= 0.01 || (diff > 0 && timeDiff >= 0.1) || clampedProgress >= 1.0 {
                lastEmittedProgress = clampedProgress
                lastEmissionTime = now
                DispatchQueue.main.async {
                    guard self.activeGemmaDownloader === downloader else { return }
                    self.gemmaState = .downloading(progress: clampedProgress)
                }
            }
        } completion: { [weak self, weak downloader] result in
            guard let self = self, let downloader = downloader else { return }
            DispatchQueue.main.async {
                guard self.activeGemmaDownloader === downloader else { return }
                self.activeGemmaDownloader = nil
                switch result {
                case .success:
                    self.gemmaState = .downloaded
                case .failure(let error):
                    let nsError = error as NSError
                    if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                        var finalProgress = lastEmittedProgress >= 0 ? lastEmittedProgress : 0.0
                        if finalProgress == 0.0 {
                            if let savedTotal = UserDefaults.standard.object(forKey: "GemmaTotalExpectedBytes") as? Int64,
                               let savedDownloaded = UserDefaults.standard.object(forKey: "GemmaTotalDownloadedBytes") as? Int64,
                               savedTotal > 0 {
                                finalProgress = min(Double(savedDownloaded) / Double(savedTotal), 0.99)
                            }
                        }
                        self.downloadError = error.localizedDescription
                        self.showDownloadErrorModal = true
                        self.gemmaState = .paused(progress: finalProgress)
                    }
                }
            }
        }
    }
    func pauseGemmaDownload() {
        activeGemmaDownloader?.cancel()
        activeGemmaDownloader = nil
        let savedTotal = UserDefaults.standard.object(forKey: "GemmaTotalExpectedBytes") as? Int64
        let savedDownloaded = UserDefaults.standard.object(forKey: "GemmaTotalDownloadedBytes") as? Int64
        var finalProgress: Double = 0.0
        if let total = savedTotal, let downloaded = savedDownloaded, total > 0 {
            finalProgress = min(Double(downloaded) / Double(total), 0.99)
        }
        gemmaState = .paused(progress: finalProgress)
    }
    func cancelGemmaDownload() {
        activeGemmaDownloader?.cancel()
        activeGemmaDownloader = nil
        gemmaState = .notDownloaded
        UserDefaults.standard.removeObject(forKey: "GemmaTotalExpectedBytes")
        UserDefaults.standard.removeObject(forKey: "GemmaTotalDownloadedBytes")
        cleanupGemmaFiles()
    }
    private func cleanupGemmaFiles() {
        LLMManager.shared.releaseModel()
        URLCache.shared.removeAllCachedResponses()
        let api = HubApi(downloadBase: modelsDirectory, cache: nil, useBackgroundSession: false)
        let repoDir = api.localRepoLocation(Hub.Repo(id: gemmaModelId))
        do {
            if FileManager.default.fileExists(atPath: repoDir.path) {
                try FileManager.default.removeItem(at: repoDir)
            }
        } catch {
            // Ignore deletion errors
        }
        let mlxDir = modelsDirectory.appendingPathComponent("models").appendingPathComponent("mlx-community")
        if FileManager.default.fileExists(atPath: mlxDir.path) {
            try? FileManager.default.removeItem(at: mlxDir)
        }
        cleanHubCache(repoName: "models--mlx-community--gemma-3-4b-it-qat-4bit")
        cleanDefaultDownloadBase(repoPath: "models/mlx-community/gemma-3-4b-it-qat-4bit")
        let tmpDir = FileManager.default.temporaryDirectory
        if let tmpFiles = try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil) {
            for file in tmpFiles {
                if file.lastPathComponent.hasPrefix("CFNetworkDownload_") && file.lastPathComponent.hasSuffix(".tmp") {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
    func uninstallGemma() {
        cleanupGemmaFiles()
        gemmaState = .notDownloaded
    }



    private func aggressivelyDeleteDirectory(at url: URL, retries: Int = 10, delay: TimeInterval = 0.1) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.aggressivelyDeleteDirectory(at: url, retries: retries - 1, delay: delay)
                }
            }
        }
    }
    /// Deeply cleans Hugging Face hub caches to free up disk space when models are uninstalled.
    /// Hugging Face library aggressively caches files across multiple directories.
    private func cleanHubCache(repoName: String) {
        let fm = FileManager.default
        var cacheRoots: [URL] = []
        let homeDir = URL(fileURLWithPath: NSHomeDirectory())
        cacheRoots.append(homeDir.appendingPathComponent(".cache/huggingface/hub"))
        if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheRoots.append(cachesDir.appendingPathComponent("huggingface/hub"))
        }
        if let envCache = ProcessInfo.processInfo.environment["HF_HUB_CACHE"] {
            let expanded = NSString(string: envCache).expandingTildeInPath
            cacheRoots.append(URL(fileURLWithPath: expanded))
        }
        if let hfHome = ProcessInfo.processInfo.environment["HF_HOME"] {
            let expanded = NSString(string: hfHome).expandingTildeInPath
            cacheRoots.append(URL(fileURLWithPath: expanded).appendingPathComponent("hub"))
        }
        let hubCacheDefault = HubCache.default.cacheDirectory
        cacheRoots.append(hubCacheDefault)
        let uniqueRoots = Array(Set(cacheRoots.map { $0.standardizedFileURL.path }))
        for rootPath in uniqueRoots {
            let rootURL = URL(fileURLWithPath: rootPath)
            let repoCache = rootURL.appendingPathComponent(repoName)
            if fm.fileExists(atPath: repoCache.path) {
                self.aggressivelyDeleteDirectory(at: repoCache)
            }
            let lockDir = rootURL.appendingPathComponent(".locks").appendingPathComponent(repoName)
            if fm.fileExists(atPath: lockDir.path) {
                self.aggressivelyDeleteDirectory(at: lockDir)
            }
            let metadataDir = rootURL.appendingPathComponent(".metadata").appendingPathComponent(repoName)
            if fm.fileExists(atPath: metadataDir.path) {
                self.aggressivelyDeleteDirectory(at: metadataDir)
            }
        }
    }
    private func cleanDefaultDownloadBase(repoPath: String) {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let defaultBase = documents.appendingPathComponent("huggingface")
        let repoDir = defaultBase.appendingPathComponent(repoPath)
        if fm.fileExists(atPath: repoDir.path) {
            self.aggressivelyDeleteDirectory(at: repoDir)
        }
        let namespaceDir = repoDir.deletingLastPathComponent()
        if fm.fileExists(atPath: namespaceDir.path) {
            let contents = (try? fm.contentsOfDirectory(atPath: namespaceDir.path)) ?? []
            if contents.isEmpty || contents == [".DS_Store"] {
                self.aggressivelyDeleteDirectory(at: namespaceDir)
            }
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}


final class WhisperDownloader: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var destinationURL: URL
    private var incompleteURL: URL
    private var progressCallback: ((Double, Int64, Int64) -> Void)?
    private var completionCallback: ((Result<URL, Error>) -> Void)?
    private var expectedLength: Int64 = 0
    private var downloadedBytes: Int64 = 0
    private var isCancelled = false
    private var firstFailureTime: Date?
    private var currentDownloadURL: URL?
    
    init(destinationURL: URL) {
        self.destinationURL = destinationURL
        self.incompleteURL = destinationURL.deletingLastPathComponent().appendingPathComponent(destinationURL.lastPathComponent + ".incomplete")
        super.init()
    }
    func start(from url: URL, progress: @escaping (Double, Int64, Int64) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        self.currentDownloadURL = url
        self.progressCallback = progress
        self.completionCallback = completion
        if isCancelled { return }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }
        var existingSize: Int64 = 0
        if fileManager.fileExists(atPath: incompleteURL.path) {
            if let attrs = try? fileManager.attributesOfItem(atPath: incompleteURL.path),
               let size = attrs[.size] as? Int64 {
                existingSize = size
            }
        } else {
            fileManager.createFile(atPath: incompleteURL.path, contents: nil)
        }
        self.downloadedBytes = existingSize
        do {
            let handle = try FileHandle(forWritingTo: incompleteURL)
            try handle.seek(toOffset: UInt64(existingSize))
            self.fileHandle = handle
        } catch {
            completion(.failure(error))
            return
        }
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }
    func cancel() {
        isCancelled = true
        task?.cancel()
        cleanup()
    }
    private func cleanup() {
        try? fileHandle?.close()
        fileHandle = nil
        session?.invalidateAndCancel()
        session = nil
        task = nil
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var redirectedRequest = newRequest
        if let originalRequest = task.originalRequest,
           let rangeHeader = originalRequest.value(forHTTPHeaderField: "Range") {
            redirectedRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        completionHandler(redirectedRequest)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if statusCode == 200 && downloadedBytes > 0 {
                try? fileHandle?.truncate(atOffset: 0)
                downloadedBytes = 0
            }
            if statusCode == 416 {
                try? fileHandle?.truncate(atOffset: 0)
                downloadedBytes = 0
            } else if !(200...299).contains(statusCode) {
                completionCallback?(.failure(NSError(domain: "WhisperDownloader", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Bad status code: \(statusCode)"])))
                completionHandler(.cancel)
                cleanup()
                return
            }
            let contentLength = httpResponse.expectedContentLength
            if contentLength > 0 {
                expectedLength = contentLength + downloadedBytes
            }
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if isCancelled { return }
        fileHandle?.write(data)
        downloadedBytes += Int64(data.count)
        if expectedLength > 0 {
            let fraction = Double(downloadedBytes) / Double(expectedLength)
            progressCallback?(fraction, downloadedBytes, expectedLength)
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        cleanup()
        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            if nsError.domain == NSURLErrorDomain, let url = currentDownloadURL {
                let now = Date()
                if firstFailureTime == nil {
                    firstFailureTime = now
                }
                if now.timeIntervalSince(firstFailureTime!) <= 5.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if !self.isCancelled {
                            self.start(from: url, progress: self.progressCallback!, completion: self.completionCallback!)
                        }
                    }
                    return
                }
            }
            completionCallback?(.failure(error))
        } else {
            firstFailureTime = nil
            do {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: incompleteURL, to: destinationURL)
                completionCallback?(.success(destinationURL))
            } catch {
                completionCallback?(.failure(error))
            }
        }
    }
}

final class GemmaDownloader: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var activeTask: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var currentDestinationURL: URL?
    private var currentIncompleteURL: URL?
    private var progressCallback: ((Double) -> Void)?
    private var completionCallback: ((Result<Void, Error>) -> Void)?
    private let modelsDirectory: URL
    private let repoId: String
    private let api: HubApi
    private var fileList: [String] = []
    private var currentFileIndex: Int = 0
    private var totalExpectedBytes: Int64 = 0
    private var totalDownloadedBytes: Int64 = 0
    private var currentFileDownloadedBytes: Int64 = 0
private var currentFileExpectedBytes: Int64 = 0
    private let defaultsKeyTotalBytes: String
    private let defaultsKeyDownloadedBytes: String
    private var lastUserDefaultsSaveTime: Date = Date()
    private var isCancelled = false
    private var firstFailureTime: Date?
    
    init(modelsDirectory: URL, repoId: String, totalBytesKey: String = "GemmaTotalExpectedBytes", downloadedBytesKey: String = "GemmaTotalDownloadedBytes") {
        self.modelsDirectory = modelsDirectory
        self.repoId = repoId
        self.defaultsKeyTotalBytes = totalBytesKey
        self.defaultsKeyDownloadedBytes = downloadedBytesKey
        self.api = HubApi(downloadBase: modelsDirectory, cache: nil, useBackgroundSession: false)
        super.init()
    }
    func start(progress: @escaping (Double) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        self.progressCallback = progress
        self.completionCallback = completion
        Task {
            do {
                if fileList.isEmpty {
                    let globs = ["*.safetensors", "*.json", "*.jinja"]
                    let repo = Hub.Repo(id: repoId)
                    let filenames = try await api.getFilenames(from: repo, matching: globs)
                    self.fileList = filenames
                    var totalSize: Int64 = 0
                    for filename in filenames {
                        if let encodedPath = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                           let url = URL(string: "https://huggingface.co/\(repoId)/resolve/main/\(encodedPath)") {
                            if let metadata = try? await api.getFileMetadata(url: url) {
                                totalSize += Int64(metadata.size ?? 0)
                            }
                        }
                    }
                    self.totalExpectedBytes = totalSize
                    UserDefaults.standard.set(self.totalExpectedBytes, forKey: self.defaultsKeyTotalBytes)
                }
                await MainActor.run {
                    if self.isCancelled { return }
                    self.downloadNextFile()
                }
            } catch {
                if !self.isCancelled {
                    completion(.failure(error))
                }
            }
        }
    }
    private func downloadNextFile() {
        guard currentFileIndex < fileList.count else {
            UserDefaults.standard.removeObject(forKey: defaultsKeyDownloadedBytes)
            UserDefaults.standard.removeObject(forKey: defaultsKeyTotalBytes)
            completionCallback?(.success(()))
            return
        }
        let relativePath = fileList[currentFileIndex]
        var previousFilesDownloaded: Int64 = 0
        let repo = Hub.Repo(id: repoId)
        let destinationDir = api.localRepoLocation(repo)
        for i in 0..<currentFileIndex {
            let prevFile = fileList[i]
            let prevPath = destinationDir.appendingPathComponent(prevFile).path
            if let attrs = try? FileManager.default.attributesOfItem(atPath: prevPath),
               let s = attrs[.size] as? Int64 {
                previousFilesDownloaded += s
            }
        }
        self.totalDownloadedBytes = previousFilesDownloaded
        let destinationURL = destinationDir.appendingPathComponent(relativePath)
        self.currentDestinationURL = destinationURL
        self.currentIncompleteURL = destinationURL.deletingLastPathComponent().appendingPathComponent(destinationURL.lastPathComponent + ".incomplete")
        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            completionCallback?(.failure(error))
            return
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            currentFileIndex += 1
            downloadNextFile()
            return
        }
        var existingSize: Int64 = 0
        if FileManager.default.fileExists(atPath: currentIncompleteURL!.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: currentIncompleteURL!.path),
               let size = attrs[.size] as? Int64 {
                existingSize = size
            }
        } else {
            FileManager.default.createFile(atPath: currentIncompleteURL!.path, contents: nil)
        }
        self.currentFileDownloadedBytes = existingSize
        self.totalDownloadedBytes += existingSize
        do {
            let handle = try FileHandle(forWritingTo: currentIncompleteURL!)
            try handle.seek(toOffset: UInt64(existingSize))
            self.fileHandle = handle
        } catch {
            completionCallback?(.failure(error))
            return
        }
        guard let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/\(repoId)/resolve/main/\(encodedPath)") else {
            completionCallback?(.failure(NSError(domain: "GemmaDownloader", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL for \(relativePath)"])))
            return
        }
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request)
        self.activeTask = task
        if isCancelled {
            task.cancel()
            return
        }
        task.resume()
    }
    func cancel() {
        isCancelled = true
        activeTask?.cancel()
        if totalDownloadedBytes > 0 {
            UserDefaults.standard.set(totalDownloadedBytes, forKey: defaultsKeyDownloadedBytes)
        }
        cleanup()
    }
    private func cleanup() {
        try? fileHandle?.close()
        fileHandle = nil
        session?.invalidateAndCancel()
        session = nil
        activeTask = nil
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var redirectedRequest = newRequest
        if let originalRequest = task.originalRequest,
           let rangeHeader = originalRequest.value(forHTTPHeaderField: "Range") {
            redirectedRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        completionHandler(redirectedRequest)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if statusCode == 200 && currentFileDownloadedBytes > 0 {
                try? fileHandle?.truncate(atOffset: 0)
                totalDownloadedBytes -= currentFileDownloadedBytes
                currentFileDownloadedBytes = 0
            }
            if statusCode == 416 {
                try? fileHandle?.truncate(atOffset: 0)
                totalDownloadedBytes -= currentFileDownloadedBytes
                currentFileDownloadedBytes = 0
            } else if !(200...299).contains(statusCode) {
                completionCallback?(.failure(NSError(domain: "GemmaDownloader", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Bad status code: \(statusCode)"])))
                completionHandler(.cancel)
                cleanup()
                return
            }
            let contentLength = httpResponse.expectedContentLength
            if contentLength > 0 {
                currentFileExpectedBytes = contentLength + currentFileDownloadedBytes
            }
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if isCancelled { return }
        fileHandle?.write(data)
        currentFileDownloadedBytes += Int64(data.count)
        totalDownloadedBytes += Int64(data.count)
        if totalExpectedBytes > 0 {
            let fraction = Double(totalDownloadedBytes) / Double(totalExpectedBytes)
            progressCallback?(fraction)
            let now = Date()
            if now.timeIntervalSince(lastUserDefaultsSaveTime) > 0.5 {
                UserDefaults.standard.set(totalDownloadedBytes, forKey: defaultsKeyDownloadedBytes)
                lastUserDefaultsSaveTime = now
            }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        cleanup()
        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            if nsError.domain == NSURLErrorDomain {
                let now = Date()
                if firstFailureTime == nil {
                    firstFailureTime = now
                }
                if now.timeIntervalSince(firstFailureTime!) <= 5.0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if !self.isCancelled {
                            self.downloadNextFile()
                        }
                    }
                    return
                }
            }
            completionCallback?(.failure(error))
        } else {
            firstFailureTime = nil
            do {
                let fileManager = FileManager.default
                if let dest = currentDestinationURL, let inc = currentIncompleteURL {
                    if fileManager.fileExists(atPath: dest.path) {
                        try fileManager.removeItem(at: dest)
                    }
                    try fileManager.moveItem(at: inc, to: dest)
                }
                DispatchQueue.main.async {
                    if self.isCancelled { return }
                    self.currentFileIndex += 1
                    self.downloadNextFile()
                }
            } catch {
                completionCallback?(.failure(error))
            }
        }
    }
}
import Foundation
import Hub

final class MLXModelDownloader: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var activeTask: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var currentDestinationURL: URL?
    private var currentIncompleteURL: URL?
    private var progressCallback: ((Double, Int64, Int64) -> Void)?
    private var completionCallback: ((Result<Void, Error>) -> Void)?
    private let modelsDirectory: URL
    private let repoId: String
    private var fileList: [(path: String, size: Int64)] = []
    private var currentFileIndex: Int = 0
    private var totalExpectedBytes: Int64 = 0
    private var totalDownloadedBytes: Int64 = 0
    private var currentFileDownloadedBytes: Int64 = 0
    private var isCancelled = false
    private var firstFailureTime: Date?
    
    init(modelsDirectory: URL, repoId: String) {
        self.modelsDirectory = modelsDirectory
        self.repoId = repoId
        super.init()
    }
    
    func start(progress: @escaping (Double, Int64, Int64) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        self.progressCallback = progress
        self.completionCallback = completion
        Task {
            do {
                if fileList.isEmpty {
                    let treeUrl = URL(string: "https://huggingface.co/api/models/\(repoId)/tree/main?recursive=true")!
                    let (data, _) = try await URLSession.shared.data(from: treeUrl)
                    guard let files = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                        throw NSError(domain: "MLXDownloader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse repository tree"])
                    }
                    
                    let fileItems = files.filter { ($0["type"] as? String) == "file" }
                    var totalSize: Int64 = 0
                    for file in fileItems {
                        if let size = file["size"] as? Int64, let path = file["path"] as? String {
                            totalSize += size
                            self.fileList.append((path: path, size: size))
                        }
                    }
                    self.totalExpectedBytes = totalSize
                }
                await MainActor.run {
                    if self.isCancelled { return }
                    self.downloadNextFile()
                }
            } catch {
                if !self.isCancelled {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func downloadNextFile() {
        guard currentFileIndex < fileList.count else {
            completionCallback?(.success(()))
            return
        }
        
        let fileInfo = fileList[currentFileIndex]
        let relativePath = fileInfo.path
        
        var previousFilesDownloaded: Int64 = 0
        let repo = Hub.Repo(id: repoId)
        let api = HubApi(downloadBase: modelsDirectory, cache: nil, useBackgroundSession: false)
        let destinationDir = api.localRepoLocation(repo)
        
        for i in 0..<currentFileIndex {
            previousFilesDownloaded += fileList[i].size
        }
        self.totalDownloadedBytes = previousFilesDownloaded
        
        let destinationURL = destinationDir.appendingPathComponent(relativePath)
        self.currentDestinationURL = destinationURL
        self.currentIncompleteURL = destinationURL.deletingLastPathComponent().appendingPathComponent(destinationURL.lastPathComponent + ".incomplete")
        
        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            completionCallback?(.failure(error))
            return
        }
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
               let existingSize = attrs[.size] as? Int64, existingSize == fileInfo.size {
                currentFileIndex += 1
                downloadNextFile()
                return
            } else {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }
        
        var existingSize: Int64 = 0
        if FileManager.default.fileExists(atPath: currentIncompleteURL!.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: currentIncompleteURL!.path),
               let size = attrs[.size] as? Int64 {
                existingSize = size
            }
        } else {
            FileManager.default.createFile(atPath: currentIncompleteURL!.path, contents: nil)
        }
        
        self.currentFileDownloadedBytes = existingSize
        self.totalDownloadedBytes += existingSize
        
        do {
            let handle = try FileHandle(forWritingTo: currentIncompleteURL!)
            try handle.seek(toOffset: UInt64(existingSize))
            self.fileHandle = handle
        } catch {
            completionCallback?(.failure(error))
            return
        }
        
        guard let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/\(repoId)/resolve/main/\(encodedPath)") else {
            completionCallback?(.failure(NSError(domain: "MLXDownloader", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if existingSize > 0 {
            request.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }
        
        let task = session.dataTask(with: request)
        self.activeTask = task
        
        if isCancelled {
            task.cancel()
            return
        }
        task.resume()
    }
    
    func cancel() {
        isCancelled = true
        activeTask?.cancel()
        cleanup()
    }
    
    private func cleanup() {
        try? fileHandle?.close()
        fileHandle = nil
        session?.invalidateAndCancel()
        session = nil
        activeTask = nil
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var redirectedRequest = newRequest
        if let originalRequest = task.originalRequest,
           let rangeHeader = originalRequest.value(forHTTPHeaderField: "Range") {
            redirectedRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        completionHandler(redirectedRequest)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            if statusCode == 200 && currentFileDownloadedBytes > 0 {
                try? fileHandle?.truncate(atOffset: 0)
                totalDownloadedBytes -= currentFileDownloadedBytes
                currentFileDownloadedBytes = 0
            }
            if statusCode == 416 {
                try? fileHandle?.truncate(atOffset: 0)
                totalDownloadedBytes -= currentFileDownloadedBytes
                currentFileDownloadedBytes = 0
            } else if !(200...299).contains(statusCode) {
                completionCallback?(.failure(NSError(domain: "MLXDownloader", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Bad status code: \(statusCode)"])))
                completionHandler(.cancel)
                cleanup()
                return
            }
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if isCancelled { return }
        fileHandle?.write(data)
        currentFileDownloadedBytes += Int64(data.count)
        totalDownloadedBytes += Int64(data.count)
        
        if totalExpectedBytes > 0 {
            let fraction = Double(totalDownloadedBytes) / Double(totalExpectedBytes)
            progressCallback?(fraction, totalDownloadedBytes, totalExpectedBytes)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        cleanup()
        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            let now = Date()
            if firstFailureTime == nil {
                firstFailureTime = now
            }
            if now.timeIntervalSince(firstFailureTime!) <= 5.0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !self.isCancelled {
                        self.downloadNextFile()
                    }
                }
                return
            }
            completionCallback?(.failure(error))
        } else {
            firstFailureTime = nil
            do {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: currentDestinationURL!.path) {
                    try fileManager.removeItem(at: currentDestinationURL!)
                }
                try fileManager.moveItem(at: currentIncompleteURL!, to: currentDestinationURL!)
                currentFileIndex += 1
                downloadNextFile()
            } catch {
                completionCallback?(.failure(error))
            }
        }
    }
}
