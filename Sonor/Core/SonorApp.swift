import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        // Deep link handling removed
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: NSNotification.Name("AppWillTerminate"), object: nil)
    }
}

@main
struct SonorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var controller = AppController()
    init() {
        // Zmuszamy MediaControlService do wcześniejszej inicjalizacji, 
        // aby adapter MediaRemote zdążył się połączyć i pobrać stan zanim użyjemy nagrywania pierwszy raz
        _ = MediaControlService.shared
        
        if CommandLine.arguments.contains("--worker-mode") {
            WorkerProcess.run()
            // Should not reach here because WorkerProcess calls exit()
        }
        
        NSApplication.shared.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApplication.shared.mainMenu = mainMenu
        UserDefaults.standard.set(false, forKey: "isIncognitoMode")
        UpdateManager.shared.checkForUpdates()
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let lastSeenVersion = UserDefaults.standard.string(forKey: "lastSeenVersion") ?? "0.0.0"
        if currentVersion != lastSeenVersion {
            UserDefaults.standard.set(currentVersion, forKey: "lastSeenVersion")
            let isReturningUser = lastSeenVersion != "0.0.0" || UserDefaults.standard.bool(forKey: "hasSeenOnboardingLocally")
            if isReturningUser {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    WindowManager.shared.openSettings(showSupportWindow: false)
                    NotificationCenter.default.post(name: Notification.Name("OpenChangelogTab"), object: nil)
                }
            }
        }
        
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            WindowManager.shared.hasShownSupportWindowThisSession = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                WindowManager.shared.openSettings(showSupportWindow: false)
            }
        }

    }
    var body: some Scene {
        menuBarExtraScene
    }
    private var menuBarExtraScene: some Scene {
        MenuBarExtra("Sonor", image: "MenuBarIcon") {
            MenuContentView(controller: controller)
        }
    }
}

struct MenuContentView: View {
    let controller: AppController
    @State private var isCopyDisabled: Bool
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    init(controller: AppController) {
        self.controller = controller
        self._isCopyDisabled = State(initialValue: controller.lastTranscription == nil)
    }
    
    var body: some View {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        Text("Sonor v\(appVersion)")
        
        Divider()
        
        Button(t("Copy last result")) {
            if let lastText = controller.lastTranscription {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lastText, forType: .string)
            }
        }
        .disabled(isCopyDisabled)
        .onReceive(controller.$lastTranscription) { text in
            isCopyDisabled = (text == nil)
        }
        
        Divider()
        
        Menu(t("Language")) {
            Toggle("English", isOn: Binding(
                get: { appLanguage == "en" },
                set: { if $0 { LocalizationManager.shared.appLanguage = "en" } }
            ))
            Toggle("Polski", isOn: Binding(
                get: { appLanguage == "pl" },
                set: { if $0 { LocalizationManager.shared.appLanguage = "pl" } }
            ))
            Toggle("Deutsch", isOn: Binding(
                get: { appLanguage == "de" },
                set: { if $0 { LocalizationManager.shared.appLanguage = "de" } }
            ))
            Toggle("Español", isOn: Binding(
                get: { appLanguage == "es" },
                set: { if $0 { LocalizationManager.shared.appLanguage = "es" } }
            ))
            Toggle("Français", isOn: Binding(
                get: { appLanguage == "fr" },
                set: { if $0 { LocalizationManager.shared.appLanguage = "fr" } }
            ))
            Toggle("Italiano", isOn: Binding(
                get: { appLanguage == "it" },
                set: { if $0 { LocalizationManager.shared.appLanguage = "it" } }
            ))
            Toggle("日本語", isOn: Binding(
                get: { appLanguage == "ja" },
                set: { if $0 { LocalizationManager.shared.appLanguage = "ja" } }
            ))
            Toggle("Português", isOn: Binding(
                get: { appLanguage == "pt" },
                set: { if $0 { LocalizationManager.shared.appLanguage = "pt" } }
            ))
            Toggle("中文", isOn: Binding(
                get: { appLanguage == "zh" },
                set: { if $0 { LocalizationManager.shared.appLanguage = "zh" } }
            ))
        }
        
        Button(t("Dashboard")) {
            WindowManager.shared.openSettings()
        }
        Divider()
        Button(t("Quit")) {
            controller.quitApp()
        }
    }
}

// MARK: - Worker Process
// This process runs in isolation to prevent MLX C++ aborts from crashing the main UI.
struct WorkerProcess {
    static func run() {
        let args = CommandLine.arguments
        guard let repoIndex = args.firstIndex(of: "--repo-id"), repoIndex + 1 < args.count,
              let audioIndex = args.firstIndex(of: "--audio"), audioIndex + 1 < args.count else {
            print("ERROR:Missing arguments")
            exit(1)
        }
        
        let repoId = args[repoIndex + 1]
        let audioPath = args[audioIndex + 1]
        
        var language = "auto"
        if let langIndex = args.firstIndex(of: "--language"), langIndex + 1 < args.count {
            language = args[langIndex + 1]
        }
        
        do {
            let audioData = try Data(contentsOf: URL(fileURLWithPath: audioPath))
            let audioSamples = audioData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            
            Task {
                do {
                    // Instantiate MLXEngine directly
                    let engine = MLXEngine(modelId: "worker", repoId: repoId)
                    try await engine.prepare()
                    
                    // We call performTranscription directly (skipping the worker proxy check)
                    let result = try await engine.performTranscription(audioSamples: audioSamples, language: language, initialPrompt: nil)
                    
                    let encoded = result.data(using: .utf8)?.base64EncodedString() ?? ""
                    print("SUCCESS:\(encoded)")
                    exit(0)
                } catch {
                    print("ERROR:\(error.localizedDescription)")
                    exit(1)
                }
            }
            
            // CRITICAL: We cannot use a semaphore to block the main thread here! 
            // Metal shader compilation and MLX GPU dispatch rely on XPC messages that 
            // often require the main thread's RunLoop to be active. 
            // Blocking it causes a complete deadlock (infinite spinning without crash).
            RunLoop.main.run()
            
        } catch {
            print("ERROR:\(error.localizedDescription)")
            exit(1)
        }
    }
}

