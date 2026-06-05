import SwiftUI
import AppKit
import Combine
import AVFoundation
import CoreAudio

@MainActor
class AppController: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var activeDictionaryNotification: DictionaryNotification? = nil
    @Published var isPopoverOpen = false
    private var wasPopoverOpenBeforeRecording = false
    @Published var statusText = "Ready"
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
            audioManager.isPaused = isPaused
        }
    }
    private let audioManager = AudioManager()
    private var sonorContext: SonorContext?
    private var targetAppPID: pid_t = 0  
    private var targetAXElement: AXUIElement? = nil
    private var targetAppBundleID: String? = nil
    private var wasTextFieldFocusedAtStart: Bool = false
    private var currentTask: Task<Void, Never>?
    override init() {
        super.init()
        let modes = VoiceMode.loadAndMigrateModes()
        self.availableModes = modes
        let activeModeID = UserDefaults.standard.string(forKey: "activeModeID") ?? ""
        self.currentMode = modes.first(where: { $0.id.uuidString == activeModeID }) ?? modes.first

        setupHotkey()
        NotificationCenter.default.addObserver(forName: Notification.Name("VoiceModesUpdated"), object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in
                self?.reloadModes()
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("ReleaseWhisperContext"), object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in
                self?.sonorContext = nil
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("AccessibilityPermissionRevoked"), object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.isRecording || self.isCurrentlyProcessing {
                    self.cancelRecording()
                }
            }
        }
    }
    private func setupHotkey() {
        HotkeyManager.shared.onHotkeyDown = { [weak self] in
            self?.toggleRecording()
        }
        HotkeyManager.shared.onHotkeyUp = { [weak self] in
            guard let self = self else { return }
            if self.isRecording && self.activeHotkeyMode == .hold {
                self.stopRecordingAndTranscribe()
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
        HotkeyManager.shared.isSecondaryHotkeysEnabled = { [weak self] in
            return self?.isRecording == true || self?.isPaused == true
        }
        HotkeyManager.shared.startListening()
    }
    func selectNextMode() {
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
    func toggleRecording() {
        if isCurrentlyProcessing {
            return
        }
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            let isTrusted = AXIsProcessTrusted()
            if !isTrusted {
                
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                WindowManager.shared.openAccessibilityPermissionWindow()
                return
            }
            
            let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if authStatus == .denied || authStatus == .restricted {
                WindowManager.shared.openMicrophonePermissionWindow()
                return
            } else if authStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: AVMediaType.audio) { granted in
                    Task { @MainActor in
                        if !granted {
                            WindowManager.shared.openMicrophonePermissionWindow()
                        } else {
                            self.toggleRecording()
                        }
                    }
                }
                return
            }

            let modeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
            self.activeHotkeyMode = (modeString == "Hold") ? .hold : .click
            guard case .downloaded = ModelManager.shared.whisperState else {
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
            if !AuthManager.shared.isLoggedIn {
                selectedMode = availableModes.first(where: { $0.name == "Raw Output" }) ?? VoiceMode.defaults.first!
                self.currentMode = selectedMode
            } else {
                selectedMode = currentMode ?? availableModes.first ?? VoiceMode.defaults.first!
                if self.currentMode?.id != selectedMode.id {
                    self.selectMode(selectedMode)
                }
            }
            self.isRecording = true
            let sessionID = UUID()
            self.currentRecordingSessionID = sessionID
            
            let behavior = selectedMode.audioBehavior ?? .keep
            if self.sonorContext == nil {
                self.statusText = "Initializing"
            } else if behavior == .mute {
                self.statusText = "Preparing..."
            } else {
                self.statusText = "Listening..."
            }
            WindowManager.shared.showHUD(controller: self)
            if self.sonorContext == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    Task.detached {
                        let path = await MainActor.run { return ModelManager.shared.whisperModelURL.path }
                        if FileManager.default.fileExists(atPath: path) {
                            let context = SonorContext(modelPath: path)
                            await MainActor.run {
                                guard self.currentRecordingSessionID == sessionID else { return }
                                self.sonorContext = context
                                self.startRecordingProcess(selectedMode: selectedMode, sessionID: sessionID)
                            }
                        } else {
                        }
                    }
                }
            } else {
                Task {
                    await MainActor.run {
                        self.startRecordingProcess(selectedMode: selectedMode, sessionID: sessionID)
                    }
                }
            }
        }
    }
    private func startRecordingProcess(selectedMode: VoiceMode, sessionID: UUID) {
        Task.detached {
            try? await Task.sleep(nanoseconds: 150_000_000)
            let isStillRecording = await MainActor.run { 
                return self.isRecording && self.currentRecordingSessionID == sessionID
            }
            guard isStillRecording else { return }
            let behavior = selectedMode.audioBehavior ?? .keep
            
            await MainActor.run {
                guard self.isRecording && self.currentRecordingSessionID == sessionID else { return }
                
                if behavior == .mute {
                    MediaControlService.shared.pauseMultimedia(behavior: .mute)
                } else {
                    MediaControlService.shared.resetDidPauseMusic()
                }
                
                Task {
                    guard self.isRecording && self.currentRecordingSessionID == sessionID else { return }
                    Task {
                        await SoundPlayer.shared.playSound(named: "Start")
                    }
                    await MainActor.run {
                        guard self.isRecording && self.currentRecordingSessionID == sessionID else { return }
                        self.startRecording()
                    }
                }
            }
        }
    }
    private func startRecording() {
        self.isPaused = false
        performStartRecording()
    }
    private func performStartRecording() {
        self.isPaused = false
        let modeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
        self.activeHotkeyMode = (modeString == "Hold") ? .hold : .click
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.audioManager.startRecording()
                DispatchQueue.main.async {
                    self.isRecording = true
                    NotificationCenter.default.post(name: Notification.Name("HidePermissionViews"), object: nil)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.statusText = "Listening..."
                    }
                    Task { @MainActor [weak self] in
                        while let self = self, self.isRecording {
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
                            self?.audioLevels = Array(repeating: 0.01, count: 40)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusText = "Microphone error"
                    self.isRecording = false
                    self.hideHUDAfterDelay()
                }
            }
        }
    }


    func togglePause() {
        self.isPaused.toggle()
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
        Task.detached {
            _ = await self.audioManager.stopRecording()
        }
        if MediaControlService.shared.didPauseMusic {
            MediaControlService.shared.resumeMultimedia()
        }
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
                    if !self.isRecording {
                        self.statusText = "Ready"
                        WindowManager.shared.hideHUD()
                    }
                }
            }
        }
    }
    private func stopRecordingAndTranscribe() {
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

        let samples = audioManager.stopRecording()
        if MediaControlService.shared.didPauseMusic {
            MediaControlService.shared.resumeMultimedia()
        }
        currentTask = Task {
            guard let context = sonorContext else {
                await MainActor.run { 
                    self.statusText = "Error: Missing model" 
                }
                await SoundPlayer.shared.playSound(named: "Error")
                self.hideHUDAfterDelay()
                return
            }
            guard samples.count >= 4800 else {
                await MainActor.run { 
                    self.statusText = "No text recognized." 
                }
                await SoundPlayer.shared.playSound(named: "Error")
                self.hideHUDAfterDelay()
                return
            }
            let suggestedLanguage = UserDefaults.standard.string(forKey: "suggestedSpeechLanguage") ?? "en"
            let transcribedText = await context.transcribe(audioSamples: samples, language: suggestedLanguage)
            if Task.isCancelled {
                self.hideHUDAfterDelay()
                return
            }
            let rawText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else {
                await MainActor.run { 
                    self.statusText = "No text recognized." 
                }
                await SoundPlayer.shared.playSound(named: "Error")
                self.hideHUDAfterDelay()
                return
            }
            let duration = Double(samples.count) / 16000.0
            UsageTrackingService.shared.recordUsage(duration: duration, text: rawText)
            let correctedText = TextProcessingService.shared.applyCorrections(to: rawText, isLoggedIn: AuthManager.shared.isLoggedIn)
            let selectedMode = self.currentMode ?? VoiceMode.defaults.first!
            await AssistantWorkflowService.shared.execute(
                correctedText: correctedText,
                selectedMode: selectedMode,
                initialPID: self.targetAppPID,
                targetAXElement: self.targetAXElement,
                wasTextFieldFocusedAtStart: self.wasTextFieldFocusedAtStart,
                onStatusChange: { [weak self] newStatus in
                    self?.statusText = newStatus
                },
                onAutoLearnTrigger: { [weak self] targetPID, text in
                    self?.startAutoLearnTracking(targetPID: targetPID, originalText: text)
                }
            )
            self.hideHUDAfterDelay()

        }
    }


    func quitApp() {
        NSApplication.shared.terminate(nil)
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

    func undoDictionaryEntry() {
        if let notification = activeDictionaryNotification {
            AutoLearnService.shared.undoDictionaryEntry(notification: notification)
        }
        self.hideDictionaryNotification()
    }
    
    func hideDictionaryNotification() {
        withAnimation(.easeOut(duration: 0.5)) {
            self.activeDictionaryNotification = nil
        }
        if !self.isRecording {
            self.hideHUDAfterDelay()
        }
    }
}




