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
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    
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
        
        print("🎯 HotkeyManager: Nasłuchiwanie (EventTap) dla Code: \(hotkeyCode)")
        
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
        
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        
        let hotkeyCode = savedKeyCode == 0 ? 50 : savedKeyCode
        let hotkeyModifiers = savedModifiers == 0 ? (0x0100 | 0x0200) : savedModifiers
        let hotkeyMode = UserDefaults.standard.string(forKey: "hotkeyMode") ?? "Click"
        let isHoldMode = hotkeyMode == "Przytrzymanie" || hotkeyMode == "Hold"
        
        var targetModifiers = NSEvent.ModifierFlags()
        if (hotkeyModifiers & 0x0100) != 0 { targetModifiers.insert(.command) }
        if (hotkeyModifiers & 0x0200) != 0 { targetModifiers.insert(.shift) }
        if (hotkeyModifiers & 0x0800) != 0 { targetModifiers.insert(.option) }
        if (hotkeyModifiers & 0x1000) != 0 { targetModifiers.insert(.control) }
        
        let isOnlyModifierHotkey = hotkeyCode >= 54 && hotkeyCode <= 63
        
        // Obsługa samych klawiszy modyfikujących (Fn, Cmd, Ctrl, Opt, Shift)
        if type == .flagsChanged {
            if isOnlyModifierHotkey && nsEvent.keyCode == UInt16(hotkeyCode) {
                let modifiers = nsEvent.modifierFlags
                var isPressed = false
                
                switch nsEvent.keyCode {
                case 54, 55: isPressed = modifiers.contains(.command)
                case 56, 60: isPressed = modifiers.contains(.shift)
                case 58, 61: isPressed = modifiers.contains(.option)
                case 59, 62: isPressed = modifiers.contains(.control)
                case 63: isPressed = modifiers.contains(.function)
                default: break
                }
                
                if isPressed && !self.isKeyDown {
                    self.isKeyDown = true
                    print("🎯 Hotkey (Mod) Down!")
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                } else if !isPressed && self.isKeyDown {
                    self.isKeyDown = false
                    print("🎯 Hotkey (Mod) Up!")
                    if isHoldMode {
                        DispatchQueue.main.async { self.onHotkeyUp?() }
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // Obsługa standardowych klawiszy + modyfikatorów
        if type == .keyDown {
            let currentModifiers = nsEvent.modifierFlags.intersection([.command, .shift, .option, .control])
            
            if nsEvent.keyCode == UInt16(hotkeyCode) && currentModifiers == targetModifiers {
                if !self.isKeyDown {
                    self.isKeyDown = true
                    print("🎯 Hotkey Down!")
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                }
                print("🎯 Połykanie klawisza!")
                return nil // SWALLOW!
            }
        }
        
        if type == .keyUp {
            if nsEvent.keyCode == UInt16(hotkeyCode) {
                if self.isKeyDown {
                    self.isKeyDown = false
                    print("🎯 Hotkey Up!")
                    if isHoldMode {
                        DispatchQueue.main.async { self.onHotkeyUp?() }
                    }
                }
                print("🎯 Połykanie keyUp!")
                return nil // SWALLOW!
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}
