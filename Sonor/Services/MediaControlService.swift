import Foundation
import AppKit

@MainActor
class MediaControlService {
    static let shared = MediaControlService()
    
    private var activeAudioBehavior: AudioBehavior? = nil
    private(set) var didPauseMusic: Bool = false
    
    private init() {}
    
    func pauseMultimedia(behavior: AudioBehavior) {
        self.activeAudioBehavior = behavior
        self.didPauseMusic = true
        if behavior == .mute {
            runAppleScript("set volume with output muted")
        }
    }
    
    func resumeMultimedia() {
        if !self.didPauseMusic { return }
        self.didPauseMusic = false
        let behavior = self.activeAudioBehavior ?? .mute
        self.activeAudioBehavior = nil
        if behavior == .mute {
            runAppleScript("set volume without output muted")
        }
    }
    
    func resetDidPauseMusic() {
        self.didPauseMusic = false
    }
    
    private func runAppleScript(_ source: String) {
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error = error {
                DebugLogger.shared.addLog("MediaControlService AppleScript error: \(error)")
                print("AppleScript error: \(error)")
            } else {
                DebugLogger.shared.addLog("MediaControlService AppleScript executed successfully: \(source)")
            }
        } else {
            DebugLogger.shared.addLog("MediaControlService AppleScript initialization failed for source: \(source)")
        }
    }
}
