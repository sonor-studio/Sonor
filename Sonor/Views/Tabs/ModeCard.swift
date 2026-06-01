import SwiftUI

struct ModeCard: View {
    let mode: VoiceMode
    let isSelected: Bool
    let isPremium: Bool
    let isRawOutput: Bool
    let onSelect: () -> Void
    let onSettings: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    @ObservedObject private var localizer = LocalizationManager.shared
    
    private var tagBgColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.black : Color.white
        } else {
            return colorScheme == .dark ? Color.white : Color.black
        }
    }
    
    private var tagFgColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white : Color.black
        } else {
            return colorScheme == .dark ? Color.black : Color.white
        }
    }
    
    private var descriptionText: String {
        if mode.isBuiltInMode {
            switch mode.name {
            case "Raw Output", "Zwykły output":
                return t("Performs pure 1:1 transcription of your speech, without any corrections or AI editing.")
            case "Text Smoothing", "Wygładzanie tekstu":
                return t("Removes stutters, repetitions, and grammatical errors and inserts appropriate punctuation. Preserves the original style, tone, and vocabulary of your statement.")
            case "Formal Email", "Formalny e-mail":
                return t("Automatically transforms loose thoughts into professional, elegant, and official business correspondence. Ideal for writing emails quickly.")
            case "Structured Note", "Ustrukturyzowana notatka":
                return t("Reorganizes dictated thoughts into an extremely neat text note. Uses spacing, indents, and traditional lists (e.g. 1., 2. or -).")
            case "Edit & Create", "Edycja i tworzenie":
                return t("Acts as an expert editor. It perfectly executes your spoken instructions to edit, rewrite, or generate brand new texts. Ideal for creating custom content on the fly.")
            default:
                return t("Built-in system assistant.")
            }
        } else {
            return mode.prompt.isEmpty ? t("Plain recording without a prompt.") : mode.prompt
        }
    }
    
    var body: some View {
        ZStack {
            // Main Card Content
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t(mode.name))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isSelected ? (colorScheme == .dark ? .black : .white) : .primary)
                    Spacer()
                    
                    if isRawOutput {
                        Text(t("Main Assistant"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(tagFgColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tagBgColor)
                            .cornerRadius(6)
                    }
                }
                
                Text(descriptionText)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? (colorScheme == .dark ? .black.opacity(0.7) : .white.opacity(0.7)) : .secondary)
                    .lineLimit(isRawOutput ? 2 : 4)
                
                Spacer()
                
                HStack {
                    Image(systemName: mode.assistantType == "dictation" ? "pencil" : "wand.and.stars")
                        .font(.system(size: 12))
                    Text(mode.assistantType == "dictation" ? t("Dictation") : t("Editing"))
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                    
                    if mode.audioBehavior == .mute || mode.audioBehavior == .pause {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 12))
                    }
                }
                .foregroundColor(isSelected ? (colorScheme == .dark ? .black.opacity(0.7) : .white.opacity(0.7)) : .secondary)
            }
            .padding(15)
            .blur(radius: isPremium || isRawOutput ? 0 : 3.5)
            
            // Premium Lock Overlay
            if !isPremium && !isRawOutput {
                Color.black.opacity(0.2)
                    .cornerRadius(16)
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                    Text("PREMIUM")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(5)
                }
            }
        }
        .frame(height: isRawOutput ? 120 : 160)
        .background(cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.gray : Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        .scaleEffect(isHovered && (isPremium || isRawOutput) ? 1.02 : 1.0)
        .allowsHitTesting(isPremium || isRawOutput)
        .onHover { h in 
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = h
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            colorScheme == .dark ? Color.white : Color.black
        } else {
            Color.clear
                .safeGlassEffect(cornerRadius: 16)
        }
    }
}
