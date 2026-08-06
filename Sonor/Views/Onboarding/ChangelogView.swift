import SwiftUI

struct ChangelogView: View {
    @Environment(\.colorScheme) var colorScheme
    
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)
            
            VStack(spacing: 12) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.primary)
                
                Text(String(format: t_changelog("What's new in version %@"), currentVersion))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 40)
            
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 40) {
                    let sections = ChangelogLocalization.shared.getSections()
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(section.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                                .textCase(.uppercase)
                                .padding(.bottom, 8)
                            
                            VStack(spacing: 24) {
                                ForEach(section.features) { feature in
                                    ChangelogFeatureCard(feature: feature)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .background(colorScheme == .dark ? Color(NSColor.windowBackgroundColor) : Color(NSColor.controlBackgroundColor))
    }
}

struct ChangelogFeatureCard: View {
    let feature: ChangelogFeature
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 24, alignment: .center)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(feature.description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
