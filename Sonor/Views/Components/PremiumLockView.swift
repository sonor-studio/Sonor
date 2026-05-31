import SwiftUI

struct PremiumLockView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var showLoginSheet: Bool
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text(t("Your voice deserves more"))
                .font(.system(size: 24, weight: .bold))
            
            Text(t("Unlock advanced AI assistants, intelligent dictionaries, and custom snippets to turn every recording into polished, ready-to-use text. Everything is 100% free and runs fully offline on your computer — your data is secure, and the app collects no information."))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            if NetworkMonitor.shared.isConnected {
                Button(action: {
                    showLoginSheet = true
                }) {
                    Text(t("Log In"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.top, 10)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
