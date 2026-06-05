import Foundation
import AppKit


func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let result = HotkeyManager.shared.handleEvent(type: type, event: event)
    return result
}

class HotkeyManager {
    static let shared = HotkeyManager()
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    var onCancelKeyDown: (() -> Void)?
    var onPauseKeyDown: (() -> Void)?
    var onAssistantKeyDown: (() -> Void)?
    var isSecondaryHotkeysEnabled: (() -> Bool)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    private var activeIsHoldMode = false
    private var cachedMainHotkey: HotkeyDef?
    private var cachedCancelHotkey: HotkeyDef?
    private var cachedPauseHotkey: HotkeyDef?
    private var cachedAssistantHotkey: HotkeyDef?
    private var cachedHotkeyModeString: String = "Click"
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var hasNotifiedMissingPermissions = false
    
    private init() {
        self.checkPermissions()
        
        // Instead of polling every 2 seconds and locking up macOS TCCD (which lags the global keyboard),
        // we check permissions automatically whenever the app becomes active (gains focus).
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.processIdentifier == NSRunningApplication.current.processIdentifier {
            self.checkPermissions()
        }
    }
    
    func checkPermissions() {
        let trusted = AXIsProcessTrusted()
        let hasTap = self.eventTap != nil
        
        if trusted {
            self.hasNotifiedMissingPermissions = false
            if !hasTap {
                self.startListening()
            } else if let tap = self.eventTap, !CGEvent.tapIsEnabled(tap: tap) {
                self.startListening()
            }
        } else {
            if hasTap {
                self.stopListening()
            }
            
            if !self.hasNotifiedMissingPermissions {
                self.hasNotifiedMissingPermissions = true
                NotificationCenter.default.post(name: Notification.Name("AccessibilityPermissionRevoked"), object: nil)
                
                DispatchQueue.main.async {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                    WindowManager.shared.openAccessibilityPermissionWindow()
                }
            }
        }
    }
    
    func startListening() {
        self.stopListening()
        
        guard AXIsProcessTrusted() else {
            return
        }
        
        self.cachedMainHotkey = HotkeyDef(keyCodeKey: "hotkeyCode", modifiersKey: "hotkeyModifiers", stringKey: "hotkeyString", defaultCode: 50, defaultModifiers: 0x0100 | 0x0200)
        self.cachedCancelHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_cancel", modifiersKey: "hotkeyModifiers_cancel", stringKey: "hotkeyString_cancel")
        self.cachedPauseHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_pause", modifiersKey: "hotkeyModifiers_pause", stringKey: "hotkeyString_pause")
        self.cachedAssistantHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_assistant", modifiersKey: "hotkeyModifiers_assistant", stringKey: "hotkeyString_assistant")
        self.cachedHotkeyModeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
        
        let eventMask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            return
        }
        self.eventTap = tap
        
        self.tapThread = Thread { [weak self] in
            guard let self = self else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            
            self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = self.runLoopSource {
                CFRunLoopAddSource(self.tapRunLoop!, source, .defaultMode)
                CGEvent.tapEnable(tap: tap, enable: true)
                CFRunLoopRun()
            }
        }
        self.tapThread?.name = "SonorCGEventTapThread"
        self.tapThread?.start()
    }
    
    func stopListening() {
        if let tap = self.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        
        let runLoopToStop = self.tapRunLoop
        let sourceToRemove = self.runLoopSource
        
        self.eventTap = nil
        self.runLoopSource = nil
        self.tapRunLoop = nil
        
        if let runLoop = runLoopToStop {
            if let source = sourceToRemove {
                CFRunLoopRemoveSource(runLoop, source, .defaultMode)
            }
            CFRunLoopStop(runLoop)
        }
        
        if let thread = self.tapThread {
            thread.cancel()
        }
        self.tapThread = nil
    }
    
    struct HotkeyDef {
        let code: Int
        let modifiers: Int
        let targetModifiers: NSEvent.ModifierFlags
        let isOnlyModifier: Bool
        let stringKey: String?
        init(keyCodeKey: String, modifiersKey: String, stringKey: String? = nil, defaultCode: Int? = nil, defaultModifiers: Int? = nil) {
            self.stringKey = stringKey
            var userCode = UserDefaults.standard.object(forKey: keyCodeKey) as? Int
            if let sk = stringKey, UserDefaults.standard.string(forKey: sk) == "None" {
                userCode = -1
            }
            let userMods = UserDefaults.standard.object(forKey: modifiersKey) as? Int
            let finalCode = userCode ?? defaultCode ?? -1
            let finalMods = userMods ?? defaultModifiers ?? 0
            self.code = finalCode
            self.modifiers = finalMods
            var tm = NSEvent.ModifierFlags()
            if (finalMods & 0x0100) != 0 { tm.insert(.command) }
            if (finalMods & 0x0200) != 0 { tm.insert(.shift) }
            if (finalMods & 0x0800) != 0 { tm.insert(.option) }
            if (finalMods & 0x1000) != 0 { tm.insert(.control) }
            self.targetModifiers = tm
            self.isOnlyModifier = (finalCode >= 54 && finalCode <= 63)
        }
    }
    
    func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return passthrough
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return passthrough
        }
        
        guard let mainHotkey = self.cachedMainHotkey,
              let cancelHotkey = self.cachedCancelHotkey,
              let pauseHotkey = self.cachedPauseHotkey,
              let assistantHotkey = self.cachedAssistantHotkey else {
            return passthrough
        }

        if !self.isKeyDown {
            self.activeIsHoldMode = self.cachedHotkeyModeString == "Hold"
        }
        let isHoldMode = self.activeIsHoldMode
        
        if type == .flagsChanged {
            let code = Int(nsEvent.keyCode)
            let modifiers = nsEvent.modifierFlags
            var isPressed = false
            switch code {
            case 54, 55: isPressed = modifiers.contains(.command)
            case 56, 60: isPressed = modifiers.contains(.shift)
            case 58, 61: isPressed = modifiers.contains(.option)
            case 59, 62: isPressed = modifiers.contains(.control)
            case 63: isPressed = modifiers.contains(.function)
            default: break
            }
            if mainHotkey.isOnlyModifier && code == mainHotkey.code {
                if isPressed && !self.isKeyDown {
                    self.isKeyDown = true
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                } else if !isPressed && self.isKeyDown {
                    self.isKeyDown = false
                    if isHoldMode {
                        DispatchQueue.main.async { self.onHotkeyUp?() }
                    }
                }
            }
            let secondaryActive = self.isSecondaryHotkeysEnabled?() ?? true
            if secondaryActive {
                if cancelHotkey.isOnlyModifier && code == cancelHotkey.code {
                    if isPressed {
                        DispatchQueue.main.async { self.onCancelKeyDown?() }
                    }
                }
                if pauseHotkey.isOnlyModifier && code == pauseHotkey.code {
                    if isPressed {
                        DispatchQueue.main.async { self.onPauseKeyDown?() }
                    }
                }
                if assistantHotkey.isOnlyModifier && code == assistantHotkey.code {
                    if isPressed {
                        DispatchQueue.main.async { self.onAssistantKeyDown?() }
                    }
                }
            }
            return passthrough
        }
        
        if type == .keyDown {
            let code = Int(nsEvent.keyCode)
            let modifiers = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !mainHotkey.isOnlyModifier && code == mainHotkey.code && modifiers == mainHotkey.targetModifiers {
                if !isKeyDown {
                    isKeyDown = true
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                }
                return nil
            }
            
            let secondaryActive = self.isSecondaryHotkeysEnabled?() ?? true
            if secondaryActive {
                if !cancelHotkey.isOnlyModifier && code == cancelHotkey.code && modifiers == cancelHotkey.targetModifiers {
                    DispatchQueue.main.async { self.onCancelKeyDown?() }
                    return nil
                }
                if !pauseHotkey.isOnlyModifier && code == pauseHotkey.code && modifiers == pauseHotkey.targetModifiers {
                    DispatchQueue.main.async { self.onPauseKeyDown?() }
                    return nil
                }
                if !assistantHotkey.isOnlyModifier && code == assistantHotkey.code && modifiers == assistantHotkey.targetModifiers {
                    DispatchQueue.main.async { self.onAssistantKeyDown?() }
                    return nil
                }
            }
            return passthrough
        } else if type == .keyUp {
            let code = Int(nsEvent.keyCode)
            if !mainHotkey.isOnlyModifier && code == mainHotkey.code {
                if isKeyDown {
                    isKeyDown = false
                    if isHoldMode {
                        DispatchQueue.main.async { self.onHotkeyUp?() }
                    }
                }
                return nil
            }
            
            let secondaryActive = self.isSecondaryHotkeysEnabled?() ?? true
            if secondaryActive {
                if !cancelHotkey.isOnlyModifier && code == cancelHotkey.code {
                    return nil
                }
                if !pauseHotkey.isOnlyModifier && code == pauseHotkey.code {
                    return nil
                }
                if !assistantHotkey.isOnlyModifier && code == assistantHotkey.code {
                    return nil
                }
            }
            return passthrough
        }
        
        return passthrough
    }
}
