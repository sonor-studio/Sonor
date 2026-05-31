import SwiftUI

struct RamHistoryExplanationView: View {
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
    @ObservedObject private var memoryManager = MessageMemoryManager.shared
    
    var body: some View {
        let isRAM = memoryManager.historyStorageType == "RAM"
        
        VStack(spacing: 0) {
            // Upper padding spacer instead of X close button
            Spacer()
                .frame(height: 30)
            
            // Icon & Title
            VStack(spacing: 12) {
                Image(systemName: isRAM ? "clock.arrow.circlepath" : "doc.text.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(t(isRAM ? "Text History Privacy" : "Persistent History Privacy"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                if isRAM {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Stored only in RAM"))
                               .font(.system(size: 12, weight: .bold))
                            Text(t("The text history is saved exclusively in the computer's operational memory (RAM), not on the disk."))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Completely temporary"))
                                .font(.system(size: 12, weight: .bold))
                            Text(t("All saved texts disappear immediately when you close the application. They are not recoverable, ensuring your data remains private."))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Stored in local file"))
                               .font(.system(size: 12, weight: .bold))
                            Text(t("The text history is saved securely in a local text file on your disk."))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("Persistent history"))
                                .font(.system(size: 12, weight: .bold))
                            Text(t("All saved texts persist between application restarts, so you never lose your history unless you manually clear it."))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                    }
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Local processing"))
                            .font(.system(size: 12, weight: .bold))
                        Text(t("We do not store, send, or analyze your processed texts anywhere outside of your device."))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
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
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 420)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}
