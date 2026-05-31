import SwiftUI

struct IncognitoExplanationView: View {
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
    
    let isFromInfo: Bool
    @AppStorage("skipIncognitoExplanation") private var skipIncognitoExplanation = false
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Upper padding spacer instead of X close button
            Spacer()
                .frame(height: 30)
            
            // Icon & Title
            VStack(spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(t("Incognito Mode"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("No statistics"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("No information about speaking time, word count, or productivity gains is recorded."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("RAM memory only"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("Audio and transcription are processed exclusively in the computer's operational memory."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Immediate deletion"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("All data is irretrievably deleted from memory immediately after transcription finishes and text is pasted."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Checkbox (only if not opened from info button, or if opened from info button and is already checked so they can reset it)
            if !isFromInfo || skipIncognitoExplanation {
                Toggle(isOn: $skipIncognitoExplanation) {
                    Text(t("Do not show this notification again"))
                        .font(.system(size: 13))
                }
                .toggleStyle(.checkbox)
                .accentColor(colorScheme == .dark ? .white : .black)
                .tint(colorScheme == .dark ? .white : .black)
                .focusable(false)
                .padding(.bottom, 16)
            }
            
            // Accept Button (Zrozumiałem)
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
