import SwiftUI

struct IncognitoAnimationOverlay: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var showBanner = false
    @State private var isActiveMode = true
    @ObservedObject private var localizer = LocalizationManager.shared
    var body: some View {
        VStack {
            if showBanner {
                HStack(spacing: 8) {
                    Image(systemName: isActiveMode ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .font(.system(size: 14))
                    Text(isActiveMode ? t("Incognito Mode Active") : t("Incognito Mode Inactive"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .shadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 12)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlayIncognitoAnimation"))) { notification in
            if let num = notification.object as? NSNumber {
                isActiveMode = num.boolValue
            } else {
                isActiveMode = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showBanner = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeIn(duration: 0.3)) {
                    showBanner = false
                }
            }
        }
    }
}
