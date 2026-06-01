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
        targetApp.activate(options: .activateIgnoringOtherApps)

        // Czekaj aż aplikacja faktycznie stanie się aktywna (max 1.5 sekundy)
        var attempts = 0
        while !targetApp.isActive && attempts < 30 {
            Thread.sleep(forTimeInterval: 0.05)
            attempts += 1
        }
        
        // Dodatkowy czas na zakończenie ewentualnych animacji systemowych
        Thread.sleep(forTimeInterval: 0.1)

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



    // MARK: - Detect Text Field Focus
    func getFocusedAXElement(pid: pid_t) -> AXUIElement? {
        guard AXIsProcessTrusted() else {
            print("⚠️ [AXDebug] System nie ufa tej aplikacji w kwestii Accessibility (AXIsProcessTrusted = false)")
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: AnyObject?
        
        // Próba 1: Pobierz bezpośrednio z aplikacji
        var focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if focusResult == .success, let element = focusedElement as! AXUIElement? {
            return element
        }
        
        print("⚠️ [AXDebug] Próba 1 (App Element) nie powiodła się z kodem: \(focusResult.rawValue). Próbuję pobrać przez aktywne okno...")
        
        // Próba 2: Pobierz z zogniskowanego okna (kAXFocusedWindowAttribute)
        var focusedWindow: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
           let windowElement = focusedWindow as! AXUIElement? {
            focusResult = AXUIElementCopyAttributeValue(windowElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            
            if focusResult == .success, let element = focusedElement as! AXUIElement? {
                print("✅ [AXDebug] Sukces! Pobrano sfokusowany element przez aktywne okno.")
                return element
            }
        }
        
        // Próba 3: Pobierz pierwsze okno z listy kAXWindowsAttribute (przydatne dla Electrona)
        print("⚠️ [AXDebug] Próba 2 (Focused Window) nie powiodła się. Próbuję przez listę wszystkich okien...")
        var windowsList: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsList) == .success,
           let windows = windowsList as? [AXUIElement], let firstWindow = windows.first {
            focusResult = AXUIElementCopyAttributeValue(firstWindow, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            
            if focusResult == .success, let element = focusedElement as! AXUIElement? {
                print("✅ [AXDebug] Sukces! Pobrano sfokusowany element przez pierwsze okno z listy.")
                return element
            }
        }
        
        print("❌ [AXDebug] Ostatecznie nie udało się pobrać sfokusowanego elementu. Ostatni kod błędu: \(focusResult.rawValue)")
        return nil
    }

    func isElementTextField(_ axElement: AXUIElement?) -> Bool {
        guard let element = axElement else { 
            print("🔍 [AXDebug] Element AXUIElement jest NIL (brak sfokusowanego obiektu) -> Zakładam wklejanie na ślepo (zwracam true)")
            return true 
        }
        
        print("🔍 [AXDebug] --- Analizuję element AXUIElement ---")
        
        var role: String = "N/A"
        var subrole: String = "N/A"
        var roleDesc: String = "N/A"
        var isEditable: Bool? = nil
        var hasInsertionPoint: Bool = false
        var valueType: String = "N/A"
        var valueDescription: String = "N/A"
        
        var roleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success {
            role = (roleValue as? String) ?? "\(String(describing: roleValue))"
        }
        
        var subroleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success {
            subrole = (subroleValue as? String) ?? "\(String(describing: subroleValue))"
        }
        
        var roleDescValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescValue) == .success {
            roleDesc = (roleDescValue as? String) ?? "\(String(describing: roleDescValue))"
        }
        
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
            isEditable = settable.boolValue
        }
        
        var insertionPoint: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, &insertionPoint) == .success {
            hasInsertionPoint = true
        }
        
        var valueVal: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueVal) == .success {
            if let valStr = valueVal as? String {
                valueType = "String"
                valueDescription = "'\(valStr.prefix(100))' (długość: \(valStr.count))"
            } else {
                valueType = "\(type(of: valueVal))"
                valueDescription = "\(String(describing: valueVal))"
            }
        }
        
        print("   🔹 Rola (Role): \(role)")
        print("   🔹 Podrola (Subrole): \(subrole)")
        print("   🔹 Opis roli (RoleDescription): \(roleDesc)")
        print("   🔹 Edytowalne (Value Settable): \(isEditable != nil ? String(isEditable!) : "Nieznane")")
        print("   🔹 Posiada kursor (InsertionPoint): \(hasInsertionPoint)")
        print("   🔹 Typ wartości: \(valueType)")
        print("   🔹 Podgląd wartości: \(valueDescription)")
        
        // List all attributes for deep inspection:
        var attributeNames: CFArray?
        if AXUIElementCopyAttributeNames(element, &attributeNames) == .success,
           let names = attributeNames as? [String] {
            print("   🔹 Wszystkie dostępne atrybuty (\(names.count)): \(names.joined(separator: ", "))")
            // Print some additional potentially interesting attributes
            for attr in ["AXPlaceholderValue", "AXSelectedTextRange", "AXNumberOfCharacters", "AXEnabled"] {
                if names.contains(attr) {
                    var val: AnyObject?
                    if AXUIElementCopyAttributeValue(element, attr as CFString, &val) == .success {
                        print("      🔸 \(attr): \(String(describing: val))")
                    }
                }
            }
        }
        
        // Zgodnie z decyzją użytkownika: jeśli pole WYRAŹNIE zgłasza, że NIE jest edytowalne,
        // to używamy schowka (zwracamy false). W każdym innym przypadku (jest edytowalne, albo
        // nie da się tego w ogóle ustalić), ryzykujemy i "wklejamy na ślepo" (zwracamy true).
        if let editable = isEditable, editable == false {
            print("❌ [AXDebug] Wynik: Fałsz (wyraźnie stwierdzono, że pole NIE jest edytowalne)")
            return false
        }
        
        print("✅ [AXDebug] Wynik: Prawda (pole edytowalne, lub nie można było jednoznacznie zaprzeczyć)")
        return true
    }

    func isTextFieldFocused(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return true } // Fallback to true if no permissions
        let element = getFocusedAXElement(pid: pid)
        return isElementTextField(element)
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
    func typeTextDirectly(text: String, targetPID: pid_t, forceFocusElement: AXUIElement? = nil) {
        guard targetPID > 0 else {
            print("❌ PasteManager: Brak prawidłowego PID docelowej aplikacji")
            return
        }

        guard let targetApp = NSRunningApplication(processIdentifier: targetPID) else {
            print("❌ PasteManager: Nie można znaleźć aplikacji o PID \(targetPID)")
            return
        }

        print("🎯 PasteManager: Aktywuję '\(targetApp.localizedName ?? "?")' (PID: \(targetPID)) dla pisania bezpośredniego")
        targetApp.activate(options: .activateIgnoringOtherApps)

        // Czekaj aż aplikacja faktycznie stanie się aktywna (max 1.5 sekundy)
        var attempts = 0
        while !targetApp.isActive && attempts < 30 {
            Thread.sleep(forTimeInterval: 0.05)
            attempts += 1
        }
        
        // Dodatkowy czas na zakończenie ewentualnych animacji systemowych
        Thread.sleep(forTimeInterval: 0.1)
        
        if let element = forceFocusElement {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
            Thread.sleep(forTimeInterval: 0.05)
        }
        
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
