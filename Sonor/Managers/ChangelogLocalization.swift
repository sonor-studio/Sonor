import Foundation
import SwiftUI

public struct ChangelogFeature: Identifiable {
    public let id = UUID()
    public let icon: String
    public let title: String
    public let description: String
}

public struct ChangelogSection: Identifiable {
    public let id = UUID()
    public let title: String
    public let features: [ChangelogFeature]
}

public class ChangelogLocalization {
    public static let shared = ChangelogLocalization()
    
    private init() {}
    
    public func getSections() -> [ChangelogSection] {
        return [
            ChangelogSection(title: t_changelog("New Features"), features: [
                ChangelogFeature(icon: "macwindow.badge.plus", title: t_changelog("Redesigned Sidebar & Navigation"), description: t_changelog("The sidebar has been reorganized for better clarity with updated icons, clearer separators, and a more intuitive layout.")),
                ChangelogFeature(icon: "ladybug.fill", title: t_changelog("In-App Feedback System"), description: t_changelog("You can now submit ideas, bug reports, and questions directly from the app. Includes custom categories and optional email contact.")),
                ChangelogFeature(icon: "waveform.path", title: t_changelog("Voice Request History"), description: t_changelog("Added the ability to browse and replay your past voice requests directly from the new statistics dashboard.")),
                ChangelogFeature(icon: "mic.badge.plus", title: t_changelog("Audio Device Selection"), description: t_changelog("A new General Settings tab allows you to explicitly select your preferred input (microphone) and output (speaker) devices."))
            ]),
            ChangelogSection(title: t_changelog("Improvements & Fixes"), features: [
                ChangelogFeature(icon: "speaker.wave.2.fill", title: t_changelog("Audio Playback Reliability"), description: t_changelog("Completely refactored the internal audio engine to resolve memory leaks and fix playback clipping issues.")),
                ChangelogFeature(icon: "menubar.rectangle", title: t_changelog("Menu Bar Stability"), description: t_changelog("Fixed visual flickering and layout issues in the Menu Bar extra, providing a much smoother experience.")),
                ChangelogFeature(icon: "globe", title: t_changelog("Expanded Localizations"), description: t_changelog("Added missing translations for all new features, ensuring 100% coverage across all 9 supported languages."))
            ]),
            ChangelogSection(title: t_changelog("Under the Hood"), features: [
                ChangelogFeature(icon: "wifi.slash", title: t_changelog("100% Offline & Private"), description: t_changelog("Complete removal of user accounts and cloud syncing. Sonor now works entirely on your device."))
            ])
        ]
    }
}

public func t_changelog(_ key: String) -> String {
    return t(key)
}
