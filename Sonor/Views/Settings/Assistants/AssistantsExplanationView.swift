import SwiftUI

struct AssistantsExplanationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 30)
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("AI Assistants"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 16) {
                InfoBulletRow(
                    icon: "sparkles",
                    title: t("Tailored Output"),
                    description: t("Assistants process your transcription using customizable prompts. You can format transcripts into emails, notes, lists, or clean prose automatically."),
                    colorScheme: colorScheme
                )
                InfoBulletRow(
                    icon: "slider.horizontal.3",
                    title: t("Infinite Customization"),
                    description: t("Create as many specialized assistants as you need, defining specific instructions, tone of voice, and formatting styles."),
                    colorScheme: colorScheme
                )
                InfoBulletRow(
                    icon: "wand.and.stars",
                    title: t("Smart Presets"),
                    description: t("Get started instantly with built-in templates for professional emails, summaries, or structured lists."),
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
