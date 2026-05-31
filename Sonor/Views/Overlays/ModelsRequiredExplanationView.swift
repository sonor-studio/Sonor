import SwiftUI

struct ModelsRequiredExplanationView: View {
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
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 30)
            
            VStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(t("Models Required"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Download necessary"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("In order to use Sonor and Whisper transcription, you must download the required AI models first in the Models tab."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Offline capability"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("Once downloaded, the models run 100% locally on your computer without internet access."))
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
