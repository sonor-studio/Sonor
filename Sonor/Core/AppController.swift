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
        DebugLogger.shared.addLog("AppController initialized")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        let modes = VoiceMode.loadAndMigrateModes()
        self.availableModes = modes
        let activeModeID = UserDefaults.standard.string(forKey: "activeModeID") ?? ""
        self.currentMode = modes.first(where: { $0.id.uuidString == activeModeID }) ?? modes.first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if !CGPreflightScreenCaptureAccess() {
                var updatedModes = VoiceMode.loadAndMigrateModes()
                var changed = false
                for i in 0..<updatedModes.count {
                    if updatedModes[i].audioBehavior == .pause {
                        updatedModes[i].audioBehavior = .mute
                        changed = true
                    }
                }
                if changed {
                    if let data = try? JSONEncoder().encode(updatedModes) {
                        UserDefaults.standard.set(data, forKey: "voiceModes")
                        NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
                    }
                    self.availableModes = updatedModes
                    if let activeModeID = UserDefaults.standard.string(forKey: "activeModeID"),
                       let updatedActive = updatedModes.first(where: { $0.id.uuidString == activeModeID }) {
                        self.currentMode = updatedActive
                    }
                }
            }
        }

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
            let behavior = selectedMode.audioBehavior ?? .keep
            if self.sonorContext == nil {
                self.statusText = "Initializing"
            } else if behavior == .pause || behavior == .mute {
                self.statusText = "Preparing..."
            } else {
                self.statusText = "Listening..."
            }
            WindowManager.shared.showHUD(controller: self)
            WindowManager.shared.forceFloatingWindow()
            if self.sonorContext == nil {
                DebugLogger.shared.addLog("SonorContext is nil, initiating load...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    Task.detached {
                        let path = await MainActor.run { return ModelManager.shared.whisperModelURL.path }
                        DebugLogger.shared.addLog("Model path to load: \(path)")
                        if FileManager.default.fileExists(atPath: path) {
                            DebugLogger.shared.addLog("Model file exists, creating SonorContext on BACKGROUND thread...")
                            let context = SonorContext(modelPath: path)
                            await MainActor.run {
                                DebugLogger.shared.addLog("SonorContext created, starting recording process...")
                                self.sonorContext = context
                                self.startRecordingProcess(selectedMode: selectedMode)
                            }
                        } else {
                            DebugLogger.shared.addLog("ERROR: Model file does not exist at path!")
                        }
                    }
                }
            } else {
                Task {
                    await MainActor.run {
                        self.startRecordingProcess(selectedMode: selectedMode)
                    }
                }
            }
        }
    }
    private func startRecordingProcess(selectedMode: VoiceMode) {
        Task.detached {
            try? await Task.sleep(nanoseconds: 150_000_000)
            let isStillRecording = await MainActor.run { return self.isRecording }
            DebugLogger.shared.addLog("startRecordingProcess: isStillRecording = \(isStillRecording)")
            guard isStillRecording else { return }
            let behavior = selectedMode.audioBehavior ?? .keep
            DebugLogger.shared.addLog("startRecordingProcess: behavior for mode '\(selectedMode.name)' = \(behavior)")
            let shouldMuteOrPause: Bool
            if behavior == .pause {
                if #available(macOS 12.3, *) {
                    shouldMuteOrPause = await AudioCaptureManager.shared.checkIsAudioPlaying()
                } else {
                    shouldMuteOrPause = false
                }
            } else if behavior == .mute {
                shouldMuteOrPause = true
            } else {
                shouldMuteOrPause = false
            }
            let isRecordingAfterCheck = await MainActor.run { return self.isRecording }
            DebugLogger.shared.addLog("startRecordingProcess: isRecordingAfterCheck = \(isRecordingAfterCheck)")
            guard isRecordingAfterCheck else { return }
            await MainActor.run {
                if behavior != .keep {
                    if shouldMuteOrPause {
                        if behavior == .pause {
                            MediaControlService.shared.pauseMultimedia(behavior: .pause)
                        } else if behavior == .mute {
                            MediaControlService.shared.pauseMultimedia(behavior: .mute)
                        }
                    } else {
                        MediaControlService.shared.resetDidPauseMusic()
                    }
                }
                Task {
                    guard self.isRecording else { return }
                    Task {
                        await SoundPlayer.shared.playSound(named: "Start")
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    await MainActor.run {
                        DebugLogger.shared.addLog("startRecordingProcess: self.isRecording right before startRecording() = \(self.isRecording)")
                        guard self.isRecording else { return }
                        self.startRecording()
                    }
                }
            }
        }
    }
    private func startRecording() {
        self.isPaused = false
        
        let isTrusted = AXIsProcessTrusted()
        if !isTrusted {
            self.statusText = t("Accessibility denied")
            self.isRecording = false
            self.hideHUDAfterDelay()
            WindowManager.shared.openAccessibilityPermissionWindow()
            MediaControlService.shared.resumeMultimedia()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
            return
        }
        
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        DebugLogger.shared.addLog("startRecording: authStatus = \(authStatus.rawValue)")
        if authStatus == .authorized {
            performStartRecording()
        } else if authStatus == .denied || authStatus == .restricted {
            DebugLogger.shared.addLog("startRecording: permission denied or restricted. Opening window.")
            self.statusText = t("Microphone denied")
            self.isRecording = false
            self.hideHUDAfterDelay()
            WindowManager.shared.openMicrophonePermissionWindow()
            MediaControlService.shared.resumeMultimedia()
        } else {
            DebugLogger.shared.addLog("startRecording: requesting access...")
            AVCaptureDevice.requestAccess(for: AVMediaType.audio) { granted in
                Task { @MainActor in
                    guard granted else {
                        DebugLogger.shared.addLog("startRecording: requestAccess NOT granted!")
                        self.statusText = t("Microphone denied")
                        self.isRecording = false
                        self.hideHUDAfterDelay()
                        WindowManager.shared.openMicrophonePermissionWindow()
                        MediaControlService.shared.resumeMultimedia()
                        return
                    }
                    DebugLogger.shared.addLog("startRecording: requestAccess GRANTED, calling performStartRecording()")
                    self.performStartRecording()
                }
            }
        }
    }
    private func performStartRecording() {
        self.isPaused = false
        let modeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
        self.activeHotkeyMode = (modeString == "Hold") ? .hold : .click
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                DebugLogger.shared.addLog("performStartRecording: calling try self.audioManager.startRecording()")
                try self.audioManager.startRecording()
                DebugLogger.shared.addLog("performStartRecording: startRecording() succeeded!")
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
                DebugLogger.shared.addLog("performStartRecording: CATCH ERROR: \(error.localizedDescription)")
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
        // wasPaused is no longer needed
        self.isPaused = false
        isRecording = false
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
            let transcribedText = await context.transcribe(audioSamples: samples)
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




