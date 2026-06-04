import SwiftUI

struct AudioPermissionExplanationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var onAccept: () -> Void
    var onCancel: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: {
                    onCancel()
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding([.top, .trailing], 16)
            }
            VStack(spacing: 12) {
                Image(systemName: "pause.rectangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Smart Pause (Experimental)"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            .padding(.top, -10)
            VStack(alignment: .leading, spacing: 20) {
                Text(t("For Sonor to automatically pause media (e.g. YouTube, Netflix), it needs Screen Recording access (ScreenCaptureKit)."))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineSpacing(2)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "questionmark.video.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Why does the system ask for Screen Recording?"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("Sonor does not record or see your screen. It only analyzes whether your Mac is currently outputting audio packets."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("100% Privacy"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("Sonor is an open-source project. You can always check the code yourself on GitHub to see exactly how this works."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.horizontal, 24)
            Spacer()
            Button(action: {
                onAccept()
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
        .frame(width: 440, height: 460)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}
