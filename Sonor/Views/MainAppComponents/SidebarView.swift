import SwiftUI

struct SidebarView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedTab: SettingsTab
    @Binding var isProfileCardHovered: Bool
    @Binding var showLoginSheet: Bool
    @Binding var isShowingProfileSheet: Bool
    
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    
    var effectiveColorScheme: ColorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Sonor")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Text(t("Beta"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(effectiveColorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(effectiveColorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(4)
            }
            .padding(.leading, 10)
            .padding(.trailing, 24)
            .padding(.bottom, 2)
            
            VStack(spacing: 5) {
                MenuButton(title: t("Home"), icon: "house.fill", isSelected: selectedTab == .home) {
                    selectedTab = .home
                }
                MenuButton(title: t("Assistants"), icon: "square.grid.2x2.fill", isSelected: selectedTab == .modes) {
                    selectedTab = .modes
                }
                MenuButton(title: t("Dictionary"), icon: "book.closed.fill", isSelected: selectedTab == .dictionary) {
                    selectedTab = .dictionary
                }
                MenuButton(title: t("Snippets"), icon: "scissors", isSelected: selectedTab == .snippets) {
                    selectedTab = .snippets
                }
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            Button(action: {
                if let url = URL(string: "https://discord.gg/26vtCxw5H3") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                HStack {
                    Image("discord")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .padding(.leading, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Join Discord"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text(t("Community and Support"))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 88/255, green: 101/255, blue: 242/255))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            
            MenuButton(title: t("Models"), icon: "shippingbox.fill", isSelected: selectedTab == .models) {
                selectedTab = .models
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
            
            VStack(spacing: 15) {
                Divider()
                    .background(Color.white.opacity(0.1))
                
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundStyle(authManager.isLoggedIn ? .primary : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(authManager.isLoggedIn ? t(authManager.accountTier.capitalized) : t("User"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(authManager.currentUserEmail ?? t("Free account"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(authManager.isLoggedIn && isProfileCardHovered ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)) : Color.clear)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if authManager.isLoggedIn {
                        isShowingProfileSheet = true
                    }
                }
                .onHover { hovering in
                    if authManager.isLoggedIn {
                        isProfileCardHovered = hovering
                    }
                }
                .padding(.horizontal, -3)
                
                if authManager.isLoggedIn {
                    Button(action: {
                        authManager.logout()
                    }) {
                        Text(t("Log Out"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
                } else if networkMonitor.isConnected {
                    Button(action: {
                        showLoginSheet = true
                    }) {
                        Text(t("Log In"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(colorScheme == .dark ? Color.white : Color.black)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
                }
                
                MenuButton(title: t("Konsola Debugowania"), icon: "terminal.fill", isSelected: false) {
                    WindowManager.shared.openDebugConsole()
                }
                
                MenuButton(title: t("Settings"), icon: "gearshape.fill", isSelected: selectedTab == .settings) {
                    selectedTab = .settings
                }
            }
            .padding(.bottom, 20)
            .padding(.leading, 10)
            .padding(.trailing, 30)
        }
    }
}
