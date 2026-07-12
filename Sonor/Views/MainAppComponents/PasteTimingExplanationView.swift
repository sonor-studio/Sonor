import SwiftUI

struct PasteTimingExplanationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 30)
            VStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Paste Target Explanation"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 16) {
                explanationRow(
                    title: t("Automatic"),
                    icon: "wand.and.stars",
                    description: t("Checks both at the start and at the end of dictation. Priority is given to the field focused at the end, so text is always pasted where your cursor is right now. If no field is found at the end, it will safely paste into the field that was focused when you started talking. If neither had focus, it detects 'no field'.")
                )
                
                explanationRow(
                    title: t("Field focused at start"),
                    icon: "arrow.right.to.line.compact",
                    description: t("Saves the exact text field you clicked before launching the assistant. When generating finishes, it forces the text strictly into that specific field, ignoring whatever field is active at the end.")
                )
                
                explanationRow(
                    title: t("Field focused at end"),
                    icon: "arrow.right.to.line",
                    description: t("Ignores your initial text field entirely. It will wait for the text to be fully generated, and paste it only into the field that is active at the exact moment of pasting. If none is found at the end, it detects 'no field'.")
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
        .frame(width: 440, height: 440)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
    
    private func explanationRow(title: String, icon: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 18)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
    }
}
