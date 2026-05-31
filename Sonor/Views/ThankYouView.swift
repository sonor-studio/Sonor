import SwiftUI
import Carbon

struct ThankYouView: View {
    let onComplete: () -> Void
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
            Spacer()
                .frame(height: 30)
            
            // Icon & Title
            VStack(spacing: 12) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(t("Congratulations, you unlocked full potential!"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 24)
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Description
                Text(t("Thank you for creating an account in Sonor. You now have access to powerful premium features. You can test them right away!"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
                
                let features = [
                    (icon: "brain.head.profile", title: t("Advanced LLM models"), description: t("Select any text and invoke Sonor to intelligently format it.")),
                    (icon: "text.badge.plus", title: t("Templates and Snippets"), description: t("Go to settings, add custom phrases, and recall them instantly with shortcuts.")),
                    (icon: "text.book.closed.fill", title: t("Personal Dictionary"), description: t("Sonor will now actively learn your specific vocabulary."))
                ]
                
                ForEach(features, id: \.title) { feature in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 18)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text(feature.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Centered Accept Button
            Button(action: {
                onComplete()
            }) {
                Text(t("Test it now"))
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
