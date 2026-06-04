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
        let builtInNames = ["Raw Output", "Text Smoothing", "Formal Email", "Structured Note", "Edit & Create", "Zwykły output", "Wygładzanie tekstu", "Formalny e-mail", "Ustrukturyzowana notatka", "Edycja i tworzenie"]
        return builtInNames.contains(name)
    }
    static let defaults: [VoiceMode] = [
        VoiceMode(name: "Raw Output", prompt: "", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Text Smoothing", prompt: "Clean up and organize this spoken text. Remove stuttering, filler words, repetitions, speech errors, and grammatical mistakes. Add appropriate punctuation. Preserve 100% of the original meaning, vocabulary, and tone (do not change it to formal or any other style).\n\nCRITICAL: Detect the language of the input text and respond in the EXACT SAME language. Do not translate the text under any circumstances. Reply ONLY with the cleaned-up text.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Formal Email", prompt: "Transform this spoken text into a professional, elegant, and formal business email in the language of the spoken text. Retain all key information, requests, and points, but elevate the style from casual spoken thoughts to formal business correspondence.\n\nCRITICAL: Detect the language of the input text and respond in the EXACT SAME language. Do not translate the text under any circumstances. Reply ONLY with the email content.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Structured Note", prompt: "Organize this spoken text and convert it into a clear, structured note.\nUse ONLY plain text.\n\nKey formatting and content rules:\n1. NO EXTRAPOLATION: Structure only the information that was directly spoken. Do not add your own thoughts, action plans, 'to consider' sections, or extra suggestions not dictated by the user. If the user mentioned not needing something, simply omit it or record it exactly as spoken without adding comments or advice at the bottom.\n2. PARAGRAPH BREAKS: Separate related thoughts into clean paragraphs with empty lines.\n3. INDENTATION: Use appropriate spacing (tabs/spaces) at the start of lines to create a visual hierarchical structure for sub-bullets.\n4. HEADERS: If the text naturally divides into sections, highlight headers using UPPERCASE letters only (e.g., SHOPPING LIST, NOTES). Do not create artificial introduction sections (like INTRODUCTION).\n\nCRITICAL: Detect the language of the input text and respond in the EXACT SAME language. Do not translate the text under any circumstances. Reply ONLY with the formatted plain text, with no introductory or concluding remarks.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "dictation", isBuiltIn: true),
        VoiceMode(name: "Edit & Create", prompt: "Act as an expert copywriter and editor. Your task is to edit or create text based on the user's spoken instructions. The user may ask you to rewrite a specific text they highlighted, or they may ask you to generate something entirely new based on their description.\n\nCRITICAL: Detect the language of the input text and respond in the EXACT SAME language. Reply ONLY with the final text, without any conversational filler, introductory, or concluding remarks.", boundAppBundleIDs: [], audioBehavior: .keep, assistantType: "edit", isBuiltIn: true)
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
        let oldBuiltInNames = ["Poprawianie", "Formalny", "Strukturyzowana notatka"]
        modes.removeAll(where: { oldBuiltInNames.contains($0.name) && ($0.isBuiltIn == true) })
        let markdownNoteNames = ["Notatka markdown", "Notatka Markdown", "Markdown Note"]
        modes.removeAll(where: { markdownNoteNames.contains($0.name) })
        if let index = modes.firstIndex(where: { $0.name == "Zwykły output" || $0.name == "Raw Output" }) {
            modes[index].name = "Raw Output"
            modes[index].isBuiltIn = true
            modes[index].prompt = ""
        } else {
            if !modes.contains(where: { $0.name == "Raw Output" }) {
                modes.insert(defaults[0], at: 0)
            }
        }
        if let index = modes.firstIndex(where: { $0.name == "Wygładzanie tekstu" || $0.name == "Text Smoothing" }) {
            modes[index].name = "Text Smoothing"
            modes[index].isBuiltIn = true
            modes[index].prompt = defaults[1].prompt
        } else {
            if !modes.contains(where: { $0.name == "Text Smoothing" }) {
                modes.insert(defaults[1], at: min(modes.count, 1))
            }
        }
        if let index = modes.firstIndex(where: { $0.name == "Formalny e-mail" || $0.name == "Formal Email" }) {
            modes[index].name = "Formal Email"
            modes[index].isBuiltIn = true
            modes[index].prompt = defaults[2].prompt
        } else {
            if !modes.contains(where: { $0.name == "Formal Email" }) {
                modes.insert(defaults[2], at: min(modes.count, 2))
            }
        }
        if let index = modes.firstIndex(where: { $0.name == "Ustrukturyzowana notatka" || $0.name == "Structured Note" }) {
            modes[index].name = "Structured Note"
            modes[index].isBuiltIn = true
            modes[index].prompt = defaults[3].prompt
        } else {
            if !modes.contains(where: { $0.name == "Structured Note" }) {
                modes.insert(defaults[3], at: min(modes.count, 3))
            }
        }
        if let index = modes.firstIndex(where: { $0.name == "Edycja i tworzenie" || $0.name == "Edit & Create" }) {
            modes[index].name = "Edit & Create"
            modes[index].isBuiltIn = true
            modes[index].prompt = defaults[4].prompt
        } else {
            if !modes.contains(where: { $0.name == "Edit & Create" }) {
                modes.insert(defaults[4], at: min(modes.count, 4))
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
