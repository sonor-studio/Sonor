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
        return !isRecording && !nonProcessingStatuses.contains(statusText)
    }
    
    @Published var audioLevel: Float = 0.0
    @Published var audioLevels: [Float] = Array(repeating: 0.01, count: 40)
    @Published var availableModes: [VoiceMode] = []
    @Published var currentMode: VoiceMode?
    @Published var isPaused = false {
        didSet {
            audioManager.isPaused = isPaused
        }
    }
    
    private let audioManager = AudioManager()
    private var sonorContext: SonorContext?
    private var targetAppPID: pid_t = 0  // PID aplikacji gdzie wklejamy - zapisujemy przy starcie nagrywania
    private var targetAppBundleID: String? = nil
    private var didPauseMusic: Bool = false
    var hudWindow: NSPanel?
    private var pausedApps: [String] = []
    private var currentTask: Task<Void, Never>?
    private var modeBeforeAutomation: VoiceMode?
    
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
        HotkeyManager.shared.startListening()
    }
    
    func reloadModes() {
        let modes = VoiceMode.loadAndMigrateModes()
        self.availableModes = modes
        
        let activeModeID = UserDefaults.standard.string(forKey: "activeModeID") ?? ""
        self.currentMode = modes.first(where: { $0.id.uuidString == activeModeID }) ?? modes.first
    }
    
    func toggleRecording() {
        if isCurrentlyProcessing {
            print("⚠️ [AppController] Ignorowanie skrótu - trwa przetwarzanie poprzedniego tekstu (status: \(statusText)).")
            return
        }
        
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
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
                print("📌 Zapamiętano docelową aplikację: \(frontApp.localizedName ?? "?") (PID: \(targetAppPID))")

            }
            
            // Określ tryb na starcie
            let selectedMode: VoiceMode
            if !AuthManager.shared.isLoggedIn {
                // Użytkownicy darmowi mogą korzystać tylko ze zwykłego outputu o domyślnych ustawieniach
                selectedMode = VoiceMode.defaults.first!
                self.currentMode = selectedMode
                modeBeforeAutomation = nil
            } else {
                if let bundleID = self.targetAppBundleID,
                   let autoMode = availableModes.first(where: { $0.boundAppBundleIDs.contains(bundleID) }) {
                    selectedMode = autoMode
                    modeBeforeAutomation = currentMode // Zapisz poprzedni tryb
                    print("🤖 Automatycznie wybrano tryb dla aplikacji \(bundleID): \(selectedMode.name)")
                } else {
                    selectedMode = currentMode ?? availableModes.first ?? VoiceMode.defaults.first!
                    modeBeforeAutomation = nil // Brak automatyzacji
                }
                self.currentMode = selectedMode // Aktualizuj UI
            }
            
            // Pokaż HUD OD RAZU, zanim zacznie grać dźwięk
            self.isRecording = true
            self.statusText = self.sonorContext == nil ? "Inicjalizacja" : "Listening..."
            self.showHUD()
            self.forceFloatingWindow()
            
            Task {
                if self.sonorContext == nil {
                    let path = ModelManager.shared.whisperModelURL.path
                    if FileManager.default.fileExists(atPath: path) {
                        let context = await Task.detached(priority: .userInitiated) {
                            return SonorContext(modelPath: path)
                        }.value
                        
                        await MainActor.run {
                            self.sonorContext = context
                            self.statusText = "Listening..."
                        }
                    }
                }
                
                await MainActor.run {
                    self.startRecordingProcess(selectedMode: selectedMode)
                }
            }
        }
    }
    
    private func startRecordingProcess(selectedMode: VoiceMode) {
        // Pauzowanie muzyki jeśli wymagane
        if selectedMode.pauseMusic {
            print("🎵 Sprawdzanie i pauzowanie multimediów (Native)...")
            Task {
                // Odtwórz dźwięk w tle (fire-and-forget)
                Task {
                    await SoundPlayer.shared.playSound(named: "Start")
                }
                // Krótkie opóźnienie 200ms, aby dźwięk zdążył ruszyć zanim wyciszymy system
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    guard self.isRecording else { return }
                    self.pauseMultimedia {
                        self.startRecording()
                    }
                }
            }
        } else {
            self.didPauseMusic = false
            Task {
                // Odtwórz dźwięk w tle (fire-and-forget)
                Task {
                    await SoundPlayer.shared.playSound(named: "Start")
                }
            }
            self.startRecording()
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
        do {
            print("🎙️ Próba startu nagrywania...")
            try self.audioManager.startRecording()
            self.isRecording = true
            self.statusText = "Listening..."
            
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
        } catch {
            print("❌ Błąd mikrofonu: \(error.localizedDescription)")
            self.statusText = "Microphone error"
            self.isRecording = false
            self.hideHUDAfterDelay()
        }
    }
    
    private var settingsWindow: NSWindow?

    func forceFloatingWindow() {
        // Opóźnienie na uruchomienie UI okna MenuBar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
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
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Sonor"
        window.minSize = NSSize(width: 1000, height: 600)
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
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
        
        // Obserwujemy zamknięcie okna, aby przywrócić tryb akcesoriów (brak w Docku)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            NSApp.setActivationPolicy(.accessory)
        }
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    func selectMode(_ mode: VoiceMode) {
        self.currentMode = mode
        UserDefaults.standard.set(mode.id.uuidString, forKey: "activeModeID")
    }
    
    func cancelRecording() {
        isRecording = false
        statusText = "Cancelled"
        
        restoreModeIfNeeded()
        
        currentTask?.cancel()
        currentTask = nil
        
        _ = audioManager.stopRecording()
        
        if self.didPauseMusic {
            self.resumeMultimedia()
            self.didPauseMusic = false
        }
        
        withAnimation {
            self.audioLevels = Array(repeating: 0.01, count: 40)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.statusText = "Ready"
            self.hudWindow?.orderOut(nil)
        }
    }
    
    @MainActor
    private func restoreModeIfNeeded() {
        if let previousMode = modeBeforeAutomation {
            self.currentMode = previousMode
            modeBeforeAutomation = nil
            print("⏪ Przywrócono tryb sprzed automatyzacji: \(previousMode.name)")
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
            self.didPauseMusic = false
        }
        
        currentTask = Task {
            guard let context = sonorContext else {
                await MainActor.run { 
                    self.statusText = "Error: Missing model" 
                    self.restoreModeIfNeeded()
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
                    self.restoreModeIfNeeded()
                }
                await SoundPlayer.shared.playSound(named: "Error")
                self.hideHUDAfterDelay()
                return
            }
            
            // Krok 1: transkrypcja Sonor
            let transcribedText = await context.transcribe(audioSamples: samples)
            
            if Task.isCancelled {
                print("Task cancelled after transcription.")
                await MainActor.run { 
                    self.restoreModeIfNeeded() 
                }
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
                    self.restoreModeIfNeeded()
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
            
            let pid = self.targetAppPID

            print("🎯 Wybrany tryb: \(selectedMode.name)")

            let isPremium = await MainActor.run { AuthManager.shared.isLoggedIn }
            let shouldRunLLM = !selectedMode.prompt.isEmpty && isPremium

            if !shouldRunLLM {
                await MainActor.run { self.statusText = "Done!" }
                print("=== [RAW OUTPUT SELECTED (or Free User)] ===")
                
                // Zapisujemy do pamięci RAM na wątku głównym
                await MainActor.run {
                    MessageMemoryManager.shared.saveMessage(correctedText)
                }
                
                DispatchQueue.global(qos: .userInteractive).async {
                    PasteManager.shared.typeTextDirectly(text: correctedText, targetPID: pid)
                    Task { @MainActor in
                        self.startAutoLearnTracking(targetPID: pid, originalText: correctedText)
                    }
                }
            } else {
                if !LLMManager.shared.isReady {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.statusText = "Initializing"
                        }
                    }
                    await LLMManager.shared.ensureModelWarmed()
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
                    DispatchQueue.global(qos: .userInteractive).async {
                        PasteManager.shared.typeTextToken(token: token, targetPID: pid)
                    }
                }
                print("\n=== [LLM STREAMING FINISHED] ===")
                
                // Zapisujemy do pamięci RAM na wątku głównym
                await MainActor.run {
                    MessageMemoryManager.shared.saveMessage(fullGeneratedText)
                    self.startAutoLearnTracking(targetPID: pid, originalText: fullGeneratedText)
                }
            }

            await MainActor.run {
                self.statusText = "Done!"
                self.restoreModeIfNeeded()
            }
            
            await SoundPlayer.shared.playSound(named: "End")
            
            self.hideHUDAfterDelay()
        }
    }
    
    private func pauseMultimedia(completion: @escaping () -> Void) {
        print("🔊 [VolumeControl] Wyciszanie systemu...")
        runAppleScript("set volume with output muted")
        self.didPauseMusic = true
        completion()
    }
    
    private func resumeMultimedia() {
        if !self.didPauseMusic {
            return
        }
        
        print("🔊 [VolumeControl] Przywracanie dźwięku...")
        runAppleScript("set volume without output muted")
        self.didPauseMusic = false
        self.pausedApps = []
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
            processedText = processedText.replacingOccurrences(of: shortcut, with: expansion, options: .caseInsensitive)
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
        // Rozbij na słowa
        let initialWords = initial.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let currentWords = current.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        guard initialWords != currentWords else { return [] }
        
        let m = initialWords.count
        let n = currentWords.count
        
        // Bezpieczne zabezpieczenie przed pustymi zakresami w Swift
        guard m > 0 && n > 0 else { return [] }
        
        // DP table for LCS
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 1...m {
            for j in 1...n {
                if initialWords[i-1] == currentWords[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        
        // Backtrack to find differences
        var i = m
        var j = n
        
        var diffs: [(wrong: [String], correct: [String])] = []
        
        var currentWrong: [String] = []
        var currentCorrect: [String] = []
        
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && initialWords[i-1] == currentWords[j-1] {
                if !currentWrong.isEmpty || !currentCorrect.isEmpty {
                    diffs.append((currentWrong, currentCorrect))
                    currentWrong.removeAll()
                    currentCorrect.removeAll()
                }
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
                currentCorrect.insert(currentWords[j-1], at: 0)
                j -= 1
            } else {
                currentWrong.insert(initialWords[i-1], at: 0)
                i -= 1
            }
        }
        
        if !currentWrong.isEmpty || !currentCorrect.isEmpty {
            diffs.append((currentWrong, currentCorrect))
        }
        
        var corrections: [(wrong: String, correct: String)] = []
        
        // Analyze diffs
        for diff in diffs.reversed() {
            let wrongWords = diff.wrong
            let correctWords = diff.correct
            
            // Dopuszczamy poprawki o długości max 2 słów na stronę
            guard !wrongWords.isEmpty && !correctWords.isEmpty else { continue }
            guard wrongWords.count <= 2 && correctWords.count <= 2 else { continue }
            
            let wrongText = wrongWords.joined(separator: " ").trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            let correctText = correctWords.joined(separator: " ").trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            
            guard !wrongText.isEmpty && !correctText.isEmpty else { continue }
            
            if wrongText.lowercased() != correctText.lowercased() || wrongText != correctText {
                corrections.append((wrongText, correctText))
            }
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


