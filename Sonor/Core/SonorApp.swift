import SwiftUI

@main
struct SonorApp: App {
    @StateObject private var controller = AppController()
    
    init() {
        // Ukryj aplikację z Docka i spraw, by działała tylko w pasku menu (Menu Bar)
        NSApplication.shared.setActivationPolicy(.accessory)
        
        // Zawsze wyłączaj tryb incognito przy uruchomieniu aplikacji
        UserDefaults.standard.set(false, forKey: "isIncognitoMode")
        
        UpdateManager.shared.checkForUpdates()
    }
    
    var body: some Scene {
        menuBarExtraScene
    }
    
    private var menuBarExtraScene: some Scene {
        MenuBarExtra("Sonor", image: "MenuBarIcon") {
            menuContent
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

