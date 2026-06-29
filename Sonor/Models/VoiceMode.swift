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
        let builtInNames = ["Pure Text", "Text Smoothing", "Formal Style", "Casual Style", "Edit & Create", "Czysty tekst", "Wygładzanie tekstu", "Styl formalny", "Luźny styl", "Edycja i tworzenie"]
        return builtInNames.contains(name)
    }
    static let defaults: [VoiceMode] = [
        VoiceMode(name: "Pure Text", prompt: "", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Text Smoothing", prompt: "You are an intelligent note-taker. Your job is to rewrite chaotic voice memos into clear, professional, yet naturally sounding messages.\nRULES:\nRESOLVE CONTRADICTIONS: If the speaker changes their mind (e.g., \"6 people... wait, 4\" or \"all evening... actually until 8\"), write ONLY the absolute final decision. Ignore abandoned ideas.\n2. **THE DYNAMIC STRUCTURE:** \n   - Start with an introductory sentence keeping the speaker's original framing.\n   - LIST CONDITION: If (and ONLY if) there are distinct action items, rules, or sequential steps, use a numbered list (1. 2. 3.). If the text is just a general thought, statement, or observation without actionable steps, DO NOT create a list at all. Just write standard paragraphs.\n   - End with a normal closing sentence ONLY if the speaker gave a final thought.\nPRESERVE ORIGINAL TONE: Maintain the user's casual or direct tone. Do not make it sound like a stiff corporate email (e.g., avoid adding \"Here is what we decided\").\nZERO HALLUCINATIONS: Do not invent polite sign-offs (like \"Let me know if you have questions\") unless the speaker actually said them. DO NOT start your response with \"Here is the text\" or any filler words.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Formal Style", prompt: "Rewrite the following text into a professional, elegant, and formal style.\nCRITICAL RULE: Do NOT transform regular text into an email. Intelligently detect if the provided text is already formatted as an email. If it is NOT an email, strictly preserve its original format without adding any email-specific elements like greetings or farewells. If it IS an email, simply elevate its tone to be more formal while keeping its existing structure.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Casual Style", prompt: "Rewrite the raw text into a casual, relaxed, and conversational style. \nYou may use common colloquialisms, but do not exaggerate or make it sound unnatural. Keep it friendly and laid-back.\n\nCRITICAL RULES:\n1. FORMAT INTEGRITY: \n   - IF the input text includes a subject, greeting, or sign-off, maintain an e-mail/message structure. However, make these elements casual too (e.g., change \"Dear Team\" to \"Hey everyone\", or \"Sincerely\" to \"Cheers\" / \"Best\").\n   - IF the input text is a note or general statement without greetings, do NOT add a subject, greeting, or sign-off.\n2. CONCISENESS: Return ONLY the rewritten text. No introductions, no explanations, and no filler text.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Edit & Create", prompt: "Act as an expert copywriter. Execute the user's command to create new content or edit existing context, ensuring a highly professional and appropriate tone.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "edit", isBuiltIn: true)
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
            "Pure Text": ["Raw Output", "Zwykły output", "Czysty tekst"],
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
