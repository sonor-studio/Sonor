import SwiftUI

struct SnippetsExplanationView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("appTheme") private var appTheme = "system"
    var colorScheme: ColorScheme {
        if appTheme == "dark" {
            return .dark
        } else if appTheme == "light" {
            return .light
        } else {
            let appleInterfaceStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
            return appleInterfaceStyle == "Dark" ? .dark : .light
        }
    }
    
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 30)
            
            VStack(spacing: 12) {
                Image(systemName: "scissors")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(t("Custom Snippets"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 16) {
                InfoBulletRow(
                    icon: "scissors",
                    title: t("Voice Shortcuts"),
                    description: t("Create voice-activated macros. Speak a short keyword, and Sonor will expand it into a pre-defined text block."),
                    colorScheme: colorScheme
                )
                
                InfoBulletRow(
                    icon: "doc.text.fill",
                    title: t("Message Templates"),
                    description: t("Perfect for long email templates, standard responses, links, or code blocks that you speak frequently."),
                    colorScheme: colorScheme
                )
                
                InfoBulletRow(
                    icon: "keyboard",
                    title: t("Instant Injection"),
                    description: t("The expanded text is immediately injected into your active cursor position, making voice typing faster than ever."),
                    colorScheme: colorScheme
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            Button(action: {
                dismiss()
            }) {
                Text(t("I understand"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 430)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}
