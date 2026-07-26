import Foundation
import SwiftUI

public struct ChangelogFeature: Identifiable {
    public let id = UUID()
    public let icon: String
    public let title: String
    public let description: String
}

public class ChangelogLocalization {
    public static let shared = ChangelogLocalization()
    
    private init() {}
    
    public func getFeatures() -> [ChangelogFeature] {
        return [
            ChangelogFeature(icon: "wifi.slash", title: t_changelog("100% Offline & Private"), description: t_changelog("Complete removal of user accounts and cloud syncing. Sonor now works entirely on your device.")),
            ChangelogFeature(icon: "bolt.fill", title: t_changelog("Lighter & Faster"), description: t_changelog("Streamlined the interface and removed unnecessary integrations to make the app significantly faster.")),
            ChangelogFeature(icon: "sparkles", title: t_changelog("Simplified Experience"), description: t_changelog("Removed unused screens and onboarding steps for quicker access to core features."))
        ]
    }
}

public func t_changelog(_ key: String) -> String {
    return t(key)
}
