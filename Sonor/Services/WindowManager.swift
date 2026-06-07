import Foundation
import AppKit
import SwiftUI

@MainActor
class WindowManager {
    static let shared = WindowManager()
    
    var hudWindow: NSPanel?
    private var settingsWindow: NSWindow?
    private var supportWindow: NSWindow?
    
    private init() {}
    
    func showHUD(controller: AppController) {
        if hudWindow == nil {
            let panel = SonorHUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 600),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.contentView = NSHostingView(rootView: CapsuleHUDView(controller: controller))
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
        hudWindow?.backgroundColor = .clear
        hudWindow?.isOpaque = false
        hudWindow?.hasShadow = false
        hudWindow?.orderFront(nil)
    }
    
    func hideHUD() {
        hudWindow?.orderOut(nil)
    }
    
    private var hasShownSupportWindowThisSession = false

    func openSettings(showSupportWindow: Bool = true) {
        if let window = settingsWindow {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if showSupportWindow && !hasShownSupportWindowThisSession {
                self.hasShownSupportWindowThisSession = true
                self.openSupportWindow()
            }
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
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
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.isMovableByWindowBackground = false
        self.settingsWindow = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateActivationPolicy()
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: false)
        window.makeKeyAndOrderFront(nil)
        if showSupportWindow && !hasShownSupportWindowThisSession {
            self.hasShownSupportWindowThisSession = true
            self.openSupportWindow()
        }
    }
    
    func openSupportWindow() {
        if let window = supportWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: false)
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
        NSApp.activate(ignoringOtherApps: false)
        window.makeKeyAndOrderFront(nil)
    }
    

    
    func openMicrophonePermissionWindow() {
        self.openSettings(showSupportWindow: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: Notification.Name("ShowMicPermissionView"), object: nil)
        }
    }
    
    func openAccessibilityPermissionWindow() {
        self.openSettings(showSupportWindow: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: Notification.Name("ShowAccessibilityPermissionView"), object: nil)
        }
    }
    
    func updateActivationPolicy() {
        let isSettingsVisible = settingsWindow?.isVisible == true
        let isSupportVisible = supportWindow?.isVisible == true
        if !isSettingsVisible && !isSupportVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

class SonorHUDPanel: NSPanel {
    override var canBecomeKey: Bool { return false }
    override var canBecomeMain: Bool { return false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}
