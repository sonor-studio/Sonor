import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
           let url = URL(string: urlString) {
            AuthManager.shared.handleDeepLink(url)
        }
    }
}

@main
struct SonorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = AppController()
    init() {
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
            WindowManager.shared.openSettings()
        }
        Divider()
        Button(t("Quit")) {
            controller.quitApp()
        }
    }
}

