import Foundation
import CoreGraphics

enum AudioBehavior: String, Codable, CaseIterable {
    case keep
    case mute
    case pause
}


struct VoiceMode: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var prompt: String
    var boundAppBundleIDs: [String]
    var audioBehavior: AudioBehavior?
    var assistantType: String? 
    var passAppName: Bool?
    var passCopiedText: Bool?
    var language: String? 
    var isBuiltIn: Bool? 
    var pasteTiming: String? 
    var fallbackToClipboard: Bool?
    init(id: UUID = UUID(), name: String, prompt: String, boundAppBundleIDs: [String] = [], audioBehavior: AudioBehavior? = .keep, assistantType: String? = "dictation", passAppName: Bool? = true, passCopiedText: Bool? = true, language: String? = "auto", isBuiltIn: Bool? = false, pasteTiming: String? = "start", fallbackToClipboard: Bool? = false) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.boundAppBundleIDs = boundAppBundleIDs
        self.audioBehavior = audioBehavior
        self.assistantType = assistantType
        self.passAppName = passAppName
        self.passCopiedText = passCopiedText
        self.language = language
        self.isBuiltIn = isBuiltIn
        self.pasteTiming = pasteTiming
        self.fallbackToClipboard = fallbackToClipboard
    }
    var isBuiltInMode: Bool {
        if isBuiltIn == true {
            return true
        }
        let builtInNames = ["Raw Output", "Text Smoothing", "Formal Style", "Casual Style", "Edit & Create", "Zwykły output", "Wygładzanie tekstu", "Styl formalny", "Luźny styl", "Edycja i tworzenie"]
        return builtInNames.contains(name)
    }
    static let defaults: [VoiceMode] = [
        VoiceMode(name: "Raw Output", prompt: "", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Text Smoothing", prompt: "You are a professional text editor. Your goal is to transform a raw speech transcript into a clean, structured, and readable text while preserving the original intent of the author.\n\nStrictly adhere to the following rules:\n1. Filter thoughts: Remove all stutters, repetitions, and filler words.\n2. Smart correction: If the author changes their mind while speaking (e.g., 'I'll do A... no, wait, B'), include ONLY the final decision. Remove the entire hesitation and plan-changing process. Present ONLY the synthetic final result. Do not analyze or repeat the thought process behind the changes in the source text.\n3. Formatting: Autonomously divide the text into logical paragraphs. If you detect a list of steps, plans, or items, create a clear list.\n4. NO MARKDOWN OR HTML: Use absolutely no asterisks (*), hashes (#), dashes (-), or HTML tags.\n5. Lists: To create lists, use exclusively numbers with periods (e.g., 1. 2. 3.) and standard spaces.\n\nDo not add any comments of your own at the beginning or end. Return only the final text.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Formal Style", prompt: "Rewrite the following text into a professional, elegant, and formal style. Do NOT write an email. Do NOT add greetings or sign-offs (e.g. 'Dear X', 'Best regards', 'Sincerely'). Simply elevate the vocabulary and tone to be formal and polite.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Casual Style", prompt: "Rewrite the following text into a casual, relaxed, and conversational style. You may use common colloquialisms or slang, but do not exaggerate or make it sound unnatural. Keep it friendly and laid-back. Do NOT add greetings or sign-offs.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Edit & Create", prompt: "Act as an expert copywriter. Modify or generate text exactly as requested by the user, while maintaining the appropriate tone.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "edit", isBuiltIn: true)
    ]
    static func loadAndMigrateModes() -> [VoiceMode] {
        guard let voiceModesData = UserDefaults.standard.data(forKey: "voiceModes") else {
            save(defaults)
            return defaults
        }
        var modes = [VoiceMode]()
        if let decoded = try? JSONDecoder().decode([VoiceMode].self, from: voiceModesData) {
            modes = decoded
        } else {
            struct OldVoiceMode: Codable {
                var id: UUID
                var name: String
                var prompt: String
                var boundAppBundleIDs: [String]
                var pauseMusic: Bool
                var assistantType: String?
                var passAppName: Bool?
                var passCopiedText: Bool?
                var language: String?
                var isBuiltIn: Bool?
            }
            if let oldModes = try? JSONDecoder().decode([OldVoiceMode].self, from: voiceModesData) {
                modes = oldModes.map { old in
                    VoiceMode(
                        id: old.id,
                        name: old.name,
                        prompt: old.prompt,
                        boundAppBundleIDs: old.boundAppBundleIDs,
                        audioBehavior: old.pauseMusic ? .mute : .keep,
                        assistantType: old.assistantType,
                        passAppName: old.passAppName,
                        passCopiedText: old.passCopiedText,
                        language: old.language,
                        isBuiltIn: old.isBuiltIn,
                        pasteTiming: "start",
                        fallbackToClipboard: false
                    )
                }
            } else {
                save(defaults)
                return defaults
            }
        }
        let deprecatedNames = ["Poprawianie", "Formalny", "Strukturyzowana notatka", "Structured Note", "Notatka markdown", "Notatka Markdown", "Markdown Note"]
        modes.removeAll(where: { deprecatedNames.contains($0.name) })
        
        let aliases: [String: [String]] = [
            "Raw Output": ["Zwykły output"],
            "Text Smoothing": ["Wygładzanie tekstu"],
            "Formal Style": ["Formalny e-mail", "Formal Email", "Styl formalny"],
            "Casual Style": ["Luźny styl"],
            "Edit & Create": ["Edycja i tworzenie"]
        ]
        
        for (defaultIndex, defaultMode) in defaults.enumerated() {
            let targetName = defaultMode.name
            var namesToMatch = aliases[targetName] ?? []
            namesToMatch.append(targetName)
            
            let matchingIndices = modes.indices.filter { namesToMatch.contains(modes[$0].name) }
            
            if let firstIndex = matchingIndices.first {
                modes[firstIndex].name = targetName
                modes[firstIndex].isBuiltIn = true
                modes[firstIndex].prompt = defaultMode.prompt
                
                // Remove all subsequent duplicates
                for duplicateIndex in matchingIndices.dropFirst().reversed() {
                    modes.remove(at: duplicateIndex)
                }
            } else {
                let insertIndex = min(modes.count, defaultIndex)
                modes.insert(defaultMode, at: insertIndex)
            }
        }
        for i in 0..<modes.count {
            if modes[i].audioBehavior == .pause {
                modes[i].audioBehavior = .mute
            }
        }
        
        save(modes)
        return modes
    }
    private static func save(_ modes: [VoiceMode]) {
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: "voiceModes")
        }
    }
}
