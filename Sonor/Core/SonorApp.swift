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
        menuBarExtraScene
    }
    
    private var menuBarExtraScene: some Scene {
        if controller.isRecording {
            return MenuBarExtra("Sonor", systemImage: "mic.fill") {
                menuContent
            }
        } else {
            return MenuBarExtra("Sonor", image: "MenuBarIcon") {
                menuContent
            }
        }
    }
    
    @ViewBuilder
    private var menuContent: some View {
        Button(t("Settings")) {
            controller.openSettings()
        }
        Divider()
        Button(t("Quit")) {
            controller.quitApp()
        }
    }
}

