import Foundation
import AppKit
import AVFoundation


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
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    private var isCancelKeyDown = false
    private var isPauseKeyDown = false
    private var isAssistantKeyDown = false
    private var activeIsHoldMode = false
    private var modifierOnlyHotkeyAborted = false
    private var cachedMainHotkey: HotkeyDef?
    private var cachedCancelHotkey: HotkeyDef?
    private var cachedPauseHotkey: HotkeyDef?
    private var cachedAssistantHotkey: HotkeyDef?
    private var cachedHotkeyModeString: String = "Click"
    private var capturedKeys: Set<Int> = []
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
        let hasMic = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        let hasTap = self.eventTap != nil
        
        let allGranted = trusted && hasMic
        
        if allGranted {
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
                NotificationCenter.default.post(name: Notification.Name("PermissionsRevoked"), object: nil)
                
                DispatchQueue.main.async {
                    if !trusted {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                    }
                    WindowManager.shared.openPermissionsWindow()
                }
            }
        }
    }
    
    func startListening() {
        self.stopListening()
        
        guard AXIsProcessTrusted() else {
            return
        }
        
        self.cachedMainHotkey = HotkeyDef(keyCodeKey: "hotkeyCode", modifiersKey: "hotkeyModifiers", stringKey: "hotkeyString", defaultCode: 49, defaultModifiers: 0x1800)
        self.cachedCancelHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_cancel", modifiersKey: "hotkeyModifiers_cancel", stringKey: "hotkeyString_cancel", defaultCode: 6, defaultModifiers: 0x1800)
        self.cachedPauseHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_pause", modifiersKey: "hotkeyModifiers_pause", stringKey: "hotkeyString_pause", defaultCode: 7, defaultModifiers: 0x1800)
        self.cachedAssistantHotkey = HotkeyDef(keyCodeKey: "hotkeyCode_assistant", modifiersKey: "hotkeyModifiers_assistant", stringKey: "hotkeyString_assistant", defaultCode: 8, defaultModifiers: 0x1800)
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
            let modifiers = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            var changedFlag: NSEvent.ModifierFlags?
            switch code {
            case 54, 55: changedFlag = .command
            case 56, 60: changedFlag = .shift
            case 58, 61: changedFlag = .option
            case 59, 62: changedFlag = .control
            default: break
            }
            
            var isPressed = false
            if let flag = changedFlag {
                isPressed = modifiers.contains(flag)
            }
            
            // Main Hotkey
            if mainHotkey.isOnlyModifier {
                var mainTriggerFlag = NSEvent.ModifierFlags()
                switch mainHotkey.code {
                case 54, 55: mainTriggerFlag = .command
                case 56, 60: mainTriggerFlag = .shift
                case 58, 61: mainTriggerFlag = .option
                case 59, 62: mainTriggerFlag = .control
                default: break
                }
                
                if self.isKeyDown && isPressed && code != mainHotkey.code && (changedFlag == nil || !mainHotkey.targetModifiers.contains(changedFlag!)) {
                    self.modifierOnlyHotkeyAborted = true
                }
                
                if code == mainHotkey.code && isPressed {
                    let activeOthers = modifiers.subtracting(mainTriggerFlag)
                    if activeOthers == mainHotkey.targetModifiers {
                        if !self.isKeyDown {
                            self.isKeyDown = true
                            self.modifierOnlyHotkeyAborted = false
                            if isHoldMode {
                                DispatchQueue.main.async { self.onHotkeyDown?() }
                            }
                        }
                    }
                } else if !isPressed && self.isKeyDown {
                    let releasedTrigger = (code == mainHotkey.code)
                    let releasedOtherRequired = (changedFlag != nil && mainHotkey.targetModifiers.contains(changedFlag!))
                    if releasedTrigger || releasedOtherRequired {
                        self.isKeyDown = false
                        if isHoldMode {
                            DispatchQueue.main.async { self.onHotkeyUp?() }
                        } else {
                            if !self.modifierOnlyHotkeyAborted {
                                DispatchQueue.main.async { self.onHotkeyDown?() }
                            }
                        }
                    }
                }
            }
            
            // Cancel Hotkey
            if cancelHotkey.isOnlyModifier {
                var cancelTriggerFlag = NSEvent.ModifierFlags()
                switch cancelHotkey.code {
                case 54, 55: cancelTriggerFlag = .command
                case 56, 60: cancelTriggerFlag = .shift
                case 58, 61: cancelTriggerFlag = .option
                case 59, 62: cancelTriggerFlag = .control
                default: break
                }
                
                if self.isCancelKeyDown && isPressed && code != cancelHotkey.code && (changedFlag == nil || !cancelHotkey.targetModifiers.contains(changedFlag!)) {
                    self.modifierOnlyHotkeyAborted = true
                }
                
                if code == cancelHotkey.code && isPressed {
                    let activeOthers = modifiers.subtracting(cancelTriggerFlag)
                    if activeOthers == cancelHotkey.targetModifiers {
                        if !self.isCancelKeyDown {
                            self.isCancelKeyDown = true
                            self.modifierOnlyHotkeyAborted = false
                        }
                    }
                } else if !isPressed && self.isCancelKeyDown {
                    let releasedTrigger = (code == cancelHotkey.code)
                    let releasedOtherRequired = (changedFlag != nil && cancelHotkey.targetModifiers.contains(changedFlag!))
                    if releasedTrigger || releasedOtherRequired {
                        self.isCancelKeyDown = false
                        if !self.modifierOnlyHotkeyAborted {
                            DispatchQueue.main.async { self.onCancelKeyDown?() }
                        }
                    }
                }
            }
            
            // Pause Hotkey
            if pauseHotkey.isOnlyModifier {
                var pauseTriggerFlag = NSEvent.ModifierFlags()
                switch pauseHotkey.code {
                case 54, 55: pauseTriggerFlag = .command
                case 56, 60: pauseTriggerFlag = .shift
                case 58, 61: pauseTriggerFlag = .option
                case 59, 62: pauseTriggerFlag = .control
                default: break
                }
                
                if self.isPauseKeyDown && isPressed && code != pauseHotkey.code && (changedFlag == nil || !pauseHotkey.targetModifiers.contains(changedFlag!)) {
                    self.modifierOnlyHotkeyAborted = true
                }
                
                if code == pauseHotkey.code && isPressed {
                    let activeOthers = modifiers.subtracting(pauseTriggerFlag)
                    if activeOthers == pauseHotkey.targetModifiers {
                        if !self.isPauseKeyDown {
                            self.isPauseKeyDown = true
                            self.modifierOnlyHotkeyAborted = false
                        }
                    }
                } else if !isPressed && self.isPauseKeyDown {
                    let releasedTrigger = (code == pauseHotkey.code)
                    let releasedOtherRequired = (changedFlag != nil && pauseHotkey.targetModifiers.contains(changedFlag!))
                    if releasedTrigger || releasedOtherRequired {
                        self.isPauseKeyDown = false
                        if !self.modifierOnlyHotkeyAborted {
                            DispatchQueue.main.async { self.onPauseKeyDown?() }
                        }
                    }
                }
            }
            
            // Assistant Hotkey
            if assistantHotkey.isOnlyModifier {
                var assistantTriggerFlag = NSEvent.ModifierFlags()
                switch assistantHotkey.code {
                case 54, 55: assistantTriggerFlag = .command
                case 56, 60: assistantTriggerFlag = .shift
                case 58, 61: assistantTriggerFlag = .option
                case 59, 62: assistantTriggerFlag = .control
                default: break
                }
                
                if self.isAssistantKeyDown && isPressed && code != assistantHotkey.code && (changedFlag == nil || !assistantHotkey.targetModifiers.contains(changedFlag!)) {
                    self.modifierOnlyHotkeyAborted = true
                }
                
                if code == assistantHotkey.code && isPressed {
                    let activeOthers = modifiers.subtracting(assistantTriggerFlag)
                    if activeOthers == assistantHotkey.targetModifiers {
                        if !self.isAssistantKeyDown {
                            self.isAssistantKeyDown = true
                            self.modifierOnlyHotkeyAborted = false
                        }
                    }
                } else if !isPressed && self.isAssistantKeyDown {
                    let releasedTrigger = (code == assistantHotkey.code)
                    let releasedOtherRequired = (changedFlag != nil && assistantHotkey.targetModifiers.contains(changedFlag!))
                    if releasedTrigger || releasedOtherRequired {
                        self.isAssistantKeyDown = false
                        if !self.modifierOnlyHotkeyAborted {
                            DispatchQueue.main.async { self.onAssistantKeyDown?() }
                        }
                    }
                }
            }
            
            return passthrough
        }
        
        if type == .keyDown {
            let code = Int(nsEvent.keyCode)
            
            if self.isKeyDown && mainHotkey.isOnlyModifier {
                self.modifierOnlyHotkeyAborted = true
            }
            if self.isCancelKeyDown && cancelHotkey.isOnlyModifier {
                self.modifierOnlyHotkeyAborted = true
            }
            if self.isPauseKeyDown && pauseHotkey.isOnlyModifier {
                self.modifierOnlyHotkeyAborted = true
            }
            if self.isAssistantKeyDown && assistantHotkey.isOnlyModifier {
                self.modifierOnlyHotkeyAborted = true
            }
            
            let modifiers = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !mainHotkey.isOnlyModifier && code == mainHotkey.code && modifiers == mainHotkey.targetModifiers {
                if !isKeyDown {
                    isKeyDown = true
                    DispatchQueue.main.async { self.onHotkeyDown?() }
                }
                capturedKeys.insert(code)
                return nil
            }
            
            if !cancelHotkey.isOnlyModifier && code == cancelHotkey.code && modifiers == cancelHotkey.targetModifiers {
                DispatchQueue.main.async { self.onCancelKeyDown?() }
                capturedKeys.insert(code)
                return nil
            }
            if !pauseHotkey.isOnlyModifier && code == pauseHotkey.code && modifiers == pauseHotkey.targetModifiers {
                DispatchQueue.main.async { self.onPauseKeyDown?() }
                capturedKeys.insert(code)
                return nil
            }
            if !assistantHotkey.isOnlyModifier && code == assistantHotkey.code && modifiers == assistantHotkey.targetModifiers {
                DispatchQueue.main.async { self.onAssistantKeyDown?() }
                capturedKeys.insert(code)
                return nil
            }
            return passthrough
        } else if type == .keyUp {
            let code = Int(nsEvent.keyCode)
            if capturedKeys.contains(code) {
                capturedKeys.remove(code)
                if !mainHotkey.isOnlyModifier && code == mainHotkey.code {
                    if isKeyDown {
                        isKeyDown = false
                        if isHoldMode {
                            DispatchQueue.main.async { self.onHotkeyUp?() }
                        }
                    }
                }
                return nil
            }
            return passthrough
        }
        
        return passthrough
    }
}
