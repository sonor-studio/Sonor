import Foundation
import AppKit
import ApplicationServices

class PasteManager {
    static let shared = PasteManager()
    private init() {}

    /// Wkleja tekst do docelowej aplikacji używając 3-stopniowej strategii:
    /// 1. AXUIElement – bezpośredni zapis do focused element (najniezawodniejsza)
    /// 2. Activate + CGEvent Cmd+V przez .cghidEventTap (działa bez PID restriction)
    /// 3. Activate + symulacja klawiszy z opóźnieniem
    func pasteTextToActiveApp(text: String, targetPID: pid_t) {
        guard targetPID > 0 else {
            print("❌ PasteManager: Brak prawidłowego PID docelowej aplikacji")
            return
        }

        // 1. Aktywuj docelową aplikację i poczekaj aż przejmie focus
        guard let targetApp = NSRunningApplication(processIdentifier: targetPID) else {
            print("❌ PasteManager: Nie można znaleźć aplikacji o PID \(targetPID)")
            return
        }

        print("🎯 PasteManager: Aktywuję '\(targetApp.localizedName ?? "?")' (PID: \(targetPID))")
        targetApp.activate()

        // Daj systemowi czas na przełączenie focusu
        Thread.sleep(forTimeInterval: 0.15)

        // 2. Spróbuj bezpośredniego zapisu przez AX API (nie używa schowka)
        if tryAXInsert(text: text, pid: targetPID) {
            print("✅ PasteManager: Sukces przez AX API (schowek nienaruszony)")
            return
        }

        // 3. Fallback: Jeśli AX zawiedzie, użyj schowka i Cmd+V
        print("⚠️ PasteManager: AX nie zadziałało, używam schowka...")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        tryCGEventPaste()
        
        // 4. Usuń tekst ze schowka po krótkim czasie (aby aplikacja zdążyła go wkleić)
        // Zwiększamy opóźnienie i wymuszamy czyszczenie bez sprawdzania stringa (bardziej agresywne)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let pb = NSPasteboard.general
            pb.clearContents()
            print("🧹 PasteManager: Schowek wyczyszczony definitywnie")
        }
    }



    // MARK: - AX Insert (Primary)

    private func tryAXInsert(text: String, pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else {
            print("⚠️ PasteManager: Brak uprawnień Accessibility")
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)

        // Pobierz aktualnie sfocusowany element
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard focusResult == .success, let element = focusedElement else {
            print("⚠️ PasteManager: Nie można pobrać focused element (kod: \(focusResult.rawValue))")
            return false
        }

        guard let element = focusedElement else {
            print("⚠️ PasteManager: Nie można pobrać focused element (kod: \(focusResult.rawValue))")
            return false
        }
        
        let axElement = element as! AXUIElement

        // Sprawdź czy element jest edytowalny
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &settable)

        guard settable.boolValue else {
            print("⚠️ PasteManager: Focused element nie jest edytowalny")
            return false
        }

        // Pobierz aktualną wartość i pozycję kursora
        var currentValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValue)

        var selectedRange: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
        
        if let rangeValue = selectedRange,
           CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            
            let axValue = rangeValue as! AXValue
            
            var range = CFRange()
            AXValueGetValue(axValue, .cfRange, &range)

            // Wstaw tekst w miejscu kursora
            let currentStr = (currentValue as? String) ?? ""
            let nsStr = currentStr as NSString
            
            // Bezpieczne sprawdzenie zakresu
            let safeLocation = max(0, min(range.location, nsStr.length))
            let safeLength = max(0, min(range.length, nsStr.length - safeLocation))
            let safeRange = NSRange(location: safeLocation, length: safeLength)

            let newStr = nsStr.replacingCharacters(in: safeRange, with: text)

            let setResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, newStr as CFTypeRef)

            if setResult == .success {
                // Przesuń kursor na koniec wstawionego tekstu
                var newRange = CFRange(location: safeLocation + text.count, length: 0)
                if let newRangeValue = AXValueCreate(.cfRange, &newRange) {
                    AXUIElementSetAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, newRangeValue)
                }
                return true
            } else {
                print("⚠️ PasteManager: AXSetValue failed (kod: \(setResult.rawValue))")
            }
        }

        // Fallback wewnątrz AX: ustaw pełną wartość (jeśli pole jest puste)
        let setResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFTypeRef)
        return setResult == .success
    }

    // MARK: - CGEvent Paste (Fallback)

    private func tryCGEventPaste() {
        // Użyj .cghidEventTap zamiast postToPid – omija ograniczenia sandboxu dla zdarzeń
        let src = CGEventSource(stateID: .hidSystemState)

        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let vUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags   = .maskCommand

        vDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        vUp?.post(tap: .cghidEventTap)

        print("✅ PasteManager: CGEvent Cmd+V wysłany przez .cghidEventTap")
    }

    // MARK: - Method 1: Virtual Typing

    /// Wpisuje tekst płynnie (bezpośrednio ze znaków Unicode) bez ingerowania w schowek.
    func typeTextDirectly(text: String, targetPID: pid_t) {
        guard targetPID > 0 else {
            print("❌ PasteManager: Brak prawidłowego PID docelowej aplikacji")
            return
        }

        guard let targetApp = NSRunningApplication(processIdentifier: targetPID) else {
            print("❌ PasteManager: Nie można znaleźć aplikacji o PID \(targetPID)")
            return
        }

        print("🎯 PasteManager: Aktywuję '\(targetApp.localizedName ?? "?")' (PID: \(targetPID)) dla pisania bezpośredniego")
        targetApp.activate()

        // Daj systemowi czas na przełączenie focusu
        Thread.sleep(forTimeInterval: 0.15)
        
        // Funkcja CGEvent.keyboardSetUnicodeString to prawidłowa metoda uiszczania całego tekstu Unicode na evencie
        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        
        let utf16Chars = Array(text.utf16)
        utf16Chars.withUnsafeBufferPointer { buffer in
            if let ptr = buffer.baseAddress {
                event?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: ptr)
            }
        }
        
        event?.post(tap: .cghidEventTap)
        print("✅ PasteManager: Virtual Typing zakończone (bez użycia schowka)")
    }

    // MARK: - Method 2: Fine-Grained Typing (Token by Token)

    /// Wpisuje tekst w postaci pojedynczych tokenów (np. słów) z opóźnieniem między nimi.
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
