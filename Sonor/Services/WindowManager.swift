import Foundation
import AppKit
import SwiftUI
import AVFoundation

@MainActor
class WindowManager {
    static let shared = WindowManager()
    
    var hudWindow: NSPanel?
    private var settingsWindow: NSWindow?
    private var supportWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    
    private init() {}
    
    func showHUD(controller: AppController) {
        hideHUDWorkItem?.cancel()
        hideHUDWorkItem = nil
        
        if hudWindow == nil {
            let panel = SonorHUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 600),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: CapsuleHUDView(controller: controller))
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .none
            panel.appearance = NSAppearance(named: .darkAqua)
            if let screen = NSScreen.main {
                let defaultX = (screen.frame.width - 350) / 2
                let defaultY: CGFloat = 100
                let savedX = UserDefaults.standard.object(forKey: "hudWindowX") as? CGFloat ?? defaultX
                let savedY = UserDefaults.standard.object(forKey: "hudWindowY") as? CGFloat ?? defaultY
                let screenFrame = screen.visibleFrame
                let modeStr = UserDefaults.standard.string(forKey: "hudPositionMode") ?? "free"
                let mode = HUDPositionMode(rawValue: modeStr) ?? .free
                
                let currentPanelWidth: CGFloat = 350
                panel.setContentSize(NSSize(width: currentPanelWidth, height: 600))
                
                let leftMargin: CGFloat = 33
                let rightMargin: CGFloat = currentPanelWidth - leftMargin
                let visibleHeight: CGFloat = 88
                let minXBound = screenFrame.minX - leftMargin
                let maxXBound = screenFrame.maxX - rightMargin
                let minYBound = screenFrame.minY - 8
                let maxYBound = screenFrame.maxY - visibleHeight - 8
                
                var startX = savedX
                var startY = savedY
                
                switch mode {
                case .top:
                    startX = screenFrame.minX + (screenFrame.width - currentPanelWidth) / 2
                    startY = screenFrame.maxY - visibleHeight - 20
                case .bottom:
                    startX = screenFrame.minX + (screenFrame.width - currentPanelWidth) / 2
                    startY = screenFrame.minY + 20
                case .free:
                    startX = max(minXBound, min(savedX, maxXBound))
                    startY = max(minYBound, min(savedY, maxYBound))
                }
                
                panel.setFrameOrigin(NSPoint(x: startX, y: startY))
            }
            self.hudWindow = panel
        }
        hudWindow?.backgroundColor = .clear
        hudWindow?.isOpaque = false
        hudWindow?.hasShadow = false
        
        if hudWindow?.isVisible == false {
            hudWindow?.orderFront(nil)
        }
        NotificationCenter.default.post(name: NSNotification.Name("HUDWindowDidShow"), object: nil)
        
        LLMManager.shared.cancelUnloadTimer()
        TranscriptionManager.shared.cancelUnloadTimer()
    }
    
    func updateHUDPosition(for mode: HUDPositionMode) {
        guard let panel = self.hudWindow, let screen = panel.screen ?? NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 350
        panel.setContentSize(NSSize(width: panelWidth, height: 600))
        let visibleHeight: CGFloat = 88 // estimated height for positioning
        
        let centerX = screenFrame.minX + (screenFrame.width - panelWidth) / 2
        
        let topMargin: CGFloat = 20
        let bottomMargin: CGFloat = 20
        
        switch mode {
        case .top:
            let y = screenFrame.maxY - visibleHeight - topMargin
            panel.setFrameOrigin(NSPoint(x: centerX, y: y))
            
        case .bottom:
            let y = screenFrame.minY + bottomMargin
            panel.setFrameOrigin(NSPoint(x: centerX, y: y))
            
        case .free:
            // Do not force move when switching to free
            break
        }
    }
    
    private var hideHUDWorkItem: DispatchWorkItem?
    
    func hideHUD() {
        if hudWindow?.isVisible == true {
            NotificationCenter.default.post(name: NSNotification.Name("HUDWindowWillHide"), object: nil)
            
            hideHUDWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.hudWindow?.orderOut(nil)
            }
            hideHUDWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
        LLMManager.shared.resetUnloadTimer()
        TranscriptionManager.shared.resetUnloadTimer()
    }
    

    var hasShownSupportWindowThisSession = false

    func openSettings(showSupportWindow: Bool = true) {
        let trusted = AXIsProcessTrusted()
        let hasMic = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        if !trusted || !hasMic {
            self.openPermissionsWindow()
            return
        }

        
        if let window = settingsWindow {
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
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
        NSApp.activate(ignoringOtherApps: true)
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
    

    



    func openPermissionsWindow() {
        self.settingsWindow?.close()
        self.supportWindow?.close()
        
        if let window = permissionsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Sonor - Wymagane uprawnienia"
        window.center()
        window.contentView = NSHostingView(rootView: PermissionsExplanationView())
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        
        self.permissionsWindow = window
        
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                self?.permissionsWindow = nil
                self?.updateActivationPolicy()
            }
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name("HidePermissionViews"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.permissionsWindow?.close()
                self?.openSettings()
            }
        }
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    func updateActivationPolicy() {
        let isSettingsVisible = settingsWindow?.isVisible == true
        let isSupportVisible = supportWindow?.isVisible == true
        let isPermissionsVisible = permissionsWindow?.isVisible == true
        if !isSettingsVisible && !isSupportVisible && !isPermissionsVisible {
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
