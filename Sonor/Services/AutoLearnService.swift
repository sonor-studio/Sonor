import Foundation
import AppKit

@MainActor
class AutoLearnService {
    static let shared = AutoLearnService()
    
    private init() {}
    
    func getFocusedElementText(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusResult == .success, let element = focusedElement else { return nil }
        let axElement = element as! AXUIElement
        var currentValue: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValue)
        guard valueResult == .success else { return nil }
        return currentValue as? String
    }
    
    func startAutoLearnTracking(targetPID: pid_t, originalText: String, currentNotification: DictionaryNotification?, onNotification: @escaping @MainActor (DictionaryNotification) -> Void) {
        guard UserDefaults.standard.bool(forKey: "autoLearnDictionary") else { return }
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) 
            guard let initialText = await MainActor.run(body: { self.getFocusedElementText(pid: targetPID) }),
                  !initialText.isEmpty else {
                return
            }
            var lastText = initialText
            var latestNotification = currentNotification
            
            for _ in 1...3 {
                try? await Task.sleep(nanoseconds: 3_000_000_000) 
                guard let currentText = await MainActor.run(body: { self.getFocusedElementText(pid: targetPID) }) else {
                    continue
                }
                if currentText != lastText {
                    let corrections = TextProcessingService.shared.detectWordCorrections(from: initialText, to: currentText)
                    if !corrections.isEmpty {
                        await MainActor.run {
                            if let newNotification = self.addDictionaryEntries(corrections: corrections, currentNotification: latestNotification) {
                                latestNotification = newNotification
                                onNotification(newNotification)
                            }
                        }
                    }
                    lastText = currentText
                }
            }
        }
    }
    
    func addDictionaryEntries(corrections: [(wrong: String, correct: String)], currentNotification: DictionaryNotification?) -> DictionaryNotification? {
        var newLearnedEntries: [LearnedEntry] = []
        var dictionary = UserDefaults.standard.dictionary(forKey: "dictionaryEntries") as? [String: String] ?? [:]
        
        var accumulatedLearnedEntries = currentNotification?.learnedEntries ?? []
        for correction in corrections {
            let wrong = correction.wrong
            let correct = correction.correct
            let originalPrev: String?
            if let existingIndex = accumulatedLearnedEntries.firstIndex(where: { $0.wrong == wrong }) {
                originalPrev = accumulatedLearnedEntries[existingIndex].previousValue
            } else {
                originalPrev = dictionary[wrong]
            }
            dictionary[wrong] = correct
            let entry = LearnedEntry(wrong: wrong, correct: correct, previousValue: originalPrev)
            newLearnedEntries.append(entry)
            if let existingIndex = accumulatedLearnedEntries.firstIndex(where: { $0.wrong == wrong }) {
                accumulatedLearnedEntries[existingIndex] = entry
            } else {
                accumulatedLearnedEntries.append(entry)
            }
        }
        UserDefaults.standard.set(dictionary, forKey: "dictionaryEntries")
        NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
        
        if let lastEntry = newLearnedEntries.last {
            return DictionaryNotification(
                wrong: lastEntry.wrong,
                correct: lastEntry.correct,
                learnedEntries: accumulatedLearnedEntries
            )
        }
        return nil
    }
    
    func undoDictionaryEntry(notification: DictionaryNotification) {
        var dictionary = UserDefaults.standard.dictionary(forKey: "dictionaryEntries") as? [String: String] ?? [:]
        for entry in notification.learnedEntries {
            if let prev = entry.previousValue {
                dictionary[entry.wrong] = prev
            } else {
                dictionary.removeValue(forKey: entry.wrong)
            }
        }
        UserDefaults.standard.set(dictionary, forKey: "dictionaryEntries")
        NotificationCenter.default.post(name: Notification.Name("VoiceModesUpdated"), object: nil)
    }
}
