import Foundation
import Combine
import MLXHuggingFace
import Hub
import HuggingFace

enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case paused(progress: Double)
    case downloaded
}

@MainActor
class ModelManager: ObservableObject {
    static let shared = ModelManager()
    
    @Published var whisperState: DownloadState = .notDownloaded
    @Published var gemmaState: DownloadState = .notDownloaded
    
    // UI State for Alerts
    @Published var showModelsRequiredModal = false
    @Published var downloadError: String? = nil
    @Published var showDownloadErrorModal = false
    
    let modelsDirectory: URL
    
    private let gemmaModelId = "mlx-community/gemma-3-4b-it-qat-4bit"
    private let whisperModelId = "ggerganov/whisper.cpp"
    private let whisperFilename = "ggml-large-v3-turbo-q5_0.bin"
    
    private var gemmaDownloadTask: Task<Void, Never>?
    private var activeWhisperDownloader: WhisperDownloader?
    private var activeGemmaDownloader: GemmaDownloader?
    private var gemmaProgressObservation: NSKeyValueObservation?
    
    var whisperModelURL: URL {
        let api = HubApi(downloadBase: modelsDirectory, cache: nil)
        return api.localRepoLocation(Hub.Repo(id: whisperModelId)).appendingPathComponent(whisperFilename)
    }
    
    private init() {
        print("ℹ️ [ModelManager] Initializing ModelManager...")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = appSupport.appendingPathComponent("Sonor").appendingPathComponent("Models")
        print("ℹ️ [ModelManager] Base models directory: \(modelsDirectory.path)")
        
        createModelsDirectoryIfNeeded()
        checkInitialStates()
    }
    
    private func createModelsDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: modelsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
                print("✅ [ModelManager] Successfully created base models directory.")
            } catch {
                print("❌ [ModelManager] Failed to create models directory: \(error.localizedDescription)")
            }
        }
    }
    
    func checkInitialStates() {
        print("ℹ️ [ModelManager] Checking initial states for models...")
        
        // Check Whisper
        let whisperPath = whisperModelURL.path
        let whisperIncompletePath = whisperPath + ".incomplete"
        let whisperExists = FileManager.default.fileExists(atPath: whisperPath)
        let whisperIncompleteExists = FileManager.default.fileExists(atPath: whisperIncompletePath)
        print("ℹ️ [ModelManager] Checking Whisper at \(whisperPath) - Exists: \(whisperExists)")
        if whisperExists {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: whisperPath),
               let size = attributes[.size] as? Int64 {
                let sizeMB = Double(size) / (1024.0 * 1024.0)
                print("ℹ️ [ModelManager] Whisper file size on disk: \(String(format: "%.2f", sizeMB)) MB")
            }
            whisperState = .downloaded
        } else if whisperIncompleteExists {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: whisperIncompletePath),
               let size = attributes[.size] as? Int64 {
                let expectedSize: Double = 574_823_136.0 // Approximately 548 MB
                let progress = min(Double(size) / expectedSize, 0.99)
                whisperState = .paused(progress: progress)
            } else {
                whisperState = .paused(progress: 0.0)
            }
        } else {
            whisperState = .notDownloaded
        }
        
        // Check Gemma
        let api = HubApi(downloadBase: modelsDirectory, cache: nil)
        let repo = Hub.Repo(id: gemmaModelId)
        let gemmaDir = api.localRepoLocation(repo)
        let gemmaExists = FileManager.default.fileExists(atPath: gemmaDir.path)
        print("ℹ️ [ModelManager] Checking Gemma directory at \(gemmaDir.path) - Exists: \(gemmaExists)")
        
        if gemmaExists {
            let savedTotal = UserDefaults.standard.object(forKey: "GemmaTotalExpectedBytes") as? Int64
            let savedDownloaded = UserDefaults.standard.object(forKey: "GemmaTotalDownloadedBytes") as? Int64
            
            if let total = savedTotal, let downloaded = savedDownloaded, total > 0 {
                if downloaded >= total {
                    gemmaState = .downloaded
                } else {
                    let progress = min(Double(downloaded) / Double(total), 0.99)
                    gemmaState = .paused(progress: progress)
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
                    if totalSize > 2_000_000_000 {
                        gemmaState = .downloaded
                    } else {
                        let progress = min(Double(totalSize) / 3_000_000_000.0, 0.99)
                        gemmaState = .paused(progress: progress)
                    }
                } else {
                    gemmaState = .notDownloaded
                }
            }
        } else {
            gemmaState = .notDownloaded
        }
        print("ℹ️ [ModelManager] Initial state check complete. Whisper: \(whisperState), Gemma: \(gemmaState)")
    }
    
    // MARK: - Whisper Download
    
    func downloadWhisper() {
        if case .downloading = whisperState { return }
        if case .downloaded = whisperState { return }
        
        print("📥 [Whisper] Starting custom download process for \(whisperModelId)...")
        var initialWhisperProgress: Double = 0.0
        let whisperIncompletePath = whisperModelURL.path + ".incomplete"
        if FileManager.default.fileExists(atPath: whisperIncompletePath),
           let attributes = try? FileManager.default.attributesOfItem(atPath: whisperIncompletePath),
           let size = attributes[.size] as? Int64 {
            let expectedSize: Double = 574_823_136.0 // Approximately 548 MB
            initialWhisperProgress = min(Double(size) / expectedSize, 0.99)
        }
        whisperState = .downloading(progress: initialWhisperProgress)
        
        activeWhisperDownloader?.cancel()
        
        let downloader = WhisperDownloader(destinationURL: whisperModelURL)
        self.activeWhisperDownloader = downloader
        
        let whisperDownloadURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!
        
        var lastEmittedProgress: Double = initialWhisperProgress
        var lastEmissionTime = Date()
        
        downloader.start(from: whisperDownloadURL) { [weak self, weak downloader] progress in
            guard let self = self, let downloader = downloader else { return }
            let clampedProgress = max(progress, initialWhisperProgress)
            let now = Date()
            let diff = clampedProgress - lastEmittedProgress
            let timeDiff = now.timeIntervalSince(lastEmissionTime)
            
            if diff >= 0.01 || (diff > 0 && timeDiff >= 0.1) || clampedProgress >= 1.0 {
                lastEmittedProgress = clampedProgress
                lastEmissionTime = now
                DispatchQueue.main.async {
                    guard self.activeWhisperDownloader === downloader else { return }
                    self.whisperState = .downloading(progress: clampedProgress)
                }
            }
        } completion: { [weak self, weak downloader] result in
            guard let self = self, let downloader = downloader else { return }
            DispatchQueue.main.async {
                guard self.activeWhisperDownloader === downloader else { return }
                self.activeWhisperDownloader = nil
                switch result {
                case .success:
                    print("✅ [Whisper] Download completed successfully!")
                    self.whisperState = .downloaded
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                        print("⚠️ [Whisper] Download was explicitly cancelled. State handled by cancellation method.")
                    } else {
                        print("❌ [Whisper] Failed to download Whisper: \(error.localizedDescription)")
                        
                        // Recalculate progress from disk if lastEmitted is not helpful
                        var finalProgress = lastEmittedProgress >= 0 ? lastEmittedProgress : 0.0
                        if finalProgress == 0.0 {
                            let incompleteURL = self.whisperModelURL.deletingLastPathComponent().appendingPathComponent(self.whisperModelURL.lastPathComponent + ".incomplete")
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: incompleteURL.path),
                               let size = attrs[.size] as? Int64 {
                                finalProgress = min(Double(size) / 574_823_136.0, 0.99)
                            }
                        }
                        
                        self.downloadError = error.localizedDescription
                        self.showDownloadErrorModal = true
                        self.whisperState = .paused(progress: finalProgress)
                    }
                }
            }
        }
    }
    
    func pauseWhisperDownload() {
        print("⚠️ [Whisper] Pausing Whisper download...")
        activeWhisperDownloader?.cancel()
        activeWhisperDownloader = nil
        
        var finalProgress = 0.0
        let incompleteURL = whisperModelURL.deletingLastPathComponent().appendingPathComponent(whisperModelURL.lastPathComponent + ".incomplete")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: incompleteURL.path),
           let size = attrs[.size] as? Int64 {
            finalProgress = min(Double(size) / 574_823_136.0, 0.99)
        }
        
        whisperState = .paused(progress: finalProgress)
    }

    func cancelWhisperDownload() {
        print("⚠️ [Whisper] Cancelling Whisper download...")
        activeWhisperDownloader?.cancel()
        activeWhisperDownloader = nil
        whisperState = .notDownloaded
        
        // Clean up the incomplete download file on cancellation
        let incompleteURL = whisperModelURL.deletingLastPathComponent().appendingPathComponent(whisperModelURL.lastPathComponent + ".incomplete")
        try? FileManager.default.removeItem(at: incompleteURL)
    }
    
    func pauseAllDownloads() {
        if case .downloading = whisperState {
            pauseWhisperDownload()
        }
        if case .downloading = gemmaState {
            pauseGemmaDownload()
        }
    }
    
    func uninstallWhisper() {
        print("🧹 [Whisper] Uninstalling Whisper model...")
        
        // Cancel any active download first
        cancelWhisperDownload()
        
        // Notify AppController to release active sonorContext and close its file handle
        NotificationCenter.default.post(name: Notification.Name("ReleaseWhisperContext"), object: nil)
        
        // Clear global network cache responses
        URLCache.shared.removeAllCachedResponses()
        
        let api = HubApi(downloadBase: modelsDirectory, cache: nil)
        let repoDir = api.localRepoLocation(Hub.Repo(id: whisperModelId))
        
        do {
            if FileManager.default.fileExists(atPath: repoDir.path) {
                print("🧹 [Whisper] Removing local repository folder at \(repoDir.path)...")
                try FileManager.default.removeItem(at: repoDir)
                print("✅ [Whisper] Successfully deleted Whisper local repository folder.")
            } else {
                print("ℹ️ [Whisper] Local repository folder does not exist at \(repoDir.path)")
            }
        } catch {
            print("❌ [Whisper] Error uninstalling Whisper folder: \(error.localizedDescription)")
        }
        
        // Also aggressively remove the whole namespace dir just to be safe
        let ggerganovDir = modelsDirectory.appendingPathComponent("models").appendingPathComponent("ggerganov")
        if FileManager.default.fileExists(atPath: ggerganovDir.path) {
            print("🧹 [Whisper] Removing namespace folder at \(ggerganovDir.path)...")
            try? FileManager.default.removeItem(at: ggerganovDir)
            print("✅ [Whisper] Successfully deleted Whisper namespace folder.")
        }
        
        // Remove ALL HubCache locations (content-addressed blob store)
        // The HubCache stores a second copy of every downloaded file as blobs
        cleanHubCache(repoName: "models--ggerganov--whisper.cpp")
        
        whisperState = .notDownloaded
        print("✅ [Whisper] Uninstallation finished. State set to notDownloaded.")
    }
    
    // MARK: - Gemma Download
    
    func downloadGemma() {
        if case .downloading = gemmaState { return }
        if case .downloaded = gemmaState { return }
        
        print("📥 [Gemma] Starting custom download process for \(gemmaModelId)...")
        
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
                    print("✅ [Gemma] Download completed successfully!")
                    self.gemmaState = .downloaded
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                        print("⚠️ [Gemma] Download was explicitly paused or cancelled.")
                    } else {
                        print("❌ [Gemma] Failed to download Gemma: \(error.localizedDescription)")
                        
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
        print("⚠️ [Gemma] Pausing Gemma download...")
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
        print("⚠️ [Gemma] Cancelling Gemma download and erasing files...")
        activeGemmaDownloader?.cancel()
        activeGemmaDownloader = nil
        gemmaState = .notDownloaded
        
        UserDefaults.standard.removeObject(forKey: "GemmaTotalExpectedBytes")
        UserDefaults.standard.removeObject(forKey: "GemmaTotalDownloadedBytes")
        cleanupGemmaFiles()
    }
    
    private func cleanupGemmaFiles() {
        print("🧹 [Gemma] Cleaning up Gemma files...")
        
        // Release model and clear RAM memory first
        LLMManager.shared.releaseModel()
        
        // Clear global network cache responses
        URLCache.shared.removeAllCachedResponses()
        
        let api = HubApi(downloadBase: modelsDirectory, cache: nil, useBackgroundSession: false)
        let repoDir = api.localRepoLocation(Hub.Repo(id: gemmaModelId))
        
        do {
            if FileManager.default.fileExists(atPath: repoDir.path) {
                print("🧹 [Gemma Cancel] Removing local repository folder at \(repoDir.path)...")
                try FileManager.default.removeItem(at: repoDir)
                print("✅ [Gemma Cancel] Successfully deleted Gemma local repository folder.")
            } else {
                print("ℹ️ [Gemma Cancel] Local repository folder does not exist at \(repoDir.path)")
            }
        } catch {
            print("❌ [Gemma Cancel] Error removing repository: \(error)")
        }
        
        // Aggressively remove namespace dir
        let mlxDir = modelsDirectory.appendingPathComponent("models").appendingPathComponent("mlx-community")
        if FileManager.default.fileExists(atPath: mlxDir.path) {
            print("🧹 [Gemma Cancel] Removing namespace folder at \(mlxDir.path)...")
            try? FileManager.default.removeItem(at: mlxDir)
            print("✅ [Gemma Cancel] Successfully deleted Gemma namespace folder.")
        }
        
        // Remove ALL HubCache locations (content-addressed blob store)
        cleanHubCache(repoName: "models--mlx-community--gemma-3-4b-it-qat-4bit")
        
        // Also remove from HubApi's default downloadBase (~/Documents/huggingface/)
        cleanDefaultDownloadBase(repoPath: "models/mlx-community/gemma-3-4b-it-qat-4bit")
        
        // Clean up leaked CFNetwork temporary download files in the app's Temp directory
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
        print("⚠️ [Gemma] Requesting Gemma uninstallation...")
        
        cleanupGemmaFiles()
        
        gemmaState = .notDownloaded
        print("✅ [Gemma] Uninstallation finished. State set to notDownloaded.")
    }
    
    // MARK: - Aggressive File Eraser
    
    private func aggressivelyDeleteDirectory(at url: URL, retries: Int = 10, delay: TimeInterval = 0.1) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        
        print("🧹 [ModelManager] Attempting to aggressively delete \(url.path)...")
        do {
            try fm.removeItem(at: url)
            print("✅ [ModelManager] Successfully deleted \(url.path)")
        } catch {
            if retries > 0 {
                print("⚠️ [ModelManager] Failed to delete (locked?). Retrying in \(delay)s... (Error: \(error.localizedDescription))")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.aggressivelyDeleteDirectory(at: url, retries: retries - 1, delay: delay)
                }
            } else {
                print("❌ [ModelManager] Max retries reached. Failed to delete \(url.path)")
            }
        }
    }
    
    // MARK: - HubCache Cleanup
    
    /// Removes ALL possible HubCache locations for a given repository.
    /// The HuggingFace Hub library uses a content-addressed blob store that can
    /// keep a full copy of every downloaded file, separate from our downloadBase.
    /// This method checks all known cache locations and removes them.
    private func cleanHubCache(repoName: String) {
        let fm = FileManager.default
        
        // Collect all possible cache root directories
        var cacheRoots: [URL] = []
        
        // 1. Standard non-sandboxed macOS: ~/.cache/huggingface/hub/
        let homeDir = URL(fileURLWithPath: NSHomeDirectory())
        cacheRoots.append(homeDir.appendingPathComponent(".cache/huggingface/hub"))
        
        // 2. Sandboxed macOS / iOS: Library/Caches/huggingface/hub/
        if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheRoots.append(cachesDir.appendingPathComponent("huggingface/hub"))
        }
        
        // 3. HF_HUB_CACHE environment variable
        if let envCache = ProcessInfo.processInfo.environment["HF_HUB_CACHE"] {
            let expanded = NSString(string: envCache).expandingTildeInPath
            cacheRoots.append(URL(fileURLWithPath: expanded))
        }
        
        // 4. HF_HOME environment variable + /hub
        if let hfHome = ProcessInfo.processInfo.environment["HF_HOME"] {
            let expanded = NSString(string: hfHome).expandingTildeInPath
            cacheRoots.append(URL(fileURLWithPath: expanded).appendingPathComponent("hub"))
        }
        
        // 5. Use the actual HubCache.default path (in case it resolves differently)
        let hubCacheDefault = HubCache.default.cacheDirectory
        cacheRoots.append(hubCacheDefault)
        
        // Deduplicate paths
        let uniqueRoots = Array(Set(cacheRoots.map { $0.standardizedFileURL.path }))
        
        for rootPath in uniqueRoots {
            let rootURL = URL(fileURLWithPath: rootPath)
            
            // Remove the repo cache directory (blobs, snapshots, refs)
            let repoCache = rootURL.appendingPathComponent(repoName)
            if fm.fileExists(atPath: repoCache.path) {
                self.aggressivelyDeleteDirectory(at: repoCache)
            }
            
            // Remove lock files for this repo
            let lockDir = rootURL.appendingPathComponent(".locks").appendingPathComponent(repoName)
            if fm.fileExists(atPath: lockDir.path) {
                self.aggressivelyDeleteDirectory(at: lockDir)
            }
            
            // Remove metadata for this repo
            let metadataDir = rootURL.appendingPathComponent(".metadata").appendingPathComponent(repoName)
            if fm.fileExists(atPath: metadataDir.path) {
                self.aggressivelyDeleteDirectory(at: metadataDir)
            }
        }
    }
    
    // MARK: - Default DownloadBase Cleanup
    
    /// Removes model files from HubApi's default downloadBase directory.
    /// When HubApi is created without specifying downloadBase, it defaults to
    /// ~/Documents/huggingface/. This can happen through MLX's loadContainer
    /// or from earlier code versions. This method cleans that location.
    private func cleanDefaultDownloadBase(repoPath: String) {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let defaultBase = documents.appendingPathComponent("huggingface")
        let repoDir = defaultBase.appendingPathComponent(repoPath)
        
        if fm.fileExists(atPath: repoDir.path) {
            self.aggressivelyDeleteDirectory(at: repoDir)
        }
        
        // Also clean up the namespace directory if empty
        let namespaceDir = repoDir.deletingLastPathComponent()
        if fm.fileExists(atPath: namespaceDir.path) {
            let contents = (try? fm.contentsOfDirectory(atPath: namespaceDir.path)) ?? []
            if contents.isEmpty || contents == [".DS_Store"] {
                self.aggressivelyDeleteDirectory(at: namespaceDir)
            }
        }
    }
}

// MARK: - Custom Whisper Downloader
class WhisperDownloader: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var destinationURL: URL
    private var incompleteURL: URL
    
    private var progressCallback: ((Double) -> Void)?
    private var completionCallback: ((Result<URL, Error>) -> Void)?
    
    private var expectedLength: Int64 = 0
    private var downloadedBytes: Int64 = 0
    private var isCancelled = false
    
    init(destinationURL: URL) {
        self.destinationURL = destinationURL
        self.incompleteURL = destinationURL.deletingLastPathComponent().appendingPathComponent(destinationURL.lastPathComponent + ".incomplete")
        super.init()
    }
    
    func start(from url: URL, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        self.progressCallback = progress
        self.completionCallback = completion
        
        if isCancelled { return }
        
        let fileManager = FileManager.default
        
        // Ensure parent directory exists
        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Check if incomplete file exists for resumption
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
            print("📥 [Whisper Downloader] Resuming download from \(existingSize) bytes...")
        } else {
            print("📥 [Whisper Downloader] Starting fresh download...")
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
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var redirectedRequest = newRequest
        if let originalRequest = task.originalRequest,
           let rangeHeader = originalRequest.value(forHTTPHeaderField: "Range") {
            print("📥 [Whisper Downloader] Preserving Range header during redirect: \(rangeHeader)")
            redirectedRequest.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }
        completionHandler(redirectedRequest)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            
            // If we sent Range header but server doesn't support it or returns 200 instead of 206,
            // we must truncate the file and start fresh.
            if statusCode == 200 && downloadedBytes > 0 {
                print("⚠️ [Whisper Downloader] Server returned 200 instead of 206. Restarting fresh...")
                try? fileHandle?.truncate(atOffset: 0)
                downloadedBytes = 0
            }
            
            if statusCode == 416 {
                // Range Not Satisfiable - incomplete file might be corrupted or complete.
                // Restart fresh.
                print("⚠️ [Whisper Downloader] Server returned 416. Truncating and restarting...")
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
            progressCallback?(fraction)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        cleanup()
        
        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                // Cancelled manually
                return
            }
            completionCallback?(.failure(error))
        } else {
            // Success! Move incomplete file to destination
            do {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: incompleteURL, to: destinationURL)
                print("✅ [Whisper Downloader] File downloaded and moved to destination successfully.")
                completionCallback?(.success(destinationURL))
            } catch {
                completionCallback?(.failure(error))
            }
        }
    }
}
// MARK: - Custom Gemma Downloader
class GemmaDownloader: NSObject, URLSessionDataDelegate {
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
    
    private let defaultsKeyTotalBytes = "GemmaTotalExpectedBytes"
    private let defaultsKeyDownloadedBytes = "GemmaTotalDownloadedBytes"
    
    private var lastUserDefaultsSaveTime: Date = Date()
    private var isCancelled = false
    
    init(modelsDirectory: URL, repoId: String) {
        self.modelsDirectory = modelsDirectory
        self.repoId = repoId
        self.api = HubApi(downloadBase: modelsDirectory, cache: nil, useBackgroundSession: false)
        super.init()
    }
    
    func start(progress: @escaping (Double) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        self.progressCallback = progress
        self.completionCallback = completion
        
        Task {
            do {
                if fileList.isEmpty {
                    print("📥 [Gemma Downloader] Fetching filenames from Hugging Face...")
                    let globs = ["*.safetensors", "*.json", "*.jinja"]
                    let repo = Hub.Repo(id: repoId)
                    let filenames = try await api.getFilenames(from: repo, matching: globs)
                    self.fileList = filenames
                    
                    print("📥 [Gemma Downloader] Found \(filenames.count) files. Calculating total size...")
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
                    print("📥 [Gemma Downloader] Total expected size: \(Double(self.totalExpectedBytes) / 1024 / 1024) MB")
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
            print("✅ [Gemma Downloader] All files downloaded successfully.")
            UserDefaults.standard.removeObject(forKey: defaultsKeyDownloadedBytes)
            UserDefaults.standard.removeObject(forKey: defaultsKeyTotalBytes)
            completionCallback?(.success(()))
            return
        }
        
        let relativePath = fileList[currentFileIndex]
        
        // We cannot calculate precise previousFilesDownloaded without storing per-file sizes,
        // so we will just rely on the existing downloaded bytes on disk!
        // We will calculate total downloaded bytes by summing up the sizes of all files we have so far.
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
        
        // Ensure parent directory exists
        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            completionCallback?(.failure(error))
            return
        }
        
        // Check if file is already completely downloaded
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            print("✅ [Gemma Downloader] File already downloaded: \(relativePath)")
            currentFileIndex += 1
            downloadNextFile()
            return
        }
        
        // Check if incomplete file exists for resumption
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
        
        // Construct the resolve URL manually
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
            print("📥 [Gemma Downloader] Resuming \(relativePath) from \(existingSize) bytes...")
        } else {
            print("📥 [Gemma Downloader] Starting fresh download of \(relativePath)...")
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
    
    // MARK: - URLSessionDataDelegate
    
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
                print("⚠️ [Gemma Downloader] Server returned 200 instead of 206. Restarting fresh...")
                try? fileHandle?.truncate(atOffset: 0)
                totalDownloadedBytes -= currentFileDownloadedBytes
                currentFileDownloadedBytes = 0
            }
            
            if statusCode == 416 {
                print("⚠️ [Gemma Downloader] Server returned 416. Truncating and restarting...")
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
            
            // Save progress periodically (throttle to once per 0.5s to avoid disk thrashing)
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
            completionCallback?(.failure(error))
        } else {
            do {
                let fileManager = FileManager.default
                if let dest = currentDestinationURL, let inc = currentIncompleteURL {
                    if fileManager.fileExists(atPath: dest.path) {
                        try fileManager.removeItem(at: dest)
                    }
                    try fileManager.moveItem(at: inc, to: dest)
                    print("✅ [Gemma Downloader] File downloaded and moved: \(dest.lastPathComponent)")
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
