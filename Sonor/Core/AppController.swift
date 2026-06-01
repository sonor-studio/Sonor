import SwiftUI
import AppKit
import Combine
import AVFoundation
import CoreAudio

struct LearnedEntry: Equatable {
    let wrong: String
    let correct: String
    let previousValue: String?
}

struct DictionaryNotification: Equatable {
    let wrong: String
    let correct: String
    let learnedEntries: [LearnedEntry]
}

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
    private var targetAppPID: pid_t = 0  // PID aplikacji gdzie wklejamy - zapisujemy przy starcie nagrywania
    private var targetAXElement: AXUIElement? = nil
    private var targetAppBundleID: String? = nil
    private var wasTextFieldFocusedAtStart: Bool = false
    private var didPauseMusic: Bool = false
    var hudWindow: NSPanel?
    private var currentTask: Task<Void, Never>?
    
    override init() {
        super.init()
        print("🚀 Inicjalizacja AppController...")
        
        // Pytaj o dostępność od razu po starcie
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !accessEnabled {
            print("⚠️ Brak uprawnień Accessibility na starcie.")
        }
        
        // Załaduj tryby
        let modes = VoiceMode.loadAndMigrateModes()
        self.availableModes = modes
        
        let activeModeID = UserDefaults.standard.string(forKey: "activeModeID") ?? ""
        self.currentMode = modes.first(where: { $0.id.uuidString == activeModeID }) ?? modes.first
        
        // Sprawdzenie uprawnień z opóźnieniem (aby system zdążył je odświeżyć po restarcie)
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
                    print("⚠️ Brak uprawnień do ScreenCaptureKit - degraduję wszystkie opcje pauzowania na wyciszanie.")
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
        
        // Do not init SonorContext here anymore, we will lazy load it when recording starts if the model is downloaded.
        // Also check if model was bundled (fallback) or use downloaded path.
        if case .downloaded = ModelManager.shared.whisperState {
            print("📦 Whisper is downloaded.")
        } else {
            print("⚠️ Whisper model not downloaded yet.")
        }
        
        setupHotkey()
        
        NotificationCenter.default.addObserver(forName: Notification.Name("VoiceModesUpdated"), object: nil, queue: .main) { [weak self] _ in
            self?.reloadModes()
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name("ReleaseWhisperContext"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.sonorContext = nil
            print("🧹 [AppController] Received ReleaseWhisperContext notification. Released sonorContext and closed file handle.")
        }
    }
    
    private func setupHotkey() {
        HotkeyManager.shared.onHotkeyDown = { [weak self] in
            self?.toggleRecording()
        }
        HotkeyManager.shared.onHotkeyUp = { [weak self] in
            guard let self = self else { return }
            if self.isRecording {
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
        
        // If only one mode is functional (e.g. Raw Output when Gemma isn't downloaded),
        // we can't switch to anything else.
        guard functionalModes.count > 1 else {
            print("⚠️ Only one functional assistant available (Gemma not downloaded). Skipping switcher.")
            return
        }
        
        let currentIndex = functionalModes.firstIndex(where: { $0.id == currentMode?.id }) ?? -1
        let nextIndex = (currentIndex + 1) % functionalModes.count
        let nextMode = functionalModes[nextIndex]
        
        changeMode(nextMode)
    }
    
    func changeMode(_ nextMode: VoiceMode) {
        let previousModeName = currentMode?.name ?? "Unknown"
        self.selectMode(nextMode)
        
        // Show status temporarily
        statusText = "Mode: \(nextMode.name)"
        if self.hudWindow?.isVisible == false {
            self.showHUD()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.isRecording {
                if self.statusText.hasPrefix("Mode:") {
                    self.statusText = "Listening..."
                }
            } else {
                if self.statusText.hasPrefix("Mode:") {
                    self.statusText = "Ready"
                    self.hudWindow?.orderOut(nil)
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
            print("⚠️ [AppController] Ignorowanie skrótu - nakładka przetwarza.")
            return
        }
        
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            let modeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
            self.activeHotkeyMode = (modeString == "Hold" || modeString == "Przytrzymanie") ? .hold : .click
            
            guard case .downloaded = ModelManager.shared.whisperState else {
                print("❌ Whisper model not downloaded.")
                self.isRecording = false
                self.openSettings()
                
                DispatchQueue.main.async {
                    ModelManager.shared.showModelsRequiredModal = true
                }
                return
            }
            
            // Zapisz stan popovera ZANIM zaczniemy nagrywać
            wasPopoverOpenBeforeRecording = isPopoverOpen
            
            // KLUCZOWE: Zapisz aktywną aplikację ZANIM cokolwiek zrobimy
            // W tym momencie focus jest jeszcze użytkownika
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                targetAppPID = frontApp.processIdentifier
                targetAppBundleID = frontApp.bundleIdentifier
                targetAXElement = PasteManager.shared.getFocusedAXElement(pid: targetAppPID)
                wasTextFieldFocusedAtStart = PasteManager.shared.isElementTextField(targetAXElement)
                print("📌 Zapamiętano docelową aplikację: \(frontApp.localizedName ?? "?") (PID: \(targetAppPID))")
            }
            
            // Określ tryb na starcie
            let selectedMode: VoiceMode
            if !AuthManager.shared.isLoggedIn {
                selectedMode = VoiceMode.defaults.first!
                self.currentMode = selectedMode
            } else {
                selectedMode = currentMode ?? availableModes.first ?? VoiceMode.defaults.first!
                if self.currentMode?.id != selectedMode.id {
                    self.selectMode(selectedMode)
                }
            }
            
            // Pokaż HUD OD RAZU, zanim zacznie grać dźwięk
            self.isRecording = true
            let behavior = selectedMode.audioBehavior ?? .keep
            if self.sonorContext == nil {
                self.statusText = "Initializing"
            } else if behavior == .pause || behavior == .mute {
                self.statusText = "Preparing..."
            } else {
                self.statusText = "Listening..."
            }
            self.showHUD()
            self.forceFloatingWindow()
            
            // Start recording immediately if already loaded, otherwise apply the 1-second delay for Initialization
            if self.sonorContext == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    Task {
                        let path = ModelManager.shared.whisperModelURL.path
                        if FileManager.default.fileExists(atPath: path) {
                            let context = await Task.detached(priority: .userInitiated) {
                                return SonorContext(modelPath: path)
                            }.value
                            
                            await MainActor.run {
                                self.sonorContext = context
                                self.startRecordingProcess(selectedMode: selectedMode)
                            }
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
            // KLUCZOWE: Dajemy WindowServerowi ułamek sekundy (150ms) na fizyczne narysowanie okna HUD.
            // Bez tego natychmiastowe wywołanie SCShareableContent spauzuje WindowServer przed wyrenderowaniem okna.
            try? await Task.sleep(nanoseconds: 150_000_000)
            
            // 1. Sprawdzenie zaraz po pierwszym opóźnieniu
            let isStillRecording = await MainActor.run { return self.isRecording }
            guard isStillRecording else { return }
            
            let behavior = selectedMode.audioBehavior ?? .keep
            var shouldMuteOrPause = false
            
            if behavior == .pause {
                if #available(macOS 12.3, *) {
                    shouldMuteOrPause = await AudioCaptureManager.shared.checkIsAudioPlaying()
                }
            } else if behavior == .mute {
                // Musimy wejść na MainActor by wywołać synchroniczną metodę
                shouldMuteOrPause = await MainActor.run { return self.isAudioActivelyPlayingPmset() }
            }
            
            // 2. Sprawdzenie przed wykonaniem efektów ubocznych (pauzowanie, dźwięk)
            let isRecordingAfterCheck = await MainActor.run { return self.isRecording }
            guard isRecordingAfterCheck else { return }
            
            await MainActor.run {
                if behavior != .keep {
                    if shouldMuteOrPause {
                        if behavior == .pause {
                            print("🎵 Pauzowanie multimediów (System Media Key)...")
                            self.pauseMultimedia(behavior: .pause)
                        } else if behavior == .mute {
                            print("🎵 Wyciszanie multimediów (Mute System)...")
                            self.pauseMultimedia(behavior: .mute)
                        }
                    } else {
                        print("🔊 [VolumeControl] Urządzenie nie wydaje dźwięku, pomijam akcję.")
                        self.didPauseMusic = false
                    }
                }
                
                Task {
                    guard self.isRecording else { return }
                    // Odtwórz dźwięk w tle (fire-and-forget)
                    Task {
                        await SoundPlayer.shared.playSound(named: "Start")
                    }
                    // Krótkie opóźnienie 200ms, aby dźwięk zdążył ruszyć zanim uruchomimy nagrywanie
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    await MainActor.run {
                        guard self.isRecording else { return }
                        self.startRecording()
                    }
                }
            }
        }
    }
    
    private func startRecording() {
        self.isPaused = false
        // Poproś o dostęp do Dostępności (Accessibility)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            print("⚠️ Brak uprawnień Accessibility. Pokazano prompt systemowy.")
        }
        
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if authStatus == .authorized {
            // Uprawnienia są już nadane! Rozpoczynamy nagrywanie synchronicznie i natychmiast bez asynchronicznego skoku.
            performStartRecording()
        } else {
            AVCaptureDevice.requestAccess(for: AVMediaType.audio) { granted in
                Task { @MainActor in
                    guard granted else {
                        print("⚠️ Brak uprawnień do mikrofonu.")
                        self.statusText = "No microphone permission"
                        self.isRecording = false
                        self.hideHUDAfterDelay()
                        return
                    }
                    self.performStartRecording()
                }
            }
        }
    }
    
    private func performStartRecording() {
        self.isPaused = false
        let modeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
        self.activeHotkeyMode = (modeString == "Hold" || modeString == "Przytrzymanie") ? .hold : .click
        
        print("🎙️ Próba startu nagrywania (asynchronicznie)...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.audioManager.startRecording()
                
                DispatchQueue.main.async {
                    self.isRecording = true
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.statusText = "Listening..."
                    }
                    
                    // Monitorowanie poziomu głośności do UI (.common mode chroni przed zatrzymywaniem przy przeciąganiu)
                    let timer = Timer(timeInterval: 0.05, repeats: true) { timer in
                        Task { @MainActor [weak self] in
                            guard let self = self else {
                                timer.invalidate()
                                return
                            }
                            if self.isRecording {
                                if !self.isPaused {
                                    let level = self.audioManager.audioLevel
                                    self.audioLevel = level
                                    
                                    self.audioLevels.append(max(0.01, level))
                                    if self.audioLevels.count > 40 {
                                        self.audioLevels.removeFirst()
                                    }
                                }
                            } else {
                                withAnimation {
                                    self.audioLevels = Array(repeating: 0.01, count: 40)
                                }
                                timer.invalidate()
                            }
                        }
                    }
                    RunLoop.main.add(timer, forMode: .common)
                }
            } catch {
                DispatchQueue.main.async {
                    print("❌ Błąd mikrofonu: \(error.localizedDescription)")
                    self.statusText = "Microphone error"
                    self.isRecording = false
                    self.hideHUDAfterDelay()
                }
            }
        }
    }
    
    private var settingsWindow: NSWindow?
    private var supportWindow: NSWindow?

    func forceFloatingWindow() {
        // Opóźnienie na uruchomienie UI okna MenuBar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                // Skip settings, support, and HUD windows so they maintain their standard behavior
                if window == self.settingsWindow || window == self.supportWindow || window == self.hudWindow {
                    continue
                }
                
                if window.className.contains("SwiftUI.StatusBarWindow") || window.title.isEmpty || window.isOpaque == false {
                    window.level = .floating
                    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                }
            }
        }
    }

    private func showHUD() {
        if hudWindow == nil {
            let panel = SonorHUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 600),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            // Ustawiamy contentView przed modyfikacją właściwości okna, aby uniknąć resetowania przez AppKit
            panel.contentView = NSHostingView(rootView: CapsuleHUDView(controller: self))
            
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.appearance = NSAppearance(named: .darkAqua)
            
            if let screen = NSScreen.main {
                let defaultX = (screen.frame.width - 350) / 2
                let defaultY: CGFloat = 100
                
                var savedX = UserDefaults.standard.object(forKey: "hudWindowX") as? CGFloat ?? defaultX
                var savedY = UserDefaults.standard.object(forKey: "hudWindowY") as? CGFloat ?? defaultY
                
                // Walidacja czy załadowana pozycja mieści się w granicach aktualnego ekranu
                let screenFrame = screen.visibleFrame
                let leftMargin: CGFloat = 33
                let rightMargin: CGFloat = 350 - leftMargin
                let visibleHeight: CGFloat = 88
                
                let minXBound = screenFrame.minX - leftMargin
                let maxXBound = screenFrame.maxX - rightMargin
                let minYBound = screenFrame.minY
                let maxYBound = screenFrame.maxY - visibleHeight
                
                savedX = max(minXBound, min(savedX, maxXBound))
                savedY = max(minYBound, min(savedY, maxYBound))
                
                panel.setFrameOrigin(NSPoint(x: savedX, y: savedY))
            }
            
            self.hudWindow = panel
        }
        
        // Zawsze wymuszamy właściwości przezroczystości podczas każdego wyświetlenia HUD,
        // aby upewnić się, że AppKit w żadnym wypadku nie przywróci domyślnego (np. jasnego) tła.
        hudWindow?.backgroundColor = .clear
        hudWindow?.isOpaque = false
        hudWindow?.hasShadow = false
        
        hudWindow?.makeKeyAndOrderFront(nil)
    }
    
    func togglePause() {
        self.isPaused.toggle()
        print("⏸️ [Pause] Przełączono pauzę na: \(self.isPaused)")
    }

    func openSettings() {
        if let window = settingsWindow {
            // Wymuszamy styl dla istniejącego okna, jeśli już było stworzone
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.makeKeyAndOrderFront(nil)
            
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
            // Pokaż okno ze wsparciem dla twórcy
            self.openSupportWindow()
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.minSize = NSSize(width: 1000, height: 600)
        window.center()
        window.contentView = NSHostingView(rootView: MainAppView())
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = nil
        
        // Pokazujemy standardowe przyciski
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        
        window.isMovableByWindowBackground = false
        
        self.settingsWindow = window
        
        // Obserwujemy zamknięcie okna, aby przywrócić tryb akcesoriów (brak w Docku) jeśli to konieczne
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateActivationPolicy()
            }
        }
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        // Pokaż okno ze wsparciem dla twórcy
        self.openSupportWindow()
    }
    
    func openSupportWindow() {
        if let window = supportWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Sonor - Wesprzyj Twórcę"
        window.center()
        
        // Hide standard window controls we don't need
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        window.contentView = NSHostingView(rootView: SupportView(onClose: { [weak self] in
            self?.supportWindow?.close()
        }))
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        
        self.supportWindow = window
        
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                self?.supportWindow = nil
                self?.updateActivationPolicy()
            }
        }
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    private func updateActivationPolicy() {
        let isSettingsVisible = settingsWindow?.isVisible == true
        let isSupportVisible = supportWindow?.isVisible == true
        
        if !isSettingsVisible && !isSupportVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    func selectMode(_ mode: VoiceMode) {
        self.currentMode = mode
        UserDefaults.standard.set(mode.id.uuidString, forKey: "activeModeID")
    }
    
    func cancelRecording() {
        guard isRecording || isCurrentlyProcessing else { return }
        if statusText == "Initializing" {
            print("⚠️ [AppController] Ignorowanie anulowania - faza inicjalizacji.")
            return
        }
        print("🛑 Anulowano nagrywanie.")
        isRecording = false
        self.isPaused = false
        statusText = "Cancelled"
        
        let taskToCancel = currentTask
        currentTask = nil
        taskToCancel?.cancel()
        
        Task.detached {
            _ = await self.audioManager.stopRecording()
        }
        
        if self.didPauseMusic {
            self.resumeMultimedia()
        }
        
        withAnimation {
            self.audioLevels = Array(repeating: 0.01, count: 40)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !self.isRecording && self.statusText == "Cancelled" {
                self.statusText = "Ready"
                self.hudWindow?.orderOut(nil)
            }
        }
    }
    

    private func hideHUDAfterDelay() {
        Task {
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !self.isRecording {
                        self.statusText = "Ready"
                        self.hudWindow?.orderOut(nil)
                    }
                }
            }
        }
    }
    
    private func stopRecordingAndTranscribe() {
        guard isRecording else {
            print("⚠️ [AppController] Ignorowanie stopRecordingAndTranscribe - aplikacja nie jest w trakcie nagrywania (prawdopodobnie podwójne wywołanie).")
            return
        }
        
        let wasPaused = self.isPaused
        self.isPaused = false
        isRecording = false
        statusText = "Processing"
        
        // Zależność widoczności po zakończeniu nagrywania:
        if !wasPopoverOpenBeforeRecording {
            isPopoverOpen = false
        }
        

        
        let samples = audioManager.stopRecording()
        
        // Natychmiastowe przywrócenie dźwięku po zakończeniu nagrywania
        if self.didPauseMusic {
            self.resumeMultimedia()
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
            // Krok 0: sprawdzenie długości audio (min. 300ms = 4800 próbek)
            guard samples.count >= 4800 else {
                print("⚠️ Zbyt krótkie nagranie (\(samples.count) próbek). Pomijam transkrypcję.")
                await MainActor.run { 
                    self.statusText = "No text recognized." 
                }
                await SoundPlayer.shared.playSound(named: "Error")
                self.hideHUDAfterDelay()
                return
            }
            
            // Krok 1: transkrypcja Sonor
            let transcribedText = await context.transcribe(audioSamples: samples)
            
            if Task.isCancelled {
                print("Task cancelled after transcription.")
                self.hideHUDAfterDelay()
                return
            }
            
            let rawText = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            print("=== [SONOR OUPUT] ===")
            print(rawText)
            print("=======================")
            
            guard !rawText.isEmpty else {
                await MainActor.run { 
                    self.statusText = "No text recognized." 
                }
                await SoundPlayer.shared.playSound(named: "Error")
                self.hideHUDAfterDelay()
                return
            }
            
            // Record statistics
            let duration = Double(samples.count) / 16000.0
            self.recordUsage(duration: duration, text: rawText)
            
            // Apply dictionary and snippets
            let correctedText = self.applyCorrections(to: rawText)
            print("=== [CORRECTED OUTPUT] ===")
            print(correctedText)
            print("==========================")
            
            // Krok 2: czyszczenie przez LLM
            let selectedMode = self.currentMode ?? VoiceMode.defaults.first!
            
            var pid = self.targetAppPID
            if selectedMode.pasteTiming == "end" {
                await MainActor.run {
                    if let frontApp = NSWorkspace.shared.frontmostApplication,
                       frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                        pid = frontApp.processIdentifier
                    }
                }
            }
            
            var willPaste = true
            if selectedMode.fallbackToClipboard == true {
                if selectedMode.pasteTiming == "start" {
                    willPaste = self.wasTextFieldFocusedAtStart
                } else {
                    willPaste = PasteManager.shared.isTextFieldFocused(pid: pid)
                }
            }

            print("🎯 Wybrany tryb: \(selectedMode.name)")

            let isPremium = await MainActor.run { AuthManager.shared.isLoggedIn && AuthManager.shared.accountTier == "premium" }
            let shouldRunLLM = !selectedMode.prompt.isEmpty && isPremium

            if !shouldRunLLM {
                await MainActor.run { self.statusText = "Done!" }
                print("=== [RAW OUTPUT SELECTED (or Free User)] ===")
                
                // Zapisujemy do pamięci RAM na wątku głównym
                await MainActor.run {
                    MessageMemoryManager.shared.saveMessage(correctedText)
                }
                
                if willPaste {
                    DispatchQueue.global(qos: .userInteractive).async {
                        let forceFocusElement = (selectedMode.pasteTiming == "start") ? self.targetAXElement : nil
                        PasteManager.shared.typeTextDirectly(text: correctedText, targetPID: pid, forceFocusElement: forceFocusElement)
                        Task { @MainActor in
                            self.startAutoLearnTracking(targetPID: pid, originalText: correctedText)
                        }
                    }
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(correctedText, forType: .string)
                    print("📋 Skopiowano do schowka (brak pola tekstowego)")
                    Task { await SoundPlayer.shared.playSound(named: "Error") }
                }
            } else {
                if Task.isCancelled {
                    self.hideHUDAfterDelay()
                    return
                }
                if !LLMManager.shared.isReady {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.statusText = "Initializing"
                        }
                    }
                    await LLMManager.shared.ensureModelWarmed()
                }
                if Task.isCancelled {
                    self.hideHUDAfterDelay()
                    return
                }
                
                let statusLabel: String
                if selectedMode.name == "Text Smoothing" {
                    statusLabel = "Text Smoothing"
                } else if selectedMode.name == "Formal Email" {
                    statusLabel = "Formal Email"
                } else {
                    statusLabel = "Modifying"
                }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.statusText = statusLabel
                    }
                }
                
                print("=== [LLM STREAMING STARTED] ===")
                
                let systemPrompt: String
                if selectedMode.assistantType == "edit" {
                    let activeAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Application"
                    let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
                    
                    var contextInfo = ""
                    if selectedMode.passAppName ?? true {
                        contextInfo += "=== ACTIVE APPLICATION ===\n\(activeAppName)\n\n"
                    }
                    if (selectedMode.passCopiedText ?? true) && !clipboardText.isEmpty {
                        contextInfo += "=== COPIED TEXT (CLIPBOARD) ===\n\(clipboardText)\n\n"
                    }
                    
                    // Language
                    let langInstruction: String
                    if let lang = selectedMode.language, lang != "auto" {
                        let langMap: [String: String] = [
                            "pl": "Polish", "en": "English", "de": "German", "es": "Spanish",
                            "fr": "French", "it": "Italian", "pt": "Portuguese", "nl": "Dutch",
                            "ru": "Russian", "uk": "Ukrainian", "cs": "Czech", "sk": "Slovak",
                            "sv": "Swedish", "no": "Norwegian", "da": "Danish", "fi": "Finnish",
                            "zh": "Chinese", "ja": "Japanese", "ko": "Korean", "ar": "Arabic",
                            "tr": "Turkish", "hi": "Hindi", "vi": "Vietnamese", "th": "Thai",
                            "el": "Greek", "pt-BR": "Portuguese (Brazilian)", "he": "Hebrew",
                            "ro": "Romanian", "hu": "Hungarian"
                        ]
                        let langName = langMap[lang] ?? lang
                        langInstruction = "Your response MUST be in language: \(langName)."
                    } else {
                        langInstruction = """
                        Language priority (Automatic Mode):
                        - By default, if you edit 'Copied Text', preserve the original language of that text.
                        - HOWEVER, if the user explicitly requests a language change in their instruction (e.g., "translate to Polish", "write this in English", "change language to..."), you MUST fulfill this request and change the language to the requested one. The user's instruction has the highest priority!
                        - If the user is creating new content, use the language in which the user is speaking (the instruction).
                        """
                    }
                    
                    systemPrompt = """
                    \(selectedMode.prompt)
                    
                    Use the LLM to edit and create content based on the provided context.
                    
                    \(contextInfo.isEmpty ? "" : "Context:\n" + contextInfo)
                    
                    The user will provide instructions in the 'Text' section below. Generate the output based on this instruction and context.
                    
                    \(langInstruction)
                    
                    IMPORTANT CONTEXT RULES:
                    1) Just because you received 'Copied Text' as context does not mean you MUST use it! Sense the user's intent.
                    2) If the user says "write a message to...", "create...", "generate..." and does not refer to the passed text, ignore the context and create new content.
                    3) If the user says "edit this text", "change this", "fix this" and does not provide other text, they refer to the 'Copied Text'.
                    4) Be attentive: the user might dictate text and immediately correct it in a single statement (e.g., "Write X... wait, sorry, change X to Y"). In this case, they refer to the text they just dictated, not to the context.
                    5) NEVER refuse to execute a command. Even if you think the text is too short, lacks content, or there is no point in commenting/summarizing it – execute the command to the best of your ability based on what you have.
                    6) Return ONLY and EXCLUSIVELY the final result. No introductions, no explanations, no 'I am not sure', no questions. If you hesitate, choose one option and return it. Your response will be directly pasted for the user, so it cannot contain anything other than the target text.
                    
                    IMPORTANT SAFEGUARD: If there is no command or order in the 'Text' section OR if you lack the context to execute the command, DO NOT make anything up or ask questions. In this case, simply rewrite the user's text with minimal corrections (remove stutters like uh, um, oh) and return it.
                    
                    Respond ONLY with the generated content (or corrected text), without any comments and without any introductory text.
                    """
                } else {
                    systemPrompt = selectedMode.prompt
                }
                
                if Task.isCancelled {
                    self.hideHUDAfterDelay()
                    return
                }
                if willPaste {
                    // Aktywacja i ustawienie focusu przed startem strumieniowania
                    if let targetApp = NSRunningApplication(processIdentifier: pid) {
                        targetApp.activate(options: .activateIgnoringOtherApps)
                        
                        var attempts = 0
                        while !targetApp.isActive && attempts < 30 {
                            try? await Task.sleep(nanoseconds: 50_000_000)
                            attempts += 1
                        }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    if selectedMode.pasteTiming == "start", let element = self.targetAXElement {
                        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                }
                
                var didStartStreaming = false
                var fullGeneratedText = ""
                _ = await LLMManager.shared.cleanStream(text: correctedText, systemPrompt: systemPrompt) { token in
                    fullGeneratedText += token
                    if !didStartStreaming {
                        didStartStreaming = true
                        Task { @MainActor in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                self.statusText = "Streaming"
                            }
                        }
                    }
                    print(token, terminator: "")
                    if willPaste {
                        DispatchQueue.global(qos: .userInteractive).async {
                            PasteManager.shared.typeTextToken(token: token, targetPID: pid)
                        }
                    }
                }
                print("\n=== [LLM STREAMING FINISHED] ===")
                
                if Task.isCancelled {
                    self.hideHUDAfterDelay()
                    return
                }
                
                if !willPaste {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullGeneratedText, forType: .string)
                    print("📋 Skopiowano do schowka z LLM (brak pola tekstowego)")
                    Task { await SoundPlayer.shared.playSound(named: "Error") }
                }
                
                // Zapisujemy do pamięci RAM na wątku głównym
                await MainActor.run {
                    MessageMemoryManager.shared.saveMessage(fullGeneratedText)
                    if willPaste {
                        self.startAutoLearnTracking(targetPID: pid, originalText: fullGeneratedText)
                    }
                }
            }

            await MainActor.run {
                self.statusText = "Done!"
            }
            
            if willPaste {
                await SoundPlayer.shared.playSound(named: "End")
            }
            
            self.hideHUDAfterDelay()
        }
    }
    
    nonisolated private func isAudioActivelyPlayingPmset() -> Bool {
        print("🔊 [AudioCheck] Sprawdzanie PMSET (10s delay)...")
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-g", "assertions"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("PreventUserIdleDisplaySleep") || line.contains("PreventUserIdleSystemSleep") {
                    if line.contains("coreaudiod") || line.contains("powerd") || line.contains("WindowServer") || line.contains("Sonor") {
                        continue
                    }
                    if line.contains("Audio Playback") || line.contains("WebKit Media Playback") || line.contains("Spotify") {
                        print("🔊 [AudioCheck] Znalazłem asercję audio w pmset: \(line)")
                        return true
                    }
                }
            }
        }
        return false
    }

    private func postMediaKeyEvent(key: Int32) {
        print("🔊 [VolumeControl] Wysyłanie zdarzenia klawiatury dla klawisza: \(key)")
        func doKey(down: Bool) {
            let flags = NSEvent.ModifierFlags.init(rawValue: (down ? 0xa00 : 0xb00))
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
            
            let ev = NSEvent.otherEvent(with: .systemDefined,
                                        location: NSPoint(x: 0, y: 0),
                                        modifierFlags: flags,
                                        timestamp: 0,
                                        windowNumber: 0,
                                        context: nil,
                                        subtype: 8,
                                        data1: data1,
                                        data2: -1)
            
            let cgEvent = ev?.cgEvent
            cgEvent?.post(tap: .cghidEventTap)
        }
        doKey(down: true)
        doKey(down: false)
    }

    private var activeAudioBehavior: AudioBehavior? = nil
    
    private func pauseMultimedia(behavior: AudioBehavior) {
        self.activeAudioBehavior = behavior
        self.didPauseMusic = true
        
        if behavior == .pause {
            print("🔊 [VolumeControl] Pauzowanie multimediów (System Media Key)...")
            let NX_KEYTYPE_PLAY: Int32 = 16
            postMediaKeyEvent(key: NX_KEYTYPE_PLAY)
        } else if behavior == .mute {
            print("🔊 [VolumeControl] Wyciszanie systemu (AppleScript)...")
            runAppleScript("set volume with output muted")
        }
    }
    
    private func resumeMultimedia() {
        if !self.didPauseMusic { return }
        self.didPauseMusic = false
        
        let behavior = self.activeAudioBehavior ?? .mute
        self.activeAudioBehavior = nil
        
        if behavior == .pause {
            print("🔊 [VolumeControl] Wznawianie multimediów (System Media Key)...")
            let NX_KEYTYPE_PLAY: Int32 = 16
            postMediaKeyEvent(key: NX_KEYTYPE_PLAY)
        } else if behavior == .mute {
            print("🔊 [VolumeControl] Odtwarzanie systemu (Unmute AppleScript)...")
            runAppleScript("set volume without output muted")
        }
    }
    
    private func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error = error {
                print("⚠️ AppleScript error: \(error)")
            }
        }
    }
    
    private func parseDynamicVariables(in text: String) -> String {
        var result = text
        
        if result.contains("{{clipboard}}") {
            let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{{clipboard}}", with: clipboardText)
        }
        
        if result.contains("{{date}}") {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            result = result.replacingOccurrences(of: "{{date}}", with: formatter.string(from: Date()))
        }
        
        if result.contains("{{time}}") {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            result = result.replacingOccurrences(of: "{{time}}", with: formatter.string(from: Date()))
        }
        
        if result.contains("{{active_app}}") {
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            result = result.replacingOccurrences(of: "{{active_app}}", with: appName)
        }
        
        if result.contains("{{day_of_week}}") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: LocalizationManager.shared.appLanguage)
            formatter.dateFormat = "EEEE"
            let dayName = formatter.string(from: Date())
            result = result.replacingOccurrences(of: "{{day_of_week}}", with: dayName)
        }
        
        return result
    }
    
    private func applyCorrections(to text: String) -> String {
        // Zwróć oryginalny tekst jeśli użytkownik nie jest premium
        guard AuthManager.shared.isLoggedIn else { return text }
        
        var processedText = text
        
        // 1. Słownik (Phonetic Corrections)
        let dictionary = UserDefaults.standard.dictionary(forKey: "dictionaryEntries") as? [String: String] ?? [:]
        for (wrong, correct) in dictionary {
            processedText = processedText.replacingOccurrences(of: wrong, with: correct, options: .caseInsensitive)
        }
        
        // 2. Snippety (Skróty tekstowe)
        let snippets = UserDefaults.standard.dictionary(forKey: "snippetsEntries") as? [String: String] ?? [:]
        for (shortcut, expansion) in snippets {
            let parsedExpansion = parseDynamicVariables(in: expansion)
            processedText = processedText.replacingOccurrences(of: shortcut, with: parsedExpansion, options: .caseInsensitive)
        }
        
        return processedText
    }
    
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func recordUsage(duration: Double, text: String) {
        // Pomijaj dodawanie statystyk w trybie incognito
        if UserDefaults.standard.bool(forKey: "isIncognitoMode") {
            print("🕵️‍♂️ Tryb Incognito: Statystyki NIE zostały zaktualizowane.")
            return
        }
        
        let wordCount = text.split(separator: " ").count
        let stat = UsageStat(id: UUID(), date: Date(), duration: duration, wordCount: wordCount)
        
        var stats = getStats()
        stats.append(stat)
        
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: "usageStats")
            NotificationCenter.default.post(name: Notification.Name("UsageStatsUpdated"), object: nil)
        }
    }
    
    func getStats() -> [UsageStat] {
        if let data = UserDefaults.standard.data(forKey: "usageStats"),
           let stats = try? JSONDecoder().decode([UsageStat].self, from: data) {
            return stats
        }
        return []
    }
    
    // MARK: - Auto-Learn Dictionary Methods
    
    func getFocusedElementText(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusResult == .success, let element = focusedElement else { return nil }
        let axElement = element as! AXUIElement
        var currentValue: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValue)
        guard valueResult == .success else { return nil }
        return currentValue as? String
    }
    
    func startAutoLearnTracking(targetPID: pid_t, originalText: String) {
        guard UserDefaults.standard.bool(forKey: "autoLearnDictionary") else { return }
        
        Task {
            // Daj czas na wklejenie/wpisanie tekstu
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 sekunda
            
            // Pobierz stan początkowy pola tekstowego
            guard let initialText = await MainActor.run(body: { self.getFocusedElementText(pid: targetPID) }),
                  !initialText.isEmpty else {
                print("🕵️‍♂️ [AutoLearn] Nie udało się pobrać tekstu początkowego pola")
                return
            }
            
            print("🕵️‍♂️ [AutoLearn] Rozpoczęto śledzenie. Tekst początkowy: \"\(initialText)\"")
            
            var lastText = initialText
            
            // Pętla śledzenia przez 10 sekund, sprawdzanie co 3 sekundy
            for i in 1...3 {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 sekundy
                
                guard let currentText = await MainActor.run(body: { self.getFocusedElementText(pid: targetPID) }) else {
                    continue
                }
                
                if currentText != lastText {
                    print("🕵️‍♂️ [AutoLearn] Wykryto zmianę w sekundy \(i*3): \"\(currentText)\"")
                    
                    // Porównaj initialText z currentText
                    let corrections = self.detectWordCorrections(from: initialText, to: currentText)
                    if !corrections.isEmpty {
                        print("🕵️‍♂️ [AutoLearn] Wykryto poprawki słownika: \(corrections)")
                        
                        // Dodaj do słownika i pokaż powiadomienie!
                        await MainActor.run {
                            self.addDictionaryEntriesAndNotify(corrections: corrections)
                        }
                    }
                    
                    lastText = currentText
                }
            }
            
            print("🕵️‍♂️ [AutoLearn] Zakończono śledzenie.")
        }
    }
    
    func detectWordCorrections(from initial: String, to current: String) -> [(wrong: String, correct: String)] {
        let initialWords = initial.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let currentWords = current.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        guard initialWords != currentWords else { return [] }
        
        let diff = currentWords.difference(from: initialWords)
        
        var removes: [(index: Int, word: String)] = []
        var inserts: [(index: Int, word: String)] = []
        
        for change in diff {
            switch change {
            case .remove(let offset, let element, _):
                removes.append((offset, element))
            case .insert(let offset, let element, _):
                inserts.append((offset, element))
            }
        }
        
        removes.sort { $0.index < $1.index }
        inserts.sort { $0.index < $1.index }
        
        var corrections: [(wrong: String, correct: String)] = []
        
        if removes.count <= 2 && inserts.count <= 2 && !removes.isEmpty && !inserts.isEmpty {
            let wrong = removes.map { $0.word }.joined(separator: " ")
            let correct = inserts.map { $0.word }.joined(separator: " ")
            corrections.append((wrong: wrong, correct: correct))
        }
        
        return corrections
    }

    
    func addDictionaryEntriesAndNotify(corrections: [(wrong: String, correct: String)]) {
        var newLearnedEntries: [LearnedEntry] = []
        var dictionary = UserDefaults.standard.dictionary(forKey: "dictionaryEntries") as? [String: String] ?? [:]
        
        let existingNotification = self.activeDictionaryNotification
        var accumulatedLearnedEntries = existingNotification?.learnedEntries ?? []
        
        for correction in corrections {
            let wrong = correction.wrong
            let correct = correction.correct
            
            // Sprawdź czy to słowo już poprawialiśmy w TEJ sesji
            let originalPrev: String?
            if let existingIndex = accumulatedLearnedEntries.firstIndex(where: { $0.wrong == wrong }) {
                // Zachowaj pierwotną wartość sprzed całej sesji
                originalPrev = accumulatedLearnedEntries[existingIndex].previousValue
            } else {
                // Nowe słowo w tej sesji, weź z aktualnego stanu słownika
                originalPrev = dictionary[wrong]
            }
            
            // Zapisujemy w słowniku
            dictionary[wrong] = correct
            
            let entry = LearnedEntry(wrong: wrong, correct: correct, previousValue: originalPrev)
            newLearnedEntries.append(entry)
            
            // Zaktualizuj lub dodaj do skumulowanej listy
            if let existingIndex = accumulatedLearnedEntries.firstIndex(where: { $0.wrong == wrong }) {
                accumulatedLearnedEntries[existingIndex] = entry
            } else {
                accumulatedLearnedEntries.append(entry)
            }
        }
        
        // Zapisz słownik
        UserDefaults.standard.set(dictionary, forKey: "dictionaryEntries")
        
        // Powiadom widoki (np. ustawienia słownika)
        NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
        
        // Pokaż powiadomienie HUD z najnowszą poprawką
        if let lastEntry = newLearnedEntries.last {
            let nextWrong = lastEntry.wrong
            let nextCorrect = lastEntry.correct
            
            self.activeDictionaryNotification = DictionaryNotification(
                wrong: nextWrong,
                correct: nextCorrect,
                learnedEntries: accumulatedLearnedEntries
            )
            self.showHUD()
            
            // Automatycznie schowaj po 5 sekundach
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    // Schowaj tylko, jeśli to powiadomienie jest nadal aktywne i nie uległo zmianie
                    if self.activeDictionaryNotification?.wrong == nextWrong && self.activeDictionaryNotification?.correct == nextCorrect {
                        self.hideDictionaryNotification()
                    }
                }
            }
        }
    }
    
    func undoDictionaryEntry() {
        guard let notification = activeDictionaryNotification else { return }
        
        var dictionary = UserDefaults.standard.dictionary(forKey: "dictionaryEntries") as? [String: String] ?? [:]
        
        for entry in notification.learnedEntries {
            if let prev = entry.previousValue {
                dictionary[entry.wrong] = prev
            } else {
                dictionary.removeValue(forKey: entry.wrong)
            }
        }
        
        UserDefaults.standard.set(dictionary, forKey: "dictionaryEntries")
        NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
        
        self.hideDictionaryNotification()
    }
    
    func hideDictionaryNotification() {
        withAnimation(.easeOut(duration: 0.5)) {
            self.activeDictionaryNotification = nil
        }
        
        // Jeśli nie nagrywamy, zamknij okno HUD po opóźnieniu
        if !self.isRecording {
            self.hideHUDAfterDelay()
        }
    }
}

struct UsageStat: Codable, Identifiable {
    let id: UUID
    let date: Date
    let duration: Double // seconds
    let wordCount: Int
}

class SonorHUDPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // Ignorujemy domyślne systemowe ograniczanie okna przez AppKit.
        // Pozwala to na wyjeżdżanie niewidocznej (przezroczystej) części okna ponad ekran,
        // dzięki czemu widoczna część u dołu może dotrzeć do samej górnej krawędzi (pod pasek menu).
        return frameRect
    }
}



import ScreenCaptureKit
import AVFoundation

@available(macOS 12.3, *)
class AudioCaptureManager: NSObject, SCStreamOutput {
    static let shared = AudioCaptureManager()
    
    private var stream: SCStream?
    private var isPlaying = false
    private let queue = DispatchQueue(label: "com.sonor.AudioCaptureQueue")
    
    private override init() {
        super.init()
    }
    
    func checkIsAudioPlaying(timeout: TimeInterval = 0.5) async -> Bool {
        guard CGPreflightScreenCaptureAccess() else {
            print("🔊 [AudioCaptureManager] Brak dostępu do nagrywania ekranu.")
            return false
        }
        
        self.isPlaying = false
        
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { return false }
            
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            
            self.stream = stream
            try await stream.startCapture()
            
            // Zamiast blokować wątek semaforem, usypiamy asynchronicznie task na `timeout`
            let start = Date()
            while Date().timeIntervalSince(start) < timeout {
                if self.isPlaying {
                    break
                }
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms interval
            }
            
            let result = self.isPlaying
            
            try? await stream.stopCapture()
            self.stream = nil
            
            if result {
                print("🔊 [AudioCaptureManager] Wykryto dźwięk!")
                return true
            } else {
                print("🔊 [AudioCaptureManager] Cisza.")
                return false
            }
        } catch {
            print("🔊 [AudioCaptureManager] Błąd SCStream: \(error)")
            self.stream = nil
            return false
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        if isBufferActive(sampleBuffer) {
            self.isPlaying = true
        }
    }
    
    private func isBufferActive(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return false }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return false }
        
        var bytes = [Int16](repeating: 0, count: length / MemoryLayout<Int16>.stride)
        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &bytes)
        
        for sample in bytes {
            if abs(sample) > 50 {
                return true
            }
        }
        return false
    }
}
