import SwiftUI

struct ChangelogView: View {
    let onComplete: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 30)
            
            VStack(spacing: 12) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text(String(format: t_changelog("What's new in version %@"), currentVersion))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 24)
            
            VStack(alignment: .leading, spacing: 16) {
                let features = ChangelogLocalization.shared.getFeatures()
                ForEach(features) { feature in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 24, alignment: .center)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.primary)
                            Text(feature.description)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            Button(action: {
                onComplete()
            }) {
                Text(t_changelog("Understood"))
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
