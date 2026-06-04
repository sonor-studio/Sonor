import SwiftUI

struct DictionaryExplanationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 30)
            VStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Intelligent Dictionary"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 16) {
                InfoBulletRow(
                    icon: "pencil.and.outline",
                    title: t("Phonetic Corrections"),
                    description: t("Teach Sonor how to correctly write words it often mishears, such as specific names, technical jargon, or uncommon terms."),
                    colorScheme: colorScheme
                )
                InfoBulletRow(
                    icon: "arrow.right.arrow.left",
                    title: t("Automatic Replacement"),
                    description: t("Define rules to automatically replace specific phrases. For example, change 'superbase' to 'Supabase' instantly upon transcription."),
                    colorScheme: colorScheme
                )
                InfoBulletRow(
                    icon: "checkmark.circle.fill",
                    title: t("Enhanced Accuracy"),
                    description: t("Significantly improve recognition of specialized vocabulary, brand names, and complex technical terminology."),
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
