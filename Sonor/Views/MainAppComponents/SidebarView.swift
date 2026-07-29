import SwiftUI

struct SidebarView: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedTab: SettingsTab
    @ObservedObject var localizer = LocalizationManager.shared
    
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
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.vertical, 5)
                
                MenuButton(title: t("Models"), icon: "shippingbox.fill", isSelected: selectedTab == .models) {
                    selectedTab = .models
                }
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            MenuButton(title: t("Changelog"), icon: "gift.fill", isSelected: selectedTab == .changelog) {
                selectedTab = .changelog
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
            
            MenuButton(title: t("Feedback"), icon: "envelope.fill", isSelected: selectedTab == .feedback) {
                selectedTab = .feedback
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
            
            VStack(spacing: 15) {
                Divider()
                    .background(Color.white.opacity(0.1))
                

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
