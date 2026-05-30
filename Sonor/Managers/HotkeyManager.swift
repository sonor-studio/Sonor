import Foundation
import AppKit

// Top-level callback function
func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    return HotkeyManager.shared.handleEvent(type: type, event: event)
}

class HotkeyManager {
    static let shared = HotkeyManager()
    
    // Callbacki dla wciśnięcia i puszczenia
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?
    
    var onCancelKeyDown: (() -> Void)?
    var onPauseKeyDown: (() -> Void)?
    var onAssistantKeyDown: (() -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    private var activeIsHoldMode = false
    
    private init() {}
    
    func startListening() {
        // Remove old tap if exists
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyCode")
        let hotkeyCode = savedKeyCode == 0 ? 50 : savedKeyCode
        
        print("🎯 HotkeyManager: Nasłuchiwanie (EventTap) włączone. Main Code: \(hotkeyCode)")
        
        let eventMask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue))
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            print("❌ Failed to create event tap. Upewnij się, że aplikacja ma uprawnienia Accessibility.")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = self.runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("🎯 Event Tap włączony!")
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
        print("🎯 HotkeyManager: Zatrzymano nasłuchiwanie")
    }
    
    struct HotkeyDef {
        let code: Int
        let modifiers: Int
        let targetModifiers: NSEvent.ModifierFlags
        let isOnlyModifier: Bool
        
        init(keyCodeKey: String, modifiersKey: String, defaultCode: Int? = nil, defaultModifiers: Int? = nil) {
            let userCode = UserDefaults.standard.object(forKey: keyCodeKey) as? Int
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
            print("⚠️ HotkeyManager: Event Tap disabled by timeout! Re-enabling...")
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        if type == .tapDisabledByUserInput {
            print("⚠️ HotkeyManager: Event Tap disabled by user input!")
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        
        let mainHotkey = HotkeyDef(keyCodeKey: "hotkeyCode", modifiersKey: "hotkeyModifiers", defaultCode: 50, defaultModifiers: 0x0100 | 0x0200)
        let cancelHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_cancel", modifiersKey: "hotkeyModifiers_cancel")
        let pauseHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_pause", modifiersKey: "hotkeyModifiers_pause")
        let assistantHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_assistant", modifiersKey: "hotkeyModifiers_assistant")
        
        if !self.isKeyDown {
            let hotkeyModeString = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
            self.activeIsHoldMode = hotkeyModeString == "Przytrzymanie" || hotkeyModeString == "Hold"
        }
        let isHoldMode = self.activeIsHoldMode
        
        // Obsługa samych klawiszy modyfikujących (Fn, Cmd, Ctrl, Opt, Shift)
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
                    print("🎯 Main Hotkey (Mod) Down!")
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                } else if !isPressed && self.isKeyDown {
                    self.isKeyDown = false
                    print("🎯 Main Hotkey (Mod) Up!")
                    if isHoldMode {
                        DispatchQueue.main.async { self.onHotkeyUp?() }
                    }
                }
            } else if cancelHotkey.isOnlyModifier && code == cancelHotkey.code {
                if isPressed {
                    print("🎯 Cancel Hotkey (Mod) Down!")
                    DispatchQueue.main.async { self.onCancelKeyDown?() }
                }
            } else if pauseHotkey.isOnlyModifier && code == pauseHotkey.code {
                if !isHoldMode && isPressed {
                    print("🎯 Pause Hotkey (Mod) Down!")
                    DispatchQueue.main.async { self.onPauseKeyDown?() }
                }
            } else if assistantHotkey.isOnlyModifier && code == assistantHotkey.code {
                if isPressed {
                    print("🎯 Assistant Hotkey (Mod) Down!")
                    DispatchQueue.main.async { self.onAssistantKeyDown?() }
                }
            }
            
            return Unmanaged.passUnretained(event)
        }
        
        // Obsługa standardowych klawiszy + modyfikatorów
        if type == .keyDown {
            let currentModifiers = nsEvent.modifierFlags.intersection([.command, .shift, .option, .control])
            let code = Int(nsEvent.keyCode)
            
            if code == mainHotkey.code && currentModifiers == mainHotkey.targetModifiers {
                if !self.isKeyDown {
                    self.isKeyDown = true
                    print("🎯 Main Hotkey Down!")
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                }
                print("🎯 Połykanie klawisza (Main)!")
                return nil // SWALLOW!
            } else if code == cancelHotkey.code && currentModifiers == cancelHotkey.targetModifiers {
                print("🎯 Cancel Hotkey Down!")
                DispatchQueue.main.async { self.onCancelKeyDown?() }
                return nil
            } else if code == pauseHotkey.code && currentModifiers == pauseHotkey.targetModifiers {
                if !isHoldMode {
                    print("🎯 Pause Hotkey Down!")
                    DispatchQueue.main.async { self.onPauseKeyDown?() }
                    return nil
                }
            } else if code == assistantHotkey.code && currentModifiers == assistantHotkey.targetModifiers {
                print("🎯 Assistant Hotkey Down!")
                DispatchQueue.main.async { self.onAssistantKeyDown?() }
                return nil
            }
        }
        
        if type == .keyUp {
            let code = Int(nsEvent.keyCode)
            if code == mainHotkey.code {
                if self.isKeyDown {
                    self.isKeyDown = false
                    print("🎯 Main Hotkey Up!")
                    if isHoldMode {
                        DispatchQueue.main.async { self.onHotkeyUp?() }
                    }
                }
                print("🎯 Połykanie keyUp (Main)!")
                return nil // SWALLOW!
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}

