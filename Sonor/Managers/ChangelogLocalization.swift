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
            ChangelogSection(title: t_changelog("Major Highlights"), features: [
                ChangelogFeature(icon: "cpu", title: t_changelog("The New Model Manager"), description: t_changelog("Explore a wide range of MLX transcription models in our entirely redesigned hub. Compare models easily using new accuracy and speed progress bars, rich metadata, and a robust new downloading interface.")),
                ChangelogFeature(icon: "waveform.path", title: t_changelog("Interactive Voice History"), description: t_changelog("The history tab has been completely revamped. You can now expand entries to see the target application, transcription model, and mode. Play back past recordings, and even retry transcriptions directly from your history using a different model."))
            ]),
            ChangelogSection(title: t_changelog("Core Improvements"), features: [
                ChangelogFeature(icon: "bolt.fill", title: t_changelog("Zero-Latency Audio Engine"), description: t_changelog("We rebuilt the audio engine from the ground up! The microphone now triggers instantly with zero delay, fixing the issue of clipped words at the start of recordings (especially with headphones). We also optimized the overlay animations for a much snappier feel.")),
                ChangelogFeature(icon: "pause.circle", title: t_changelog("Flawless Media Controls"), description: t_changelog("The media muting system has been heavily improved, and we introduced a highly requested feature to perfectly pause and resume your background music while recording.")),
                ChangelogFeature(icon: "person.2.badge.gearshape", title: t_changelog("Assistant-Specific Configurations"), description: t_changelog("Take full control of your workflows. You can now assign specific transcription models and post-transcription automated hotkeys individually for each assistant.")),
                ChangelogFeature(icon: "hand.tap", title: t_changelog("Smart Automatic Hotkeys"), description: t_changelog("Forget manually choosing between 'click-to-talk' and 'push-to-talk'. The new automatic hotkey mode detects your behavior—a short click toggles the assistant on and off, while holding the key down automatically stops recording when released."))
            ]),
            ChangelogSection(title: t_changelog("Quality of Life & Settings"), features: [
                ChangelogFeature(icon: "gearshape.2", title: t_changelog("Extended App Configuration"), description: t_changelog("Enjoy a massive set of new settings: freeform overlay positioning, memory management with automatic model unloading, output audio device selection, and a global hotkey to paste your last transcription.")),
                ChangelogFeature(icon: "exclamationmark.triangle.fill", title: t_changelog("Graceful Out-Of-Memory Handling"), description: t_changelog("No more crashes when you run out of RAM! The application now gracefully intercepts memory limits and provides a friendly interface in the overlay to let you retry the transcription.")),
                ChangelogFeature(icon: "ladybug.fill", title: t_changelog("In-App Feedback & UI Organization"), description: t_changelog("Submit ideas, questions, and bug reports directly via the new 'Feedback' tab in the sidebar. We also moved this Changelog out of annoying popups and directly into a dedicated application tab."))
            ])
        ]
    }
}

public func t_changelog(_ key: String) -> String {
    return t(key)
}
