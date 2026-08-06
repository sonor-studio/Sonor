import SwiftUI

struct AssistantTypeExplanationView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 30)
            VStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Assistant Types"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Dictation & Correction"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                        Text(t("The assistant acts as an advanced corrector. It listens to your voice and intelligently formats it by adding punctuation, removing filler words (like 'umm'), and fixing grammatical errors while strictly maintaining your original meaning. It does not add new information."))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "applepencil.and.scribble")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Editing & Creation"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                        Text(t("The assistant acts as a creative co-author. Instead of just dictating text, you can speak out instructions like 'Summarize this text in 3 points' or 'Reply to this email politely'. Sonor will actively generate new content or significantly rewrite existing text based on your prompt."))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text(t("Understood"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .frame(width: 200)
                    .padding(.vertical, 12)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 480)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}
