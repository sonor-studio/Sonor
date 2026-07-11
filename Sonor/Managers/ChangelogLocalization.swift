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
            ChangelogFeature(icon: "text.bubble", title: t_changelog("Intelligent Streaming"), description: t_changelog("Generation shifts to the background if the field loses focus, and smartly appends only missing text when resumed.")),
            ChangelogFeature(icon: "wand.and.stars", title: t_changelog("Revamped Assistants"), description: t_changelog("A completely overhauled prompt architecture with new 'Casual Style' and 'Formal Style' assistants.")),
            ChangelogFeature(icon: "arrow.down.circle", title: t_changelog("Resilient Downloads"), description: t_changelog("Model downloads now automatically retry during minor network connection drops.")),
            ChangelogFeature(icon: "hand.raised", title: t_changelog("Permissions & UI Polish"), description: t_changelog("Strict new permissions onboarding window, draggable overlays, and smoother animations."))
        ]
    }
}

public func t_changelog(_ key: String) -> String {
    return t(key)
}
