import Foundation
import AppKit

class TextProcessingService {
    static let shared = TextProcessingService()
    
    private init() {}
    
    func parseDynamicVariables(in text: String) -> String {
        var result = text
        if result.contains("{{clipboard}}") {
            let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
            result = result.replacingOccurrences(of: "{{clipboard}}", with: clipboardText)
        }
        if result.contains("{{date}}") {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            result = result.replacingOccurrences(of: "{{date}}", with: formatter.string(from: Date()))
        }
        if result.contains("{{time}}") {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            result = result.replacingOccurrences(of: "{{time}}", with: formatter.string(from: Date()))
        }
        if result.contains("{{active_app}}") {
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
            result = result.replacingOccurrences(of: "{{active_app}}", with: appName)
        }
        if result.contains("{{day_of_week}}") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: LocalizationManager.shared.appLanguage)
            formatter.dateFormat = "EEEE"
            let dayName = formatter.string(from: Date())
            result = result.replacingOccurrences(of: "{{day_of_week}}", with: dayName)
        }
        return result
    }
    
    func applyCorrections(to text: String, isLoggedIn: Bool) -> String {
        guard isLoggedIn else { return text }
        var processedText = text
        let dictionary = UserDefaults.standard.dictionary(forKey: "dictionaryEntries") as? [String: String] ?? [:]
        for (wrong, correct) in dictionary {
            processedText = processedText.replacingOccurrences(of: wrong, with: correct, options: .caseInsensitive)
        }
        let snippets = UserDefaults.standard.dictionary(forKey: "snippetsEntries") as? [String: String] ?? [:]
        for (shortcut, expansion) in snippets {
            let parsedExpansion = parseDynamicVariables(in: expansion)
            processedText = processedText.replacingOccurrences(of: shortcut, with: parsedExpansion, options: .caseInsensitive)
        }
        return processedText
    }
    
    func detectWordCorrections(from initial: String, to current: String) -> [(wrong: String, correct: String)] {
        let initialWords = initial.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let currentWords = current.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard initialWords != currentWords else { return [] }
        let diff = currentWords.difference(from: initialWords)
        var removes: [(index: Int, word: String)] = []
        var inserts: [(index: Int, word: String)] = []
        for change in diff {
            switch change {
            case .remove(let offset, let element, _):
                removes.append((offset, element))
            case .insert(let offset, let element, _):
                inserts.append((offset, element))
            }
        }
        removes.sort { $0.index < $1.index }
        inserts.sort { $0.index < $1.index }
        var corrections: [(wrong: String, correct: String)] = []
        if removes.count <= 2 && inserts.count <= 2 && !removes.isEmpty && !inserts.isEmpty {
            let wrong = removes.map { $0.word }.joined(separator: " ")
            let correct = inserts.map { $0.word }.joined(separator: " ")
            corrections.append((wrong: wrong, correct: correct))
        }
        return corrections
    }
}
