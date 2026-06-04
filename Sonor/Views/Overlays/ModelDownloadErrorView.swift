import SwiftUI

struct ModelDownloadErrorView: View {
    let error: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 30)
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                Text(t("Download Interrupted"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Connection lost or timeout"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("The model download could not be completed. Network connection might be unstable."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.clockwise.icloud.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Safe to resume"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("You can safely resume the download later without losing progress."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.horizontal, 24)
            Spacer()
            Button(action: { dismiss() }) {
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
            .padding(.bottom, 30)
        }
        .frame(width: 320, height: 380)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}
