import SwiftUI

@main
struct SonorApp: App {
    @StateObject private var controller = AppController()
    
    init() {
        // Ukryj aplikację z Docka i spraw, by działała tylko w pasku menu (Menu Bar)
        NSApplication.shared.setActivationPolicy(.accessory)
        
        // Zawsze wyłączaj tryb incognito przy uruchomieniu aplikacji
        UserDefaults.standard.set(false, forKey: "isIncognitoMode")
    }
    
    var body: some Scene {
        MenuBarExtra(
            "Sonor", 
            systemImage: controller.isRecording ? "mic.fill" : "mic"
        ) {
            Button(t("Settings")) {
                controller.openSettings()
            }
            Divider()
            Button(t("Quit")) {
                controller.quitApp()
            }
        }
    }
}

