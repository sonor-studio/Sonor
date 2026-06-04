import Foundation
import AppKit
import ApplicationServices

class PasteManager {
    static let shared = PasteManager()
    private init() {}

    func pasteTextToActiveApp(text: String, targetPID: pid_t) {
        guard targetPID > 0 else {
            return
        }

        guard let targetApp = NSRunningApplication(processIdentifier: targetPID) else {
            return
        }

        targetApp.activate(options: .activateAllWindows)

        var attempts = 0
        while !targetApp.isActive && attempts < 30 {
            Thread.sleep(forTimeInterval: 0.05)
            attempts += 1
        }
        Thread.sleep(forTimeInterval: 0.1)

        if tryAXInsert(text: text, pid: targetPID) {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        tryCGEventPaste()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let pb = NSPasteboard.general
            pb.clearContents()
        }
    }



    func getFocusedAXElement(pid: pid_t) -> AXUIElement? {
        guard AXIsProcessTrusted() else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: AnyObject?
        var focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if focusResult == .success, let element = focusedElement as! AXUIElement? {
            return element
        }
        var focusedWindow: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
           let windowElement = focusedWindow as! AXUIElement? {
            focusResult = AXUIElementCopyAttributeValue(windowElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            if focusResult == .success, let element = focusedElement as! AXUIElement? {
                return element
            }
        }
        var windowsList: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsList) == .success,
           let windows = windowsList as? [AXUIElement], let firstWindow = windows.first {
            focusResult = AXUIElementCopyAttributeValue(firstWindow, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            if focusResult == .success, let element = focusedElement as! AXUIElement? {
                return element
            }
        }
        return nil
    }

    func isElementTextField(_ axElement: AXUIElement?) -> Bool {
        guard let element = axElement else { 
            return true 
        }
        var isEditable: Bool? = nil
        
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
            isEditable = settable.boolValue
        }
        var attributeNames: CFArray?
        if AXUIElementCopyAttributeNames(element, &attributeNames) == .success,
           let names = attributeNames as? [String] {
            for attr in ["AXPlaceholderValue", "AXSelectedTextRange", "AXNumberOfCharacters", "AXEnabled"] {
                if names.contains(attr) {
                    var val: AnyObject?
                    if AXUIElementCopyAttributeValue(element, attr as CFString, &val) == .success {
                    }
                }
            }
        }
        if let editable = isEditable, editable == false {
            return false
        }
        return true
    }

    func isTextFieldFocused(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return true } 
        let element = getFocusedAXElement(pid: pid)
        return isElementTextField(element)
    }


    private func tryAXInsert(text: String, pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard focusResult == .success else {
            return false
        }

        guard let element = focusedElement else {
            return false
        }
        let axElement = element as! AXUIElement

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &settable)

        guard settable.boolValue else {
            return false
        }

        var currentValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValue)

        var selectedRange: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
        if let rangeValue = selectedRange,
           CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            let axValue = rangeValue as! AXValue
            var range = CFRange()
            AXValueGetValue(axValue, .cfRange, &range)

            let currentStr = (currentValue as? String) ?? ""
            let nsStr = currentStr as NSString
            let safeLocation = max(0, min(range.location, nsStr.length))
            let safeLength = max(0, min(range.length, nsStr.length - safeLocation))
            let safeRange = NSRange(location: safeLocation, length: safeLength)

            let newStr = nsStr.replacingCharacters(in: safeRange, with: text)

            let setResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, newStr as CFTypeRef)

            if setResult == .success {
                var newRange = CFRange(location: safeLocation + text.count, length: 0)
                if let newRangeValue = AXValueCreate(.cfRange, &newRange) {
                    AXUIElementSetAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, newRangeValue)
                }
                return true
            } else {
            }
        }

        let setResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFTypeRef)
        return setResult == .success
    }


    private func tryCGEventPaste() {
        let src = CGEventSource(stateID: .hidSystemState)

        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand

        vDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        vUp?.post(tap: .cghidEventTap)

    }


    func typeTextDirectly(text: String, targetPID: pid_t, forceFocusElement: AXUIElement? = nil) {
        guard targetPID > 0 else {
            return
        }

        guard let targetApp = NSRunningApplication(processIdentifier: targetPID) else {
            return
        }

        targetApp.activate(options: .activateAllWindows)

        var attempts = 0
        while !targetApp.isActive && attempts < 30 {
            Thread.sleep(forTimeInterval: 0.05)
            attempts += 1
        }
        Thread.sleep(forTimeInterval: 0.1)
        if let element = forceFocusElement {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
            Thread.sleep(forTimeInterval: 0.05)
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let utf16Chars = Array(text.utf16)
        utf16Chars.withUnsafeBufferPointer { buffer in
            if let ptr = buffer.baseAddress {
                event?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: ptr)
            }
        }
        event?.post(tap: .cghidEventTap)
    }


    func typeTextToken(token: String, targetPID: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let utf16Chars = Array(token.utf16)
        utf16Chars.withUnsafeBufferPointer { buffer in
            if let ptr = buffer.baseAddress {
                event?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: ptr)
            }
        }
        event?.post(tap: .cghidEventTap)
    }
}
