import Foundation
import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

@MainActor
class AssistantWorkflowService {
    static let shared = AssistantWorkflowService()
    
    private init() {}
    
    /// Orchestrates the entire post-transcription workflow, including optional LLM modifications,
    /// pasting text via Accessibility (AX) APIs, or falling back to the clipboard.
    /// - Parameters:
    ///   - correctedText: The transcribed string (after initial dictionary corrections).
    ///   - selectedMode: The active VoiceMode, determining if/how the LLM modifies the text.
    ///   - initialPID: Process ID of the target application to paste into.
    ///   - targetAXElement: The focused text field element where text will be injected.
    func execute(
        correctedText: String,
        selectedMode: VoiceMode,
        initialPID: pid_t,
        targetAXElement: AXUIElement?,
        wasTextFieldFocusedAtStart: Bool,
        onStatusChange: @escaping @MainActor (String) -> Void,
        onAutoLearnTrigger: @escaping @MainActor (pid_t, String) -> Void
    ) async {
        var pid = initialPID
        if selectedMode.pasteTiming == "end" {
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                pid = frontApp.processIdentifier
            }
        }
        
        // Detect whether a text field is actually focused — always, regardless of any toggle
        let isTextFieldDetected: Bool
        if selectedMode.pasteTiming == "start" {
            isTextFieldDetected = wasTextFieldFocusedAtStart
        } else {
            isTextFieldDetected = PasteManager.shared.isTextFieldFocused(pid: pid)
        }
        
        // willPaste: only paste if a text field was actually found — same behavior regardless of fallbackToClipboard
        let willPaste = isTextFieldDetected
        
        // willFallbackToClipboard: copy text to clipboard when no field found, only if user enabled this option
        let willFallbackToClipboard = !isTextFieldDetected && (selectedMode.fallbackToClipboard == true)
        
        let isPremium = AuthManager.shared.isLoggedIn && AuthManager.shared.accountTier == "premium"
        let shouldRunLLM = !selectedMode.prompt.isEmpty && isPremium
        
        if !shouldRunLLM {
            // DIRECT PASTE PATH: We skip LLM generation (e.g. for "Raw Output" mode)
            // and immediately inject the transcribed text into the target app.
            onStatusChange("Done!")
            MessageMemoryManager.shared.saveMessage(correctedText)
            
            if willPaste {
                let capturedFocusElement: AXUIElement? = (selectedMode.pasteTiming == "start") ? targetAXElement : nil
                DispatchQueue.global(qos: .userInteractive).async {
                    PasteManager.shared.typeTextDirectly(text: correctedText, targetPID: pid, forceFocusElement: capturedFocusElement)
                    Task { @MainActor in
                        onAutoLearnTrigger(pid, correctedText)
                    }
                }
            } else if willFallbackToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(correctedText, forType: .string)
            }
            // Play Error sound if no text field was detected (regardless of fallbackToClipboard setting)
            if !isTextFieldDetected {
                Task { await SoundPlayer.shared.playSound(named: "Error") }
            }
        } else {
            // LLM GENERATION PATH: The text goes through a local LLM model to apply
            // stylistic changes, corrections, or fulfill specific user commands.
            if Task.isCancelled { return }
            
            if !LLMManager.shared.isReady {
                onStatusChange("Initializing")
                await LLMManager.shared.ensureModelWarmed()
            }
            if Task.isCancelled { return }
            
            let statusLabel: String
            if selectedMode.name == "Text Smoothing" {
                statusLabel = "Text Smoothing"
            } else if selectedMode.name == "Formal Email" {
                statusLabel = "Formal Email"
            } else {
                statusLabel = "Modifying"
            }
            onStatusChange(statusLabel)
            
            let systemPrompt = buildSystemPrompt(selectedMode: selectedMode)
            if Task.isCancelled { return }
            
            if willPaste {
                if let targetApp = NSRunningApplication(processIdentifier: pid) {
                    targetApp.activate(options: .activateAllWindows)
                    var attempts = 0
                    while !targetApp.isActive && attempts < 30 {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        attempts += 1
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if selectedMode.pasteTiming == "start", let element = targetAXElement {
                    AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            
            var didStartStreaming = false
            var fullGeneratedText = ""
            
            _ = await LLMManager.shared.cleanStream(text: correctedText, systemPrompt: systemPrompt) { token in
                fullGeneratedText += token
                if !didStartStreaming {
                    didStartStreaming = true
                    Task { @MainActor in
                        onStatusChange("Streaming")
                    }
                }
                if willPaste {
                    DispatchQueue.global(qos: .userInteractive).async {
                        PasteManager.shared.typeTextToken(token: token, targetPID: pid)
                    }
                }
            }
            if Task.isCancelled { return }
            
            // Play Error sound if no text field was detected (regardless of fallbackToClipboard setting)
            if !isTextFieldDetected {
                if willFallbackToClipboard {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullGeneratedText, forType: .string)
                }
                Task { await SoundPlayer.shared.playSound(named: "Error") }
            }
            
            MessageMemoryManager.shared.saveMessage(fullGeneratedText)
            if willPaste {
                onAutoLearnTrigger(pid, fullGeneratedText)
            }
        }
        
        onStatusChange("Done!")
        if willPaste {
            await SoundPlayer.shared.playSound(named: "End")
        }
    }
    
    private func buildSystemPrompt(selectedMode: VoiceMode) -> String {
        if selectedMode.assistantType == "edit" {
            let activeAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Application"
            let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
            var contextInfo = ""
            if selectedMode.passAppName ?? true {
                contextInfo += "=== ACTIVE APPLICATION ===\n\(activeAppName)\n\n"
            }
            if (selectedMode.passCopiedText ?? true) && !clipboardText.isEmpty {
                contextInfo += "=== COPIED TEXT (CLIPBOARD) ===\n\(clipboardText)\n\n"
            }
            let langInstruction: String
            if let lang = selectedMode.language, lang != "auto" {
                let langMap: [String: String] = [
                    "pl": "Polish", "en": "English", "de": "German", "es": "Spanish",
                    "fr": "French", "it": "Italian", "pt": "Portuguese", "nl": "Dutch",
                    "ru": "Russian", "uk": "Ukrainian", "cs": "Czech", "sk": "Slovak",
                    "sv": "Swedish", "no": "Norwegian", "da": "Danish", "fi": "Finnish",
                    "zh": "Chinese", "ja": "Japanese", "ko": "Korean", "ar": "Arabic",
                    "tr": "Turkish", "hi": "Hindi", "vi": "Vietnamese", "th": "Thai",
                    "el": "Greek", "pt-BR": "Portuguese (Brazilian)", "he": "Hebrew",
                    "ro": "Romanian", "hu": "Hungarian"
                ]
                let langName = langMap[lang] ?? lang
                langInstruction = "Your response MUST be in language: \(langName)."
            } else {
                langInstruction = """
                Language priority (Automatic Mode):
                - By default, if you edit 'Copied Text', preserve the original language of that text.
                - HOWEVER, if the user explicitly requests a language change in their instruction (e.g., "translate to Polish", "write this in English", "change language to..."), you MUST fulfill this request and change the language to the requested one. The user's instruction has the highest priority!
                - If the user is creating new content, use the language in which the user is speaking (the instruction).
                """
            }
            return """
            \(selectedMode.prompt)
            Use the LLM to edit and create content based on the provided context.
            \(contextInfo.isEmpty ? "" : "Context:\n" + contextInfo)
            The user will provide instructions in the 'Text' section below. Generate the output based on this instruction and context.
            \(langInstruction)
            IMPORTANT CONTEXT RULES:
            1) Just because you received 'Copied Text' as context does not mean you MUST use it! Sense the user's intent.
            2) If the user says "write a message to...", "create...", "generate..." and does not refer to the passed text, ignore the context and create new content.
            3) If the user says "edit this text", "change this", "fix this" and does not provide other text, they refer to the 'Copied Text'.
            4) Be attentive: the user might dictate text and immediately correct it in a single statement (e.g., "Write X... wait, sorry, change X to Y"). In this case, they refer to the text they just dictated, not to the context.
            5) NEVER refuse to execute a command. Even if you think the text is too short, lacks content, or there is no point in commenting/summarizing it – execute the command to the best of your ability based on what you have.
            6) Return ONLY and EXCLUSIVELY the final result. No introductions, no explanations, no 'I am not sure', no questions. If you hesitate, choose one option and return it. Your response will be directly pasted for the user, so it cannot contain anything other than the target text.
            IMPORTANT SAFEGUARD: If there is no command or order in the 'Text' section OR if you lack the context to execute the command, DO NOT make anything up or ask questions. In this case, simply rewrite the user's text with minimal corrections (remove stutters like uh, um, oh) and return it.
            Respond ONLY with the generated content (or corrected text), without any comments and without any introductory text.
            """
        } else {
            return selectedMode.prompt
        }
    }
}
