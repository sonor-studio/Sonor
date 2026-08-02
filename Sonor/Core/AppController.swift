import SwiftUI
import AppKit
import Combine
import AVFoundation
import CoreAudio

@MainActor
class AppController: NSObject, ObservableObject {
    
    @Published var isRecording = false
    @Published var activeDictionaryNotification: DictionaryNotification? = nil
    @Published var activeCopyNotification: String? = nil
    @Published var isPopoverOpen = false
    @Published var lastTranscription: String? = nil
    private var wasPopoverOpenBeforeRecording = false
    
    /// Displays the current status of the app in the HUD (e.g. "Listening...", "Processing")
    @Published var statusText = "Ready"
    @Published var isTranscribing = false
    @Published var isHovering = false
    @Published var failedAudioSamples: [Float]? = nil
    @Published var failedSelectedMode: VoiceMode? = nil
    var failedHistoryMessageID: UUID? = nil
    @Published var canRetryTranscription: Bool = false
    
    private var currentRecordingSessionID: UUID? = nil
    var isCurrentlyProcessing: Bool {
        let nonProcessingStatuses: Set<String> = ["Ready", "Cancelled", "No microphone permission", "Microphone error", "No text recognized.", "Error: Missing model", "Done!"]
        return !isRecording && !nonProcessingStatuses.contains(statusText) && !statusText.hasPrefix("Mode:")
    }
    @Published var audioLevel: Float = 0.0
    @Published var audioLevels: [Float] = Array(repeating: 0.01, count: 40)
    @Published var availableModes: [VoiceMode] = []
    @Published var currentMode: VoiceMode?
    @Published var activeHotkeyMode: HotkeyMode = .click
    @Published var isPaused = false {
        didSet {
            if isPaused {
                audioManager.pauseRecording()
            } else {
                do {
                    try audioManager.resumeRecording()
                } catch {
                }
            }
        }
    }
    
    private let audioManager = AudioManager()
    
    /// The process ID of the external application the user was focusing before recording started.
    private var targetAppPID: pid_t = 0  
    
    /// Accessibility Element reference to the specific text field the user had focused.
    private var targetAXElement: AXUIElement? = nil
    private var targetAppBundleID: String? = nil
    private var wasTextFieldFocusedAtStart: Bool = false
    
    // Task management for cancelling active recordings or processing
    private var currentTask: Task<Void, Never>?
    private var startRecordingTask: Task<Void, Never>?
    
    override init() {
        super.init()
        let modes = VoiceMode.loadAndMigrateModes()
        self.availableModes = modes
        let activeModeID = UserDefaults.standard.string(forKey: "activeModeID") ?? ""
        self.currentMode = modes.first(where: { $0.id.uuidString == activeModeID }) ?? modes.first

        setupHotkey()
        NotificationCenter.default.addObserver(forName: Notification.Name("VoiceModesUpdated"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadModes()
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("ReleaseWhisperContext"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                TranscriptionManager.shared.resetEngine()
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("PermissionsRevoked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isRecording || self.isCurrentlyProcessing {
                    self.cancelRecording()
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("AppWillTerminate"), object: nil, queue: .main) { _ in
            _ = self.audioManager.stopRecording()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("RetryHistoryTranscription"), object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let id = notification.object as? UUID else { return }
            Task { @MainActor in
                self.retryHistoryTranscription(id: id)
            }
        }
    }
    private var hotkeyDownTime: Date = Date()
    
    private func setupHotkey() {
        HotkeyManager.shared.onHotkeyDown = { [weak self] in
            self?.hotkeyDownTime = Date()
            self?.toggleRecording()
        }
        HotkeyManager.shared.onHotkeyUp = { [weak self] in
            guard let self = self else { return }
            if self.isRecording {
                if self.activeHotkeyMode == .hold {
                    self.stopRecordingAndTranscribe()
                } else if self.activeHotkeyMode == .automatic {
                    let duration = Date().timeIntervalSince(self.hotkeyDownTime)
                    if duration > 0.4 {
                        self.stopRecordingAndTranscribe()
                    }
                }
            }
        }
        HotkeyManager.shared.onCancelKeyDown = { [weak self] in
            self?.cancelRecording()
        }
        HotkeyManager.shared.onPauseKeyDown = { [weak self] in
            self?.togglePause()
        }
        HotkeyManager.shared.onAssistantKeyDown = { [weak self] in
            self?.selectNextMode()
        }

        HotkeyManager.shared.startListening()
    }
    func selectNextMode() {
        guard isRecording else { return }
        
        let terminalStates = ["Cancelled", "Done!", "No text recognized.", "Error: Missing model", "No microphone permission", "Microphone error"]
        if isCurrentlyProcessing || terminalStates.contains(statusText) {
            return
        }
        let isGemmaDownloaded = ModelManager.shared.gemmaState == .downloaded
        let functionalModes = availableModes.filter { mode in
            isGemmaDownloaded || mode.prompt.isEmpty
        }
        guard !functionalModes.isEmpty else { return }
        guard functionalModes.count > 1 else {
            return
        }
        let currentIndex = functionalModes.firstIndex(where: { $0.id == currentMode?.id }) ?? -1
        let nextIndex = (currentIndex + 1) % functionalModes.count
        let nextMode = functionalModes[nextIndex]
        changeMode(nextMode)
    }
    func changeMode(_ nextMode: VoiceMode) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            self.selectMode(nextMode)
        }
        if !self.isRecording {
            statusText = "Mode: \(nextMode.name)"
        }
        if WindowManager.shared.hudWindow?.isVisible == false {
            WindowManager.shared.showHUD(controller: self)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.isRecording {
                if self.statusText.hasPrefix("Mode:") {
                    self.statusText = "Listening..."
                }
            } else {
                if self.statusText.hasPrefix("Mode:") {
                    self.statusText = "Ready"
                    WindowManager.shared.hideHUD()
                }
            }
        }
    }
    func reloadModes() {
        let modes = VoiceMode.loadAndMigrateModes()
        self.availableModes = modes
        let activeModeID = UserDefaults.standard.string(forKey: "activeModeID") ?? ""
        self.currentMode = modes.first(where: { $0.id.uuidString == activeModeID }) ?? modes.first
    }

    /// Toggles the recording state. 
    /// Handles accessibility permissions, microphone permissions, and model checking before proceeding.
    func toggleRecording() {
        if isCurrentlyProcessing {
            return
        }
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            let isTrusted = AXIsProcessTrusted()
            let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            
            if !isTrusted || authStatus == .denied || authStatus == .restricted {
                if !isTrusted {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                }
                WindowManager.shared.openPermissionsWindow()
                return
            } else if authStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: AVMediaType.audio) { granted in
                    Task { @MainActor in
                        if !granted {
                            WindowManager.shared.openPermissionsWindow()
                        } else {
                            self.toggleRecording()
                        }
                    }
                }
                return
            }

            let modeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
            if modeString == "Hold" { self.activeHotkeyMode = .hold }
            else if modeString == "Automatic" { self.activeHotkeyMode = .automatic }
            else { self.activeHotkeyMode = .click }
            let selectedModelId = ModelManager.shared.selectedWhisperModelId
            guard case .downloaded = ModelManager.shared.whisperStates[selectedModelId] else {
                self.isRecording = false
                WindowManager.shared.openSettings()
                DispatchQueue.main.async {
                    ModelManager.shared.showModelsRequiredModal = true
                }
                return
            }
            wasPopoverOpenBeforeRecording = isPopoverOpen
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                targetAppPID = frontApp.processIdentifier
                targetAppBundleID = frontApp.bundleIdentifier
                targetAXElement = PasteManager.shared.getFocusedAXElement(pid: targetAppPID)
                wasTextFieldFocusedAtStart = PasteManager.shared.isElementTextField(targetAXElement)
            }
            let selectedMode: VoiceMode
            selectedMode = currentMode ?? availableModes.first ?? VoiceMode.defaults.first!
            if self.currentMode?.id != selectedMode.id {
                self.selectMode(selectedMode)
            }
            self.activeCopyNotification = nil
            self.activeDictionaryNotification = nil
            self.canRetryTranscription = false
            self.failedAudioSamples = nil
            self.failedSelectedMode = nil
            
            self.isRecording = true
            let sessionID = UUID()
            self.currentRecordingSessionID = sessionID
            
            self.statusText = "Initializing"
            WindowManager.shared.showHUD(controller: self)
            
            Task {
                do {
                    try await TranscriptionManager.shared.ensureEngineReady()
                    await MainActor.run {
                        guard self.currentRecordingSessionID == sessionID else { return }
                        self.statusText = "Listening..."
                        self.startRecordingProcess(selectedMode: selectedMode, sessionID: sessionID)
                    }
                } catch {
                    await MainActor.run {
                        print("Engine Error: \(error)")
                        self.statusText = "Err: \(error.localizedDescription)"
                        self.hideHUDAfterDelay()
                    }
                }
            }
        }
    }
    private func startRecordingProcess(selectedMode: VoiceMode, sessionID: UUID) {
        startRecordingTask?.cancel()
        startRecordingTask = Task.detached {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            
            let isStillRecording = await MainActor.run { 
                return self.isRecording && self.currentRecordingSessionID == sessionID
            }
            guard isStillRecording else { return }
            let behavior = selectedMode.audioBehavior ?? .keep
            
            await MainActor.run {
                if Task.isCancelled { return }
                guard self.isRecording && self.currentRecordingSessionID == sessionID else { return }
                
                Task {
                    if Task.isCancelled { return }
                    guard self.isRecording && self.currentRecordingSessionID == sessionID else { return }
                    
                    if behavior == .mute {
                        MediaControlService.shared.pauseMultimedia(behavior: .mute)
                    }
                    
                    Task {
                        await SoundPlayer.shared.playSound(named: "Start")
                    }
                    
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    
                    await MainActor.run {
                        if Task.isCancelled { return }
                        guard self.isRecording && self.currentRecordingSessionID == sessionID else { return }
                        self.startRecording(sessionID: sessionID)
                    }
                }
            }
        }
    }
    private func startRecording(sessionID: UUID) {
        self.isPaused = false
        withAnimation {
            canRetryTranscription = false
            failedAudioSamples = nil
            failedSelectedMode = nil
        }
        performStartRecording(sessionID: sessionID)
    }
    private func performStartRecording(sessionID: UUID) {
        self.isPaused = false
        let modeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
        if modeString == "Hold" { self.activeHotkeyMode = .hold }
        else if modeString == "Automatic" { self.activeHotkeyMode = .automatic }
        else { self.activeHotkeyMode = .click }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.audioManager.startRecording()
                DispatchQueue.main.async {
                    guard self.currentRecordingSessionID == sessionID else {
                        _ = self.audioManager.stopRecording()
                        return
                    }
                    self.isRecording = true
                    NotificationCenter.default.post(name: Notification.Name("HidePermissionViews"), object: nil)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.statusText = "Listening..."
                    }
                    Task { @MainActor in
                        while self.isRecording {
                            if !self.isPaused {
                                let level = self.audioManager.audioLevel
                                self.audioLevel = level
                                self.audioLevels.append(max(0.01, level))
                                if self.audioLevels.count > 40 {
                                    self.audioLevels.removeFirst()
                                }
                            }
                            try? await Task.sleep(nanoseconds: 50_000_000)
                        }
                        withAnimation {
                            self.audioLevels = Array(repeating: 0.01, count: 40)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    MediaControlService.shared.resumeMultimedia()
                    self.statusText = "Microphone error"
                    self.isRecording = false
                    self.hideHUDAfterDelay()
                }
            }
        }
    }


    func togglePause() {
        guard isRecording else { 
            return 
        }
        self.isPaused.toggle()
        if self.isPaused {
            self.statusText = "Paused"
        } else {
            self.statusText = "Listening..."
        }
    }

    func selectMode(_ mode: VoiceMode) {
        self.currentMode = mode
        UserDefaults.standard.set(mode.id.uuidString, forKey: "activeModeID")
    }
    func cancelRecording() {
        guard isRecording || isCurrentlyProcessing else { return }
        if statusText == "Initializing" {
            return
        }
        isRecording = false
        self.isPaused = false
        self.currentRecordingSessionID = nil
        statusText = "Cancelled"
        let taskToCancel = currentTask
        currentTask = nil
        taskToCancel?.cancel()
        
        startRecordingTask?.cancel()
        startRecordingTask = nil
        
        _ = self.audioManager.stopRecording()
        
        MediaControlService.shared.resumeMultimedia()
        withAnimation {
            self.audioLevels = Array(repeating: 0.01, count: 40)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !self.isRecording && self.statusText == "Cancelled" {
                self.statusText = "Ready"
                WindowManager.shared.hideHUD()
            }
        }
    }

    private func hideHUDAfterDelay() {
        Task {
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !self.isRecording && self.activeDictionaryNotification == nil && self.activeCopyNotification == nil {
                        self.statusText = "Ready"
                        WindowManager.shared.hideHUD()
                    }
                }
            }
        }
    }
    func stopRecordingAndTranscribe() {
        guard isRecording else {
            return
        }
        self.isPaused = false
        isRecording = false
        self.currentRecordingSessionID = nil
        statusText = "Processing"
        if !wasPopoverOpenBeforeRecording {
            isPopoverOpen = false
        }
        
        startRecordingTask?.cancel()
        startRecordingTask = nil

        let samples = audioManager.stopRecording()
        MediaControlService.shared.resumeMultimedia()
        currentTask = Task {
            guard samples.count >= 8000 else {
                await MainActor.run { 
                    self.statusText = "Cancelled" 
                }
                self.hideHUDAfterDelay()
                return
            }
            
            // Silence check removed to prevent falsely cancelling quiet microphones
            
            let selectedMode = await MainActor.run { return self.currentMode ?? VoiceMode.defaults.first! }
            _ = selectedMode.language ?? "auto"
            
            await self.processAudio(samples: samples, selectedMode: selectedMode)
        }
    }
    
    func processAudio(samples: [Float], selectedMode: VoiceMode, historyMessageID: UUID? = nil, isInlineRetry: Bool = false) async {
        let snippets = UserDefaults.standard.dictionary(forKey: "snippetsEntries") as? [String: String] ?? [:]
        let snippetKeys = Array(snippets.keys)
        let initialPrompt = snippetKeys.isEmpty ? nil : snippetKeys.joined(separator: ", ")
        
        do {
            let transcribedText = try await TranscriptionManager.shared.transcribe(audioSamples: samples, language: "auto", initialPrompt: initialPrompt)
            
            if Task.isCancelled {
                if !isInlineRetry {
                    self.hideHUDAfterDelay()
                }
                return
            }
            let rawText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else {
                if !isInlineRetry {
                    await MainActor.run { 
                        self.statusText = "No text recognized." 
                    }
                    await SoundPlayer.shared.playSound(named: "Error")
                    self.hideHUDAfterDelay()
                }
                return
            }
            let duration = Double(samples.count) / 16000.0
            UsageTrackingService.shared.recordUsage(duration: duration, text: rawText)
            let correctedText = TextProcessingService.shared.applyCorrections(to: rawText)
            await MainActor.run {
                self.lastTranscription = correctedText
            }
            await AssistantWorkflowService.shared.execute(
                correctedText: correctedText,
                selectedMode: selectedMode,
                initialPID: self.targetAppPID,
                targetAXElement: self.targetAXElement,
                wasTextFieldFocusedAtStart: self.wasTextFieldFocusedAtStart,
                audioSamples: samples,
                historyMessageID: historyMessageID,
                isBackgroundRetry: isInlineRetry,
                onStatusChange: { status in
                    if !isInlineRetry {
                        self.statusText = status
                    }
                },
                onAutoLearnTrigger: { targetPID, text in
                    if !isInlineRetry {
                        self.startAutoLearnTracking(targetPID: targetPID, originalText: text)
                    }
                },
                onCopyNotificationTrigger: { textToCopy in
                    if !isInlineRetry {
                        self.showCopyNotification(text: textToCopy)
                    }
                }
            )
            if !isInlineRetry {
                self.hideHUDAfterDelay()
            }
        } catch {
            if isInlineRetry {
                if let historyMessageID = historyMessageID {
                    await MainActor.run {
                        let appName = NSRunningApplication(processIdentifier: self.targetAppPID)?.localizedName ?? "Unknown App"
                        let whisperModel = TranscriptionManager.shared.activeModelName
                        let gemmaModel = "Gemma 3"
                        let shouldRunLLM = !selectedMode.prompt.isEmpty
                        MessageMemoryManager.shared.updateMessage(id: historyMessageID, newText: t("Transcription failed"), isError: true, appName: appName, transcriptionModel: whisperModel, llmModel: shouldRunLLM ? gemmaModel : nil, modeName: selectedMode.name, updateMetadata: true)
                    }
                }
            } else {
                if let historyMessageID = historyMessageID {
                    await MainActor.run {
                        let appName = NSRunningApplication(processIdentifier: self.targetAppPID)?.localizedName ?? "Unknown App"
                        let whisperModel = TranscriptionManager.shared.activeModelName
                        let gemmaModel = "Gemma 3"
                        let shouldRunLLM = !selectedMode.prompt.isEmpty
                        MessageMemoryManager.shared.updateMessage(id: historyMessageID, newText: t("Transcription failed"), isError: true, appName: appName, transcriptionModel: whisperModel, llmModel: shouldRunLLM ? gemmaModel : nil, modeName: selectedMode.name, updateMetadata: true)
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.3)) {
                            self.statusText = "Transcription failed"
                            self.failedAudioSamples = samples
                            self.failedSelectedMode = selectedMode
                            self.canRetryTranscription = true
                        }
                    }
                } else {
                    await MainActor.run {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.3)) {
                            self.statusText = "Transcription failed"
                            self.failedAudioSamples = samples
                            self.failedSelectedMode = selectedMode
                            self.canRetryTranscription = true
                        }
                        let appName = NSRunningApplication(processIdentifier: self.targetAppPID)?.localizedName ?? "Unknown App"
                        let whisperModel = TranscriptionManager.shared.activeModelName
                        let gemmaModel = "Gemma 3"
                        let shouldRunLLM = !selectedMode.prompt.isEmpty
                        
                        let msgId = MessageMemoryManager.shared.saveMessage(t("Transcription failed"), samples: samples, isError: true, appName: appName, transcriptionModel: whisperModel, llmModel: shouldRunLLM ? gemmaModel : nil, modeName: selectedMode.name)
                        self.failedHistoryMessageID = msgId
                    }
                }
                await SoundPlayer.shared.playSound(named: "Error")
                // Do not hide HUD so the user can see the retry button
            }
        }
    }

    func retryTranscription() {
        guard let samples = failedAudioSamples, let mode = failedSelectedMode else { return }
        let histId = self.failedHistoryMessageID
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.3)) {
            self.canRetryTranscription = false
            self.statusText = "Processing"
        }
        currentTask = Task {
            await self.processAudio(samples: samples, selectedMode: mode, historyMessageID: histId)
        }
    }

    func retryHistoryTranscription(id: UUID) {
        guard let data = MessageMemoryManager.shared.getAudioData(for: id),
              let samples = MessageMemoryManager.shared.convertWAVToSamples(data: data) else { return }
        
        let mode = self.currentMode ?? VoiceMode.defaults.first! // Use currently selected mode
        
        MessageMemoryManager.shared.updateMessage(id: id, newText: t("Processing"), isError: false)
        
        Task {
            await self.processAudio(samples: samples, selectedMode: mode, historyMessageID: id, isInlineRetry: true)
        }
    }

    func quitApp() {
        self.cancelRecording()
        _ = self.audioManager.stopRecording()
        NotificationCenter.default.post(name: NSNotification.Name("AppWillTerminate"), object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Darwin._exit(0)
        }
    }
    func startAutoLearnTracking(targetPID: pid_t, originalText: String) {
        AutoLearnService.shared.startAutoLearnTracking(targetPID: targetPID, originalText: originalText, currentNotification: activeDictionaryNotification) { [weak self] newNotification in
            guard let self = self else { return }
            self.activeDictionaryNotification = newNotification
            WindowManager.shared.showHUD(controller: self)
            
            let currentWrong = newNotification.wrong
            let currentCorrect = newNotification.correct
            
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if self.activeDictionaryNotification?.wrong == currentWrong && self.activeDictionaryNotification?.correct == currentCorrect {
                        self.hideDictionaryNotification()
                    }
                }
            }
        }
    }

    func undoDictionaryEntry(delayHide: Bool = false) {
        if let notification = activeDictionaryNotification {
            AutoLearnService.shared.undoDictionaryEntry(notification: notification)
        }
        
        if delayHide {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self.hideDictionaryNotification()
                }
            }
        } else {
            self.hideDictionaryNotification()
        }
    }
    
    func hideDictionaryNotification() {
        withAnimation(.easeOut(duration: 0.5)) {
            self.activeDictionaryNotification = nil
        }
        if !self.isRecording {
            self.hideHUDAfterDelay()
        }
    }
    
    func showCopyNotification(text: String) {
        self.activeCopyNotification = text
        WindowManager.shared.showHUD(controller: self)
        
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                if self.activeCopyNotification == text {
                    self.hideCopyNotification()
                }
            }
        }
    }
    
    func hideCopyNotification() {
        withAnimation(.easeOut(duration: 0.5)) {
            self.activeCopyNotification = nil
        }
        if UserDefaults.standard.bool(forKey: "isIncognitoMode") {
            NotificationCenter.default.post(name: NSNotification.Name("PlayIncognitoAnimation"), object: NSNumber(value: true))
        }
        if !self.isRecording {
            self.hideHUDAfterDelay()
        }
    }
    
    func copyNotificationTextToClipboard(delayHide: Bool = false) {
        if let text = activeCopyNotification {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            if delayHide {
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await MainActor.run {
                        if self.activeCopyNotification == text {
                            self.hideCopyNotification()
                        }
                    }
                }
            } else {
                self.hideCopyNotification()
            }
        }
    }
}




