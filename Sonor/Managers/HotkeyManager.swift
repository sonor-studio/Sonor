import Foundation
import AppKit


func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    return HotkeyManager.shared.handleEvent(type: type, event: event)
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
    private var checkTimer: Timer?
    
    private init() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if AXIsProcessTrusted() {
                if self.eventTap == nil {
                    self.startListening()
                } else if let tap = self.eventTap, !CGEvent.tapIsEnabled(tap: tap) {
                    self.startListening()
                }
            }
        }
    }
    
    func startListening() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        
        // Cache hotkeys here to avoid UserDefaults disk IO on every keystroke
        self.cachedMainHotkey = HotkeyDef(keyCodeKey: "hotkeyCode", modifiersKey: "hotkeyModifiers", stringKey: "hotkeyString", defaultCode: 50, defaultModifiers: 0x0100 | 0x0200)
        self.cachedCancelHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_cancel", modifiersKey: "hotkeyModifiers_cancel", stringKey: "hotkeyString_cancel")
        self.cachedPauseHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_pause", modifiersKey: "hotkeyModifiers_pause", stringKey: "hotkeyString_pause")
        self.cachedAssistantHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_assistant", modifiersKey: "hotkeyModifiers_assistant", stringKey: "hotkeyString_assistant")
        self.cachedHotkeyModeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
        
        guard AXIsProcessTrusted() else { return }
        
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
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = self.runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    func stopListening() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
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
        if type == .tapDisabledByTimeout {
            DebugLogger.shared.addLog("HotkeyManager: Event tap disabled by timeout! Attempting to re-enable...")
            if AXIsProcessTrusted(), let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByUserInput {
            DebugLogger.shared.addLog("HotkeyManager: Event tap disabled by user input!")
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        
        guard let mainHotkey = self.cachedMainHotkey,
              let cancelHotkey = self.cachedCancelHotkey,
              let pauseHotkey = self.cachedPauseHotkey,
              let assistantHotkey = self.cachedAssistantHotkey else {
            return Unmanaged.passUnretained(event)
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
                } else if pauseHotkey.isOnlyModifier && code == pauseHotkey.code {
                    if !isHoldMode && isPressed {
                        DispatchQueue.main.async { self.onPauseKeyDown?() }
                    }
                } else if assistantHotkey.isOnlyModifier && code == assistantHotkey.code {
                    if isPressed {
                        DispatchQueue.main.async { self.onAssistantKeyDown?() }
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            let currentModifiers = nsEvent.modifierFlags.intersection([.command, .shift, .option, .control])
            let code = Int(nsEvent.keyCode)
            if code == mainHotkey.code && currentModifiers == mainHotkey.targetModifiers {
                if !self.isKeyDown {
                    self.isKeyDown = true
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                }
                return nil 
            }
            let secondaryActive = self.isSecondaryHotkeysEnabled?() ?? true
            if secondaryActive {
                if code == cancelHotkey.code && currentModifiers == cancelHotkey.targetModifiers {
                    DispatchQueue.main.async { self.onCancelKeyDown?() }
                    return nil
                } else if code == pauseHotkey.code && currentModifiers == pauseHotkey.targetModifiers {
                    if !isHoldMode {
                        DispatchQueue.main.async { self.onPauseKeyDown?() }
                        return nil
                    }
                } else if code == assistantHotkey.code && currentModifiers == assistantHotkey.targetModifiers {
                    DispatchQueue.main.async { self.onAssistantKeyDown?() }
                    return nil
                }
            }
        }
        if type == .keyUp {
            let code = Int(nsEvent.keyCode)
            if code == mainHotkey.code {
                if self.isKeyDown {
                    self.isKeyDown = false
                    if isHoldMode {
                        DispatchQueue.main.async { self.onHotkeyUp?() }
                    }
                }
                return nil 
            }
        }
        return Unmanaged.passUnretained(event)
    }
}

