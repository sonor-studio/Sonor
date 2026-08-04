import SwiftUI

struct ChangelogView: View {
    @Environment(\.colorScheme) var colorScheme
    
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 30)
            
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundColor(.primary)
                
                Text(String(format: t_changelog("What's new in version %@"), currentVersion))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 32)
            
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 32) {
                    let sections = ChangelogLocalization.shared.getSections()
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(section.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .padding(.bottom, 4)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16, alignment: .top),
                                GridItem(.flexible(), spacing: 16, alignment: .top)
                            ], spacing: 16) {
                                ForEach(section.features) { feature in
                                    ChangelogFeatureCard(feature: feature)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .background(colorScheme == .dark ? Color(NSColor.windowBackgroundColor) : Color(NSColor.controlBackgroundColor))
    }
}

struct ChangelogFeatureCard: View {
    let feature: ChangelogFeature
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: feature.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(8)
                
                Text(feature.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Text(feature.description)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(NSColor.controlBackgroundColor) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 5, x: 0, y: 2)
    }
}
