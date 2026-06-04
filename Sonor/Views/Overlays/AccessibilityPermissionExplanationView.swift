import SwiftUI

struct AccessibilityPermissionExplanationView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var localizer = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 30)
            VStack(spacing: 12) {
                Image(systemName: "figure.roll")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(t("Accessibility Access Required"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 16) {
                Text(t("Sonor needs Accessibility access to automatically paste your transcribed text. Without it, the application cannot function properly."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
                
                let steps = [
                    (icon: "gearshape.fill", title: t("1. Open System Settings"), description: ""),
                    (icon: "lock.shield.fill", title: t("2. Go to Privacy & Security"), description: ""),
                    (icon: "figure.walk.circle.fill", title: t("3. Select Accessibility"), description: ""),
                    (icon: "switch.2", title: t("4. Turn on the switch next to Sonor"), description: "")
                ]
                
                ForEach(steps, id: \.title) { step in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: step.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                            if !step.description.isEmpty {
                                Text(step.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    dismiss()
                }) {
                    Text(t("Cancel"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 100)
                        .padding(.vertical, 12)
                        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .focusable(false)

                Button(action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                    dismiss()
                }) {
                    Text(t("Open Settings"))
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
            }
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 480)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}
