import Foundation
import CoreAudio
import AppKit

/// Manages the system's multimedia volume, allowing the app to mute audio during 
/// voice recording to prevent echo or feedback loops.
@MainActor
class MediaControlService {
    static let shared = MediaControlService()
    
    private var activeAudioBehavior: AudioBehavior? = nil
    private var unmuteWorkItem: DispatchWorkItem?
    private var wasMutedBeforeRecording: Bool = false
    
    private init() {}
    
    /// Mutes the system volume if the selected behavior demands it.
    /// - Parameter behavior: Defines whether audio should be kept or muted during recording.
    func pauseMultimedia(behavior: AudioBehavior) {
        let isCurrentlyUnmuting = (unmuteWorkItem != nil)
        
        unmuteWorkItem?.cancel()
        unmuteWorkItem = nil
        
        let isAlreadyManagingMute = (self.activeAudioBehavior == .mute) || isCurrentlyUnmuting
        self.activeAudioBehavior = behavior
        
        if behavior == .mute {
            if !isAlreadyManagingMute {
                self.wasMutedBeforeRecording = getSystemMute()
            }
            if !self.wasMutedBeforeRecording {
                setSystemMuteAppleScript(true)
            }
        }
    }
    
    /// Unmutes the system volume. If the volume was already muted before the app 
    /// started recording, it leaves it muted to respect the user's prior state.
    /// - Parameter delay: Delay before unmuting, allowing audio drivers to settle.
    func resumeMultimedia(delay: TimeInterval = 0.5) {
        let wasMuting = (self.activeAudioBehavior == .mute)
        self.activeAudioBehavior = nil
        
        // If we didn't actively mute the system for this session, we have nothing to restore.
        if !wasMuting {
            return
        }
        
        if self.wasMutedBeforeRecording {
            return
        }
        
        unmuteWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            Thread.sleep(forTimeInterval: 0.5)
            
            for _ in 1...5 {
                if self.activeAudioBehavior != nil {
                    return
                }
                
                self.setSystemMuteAppleScript(false)
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        unmuteWorkItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: item)
    }
    

    
    /// Uses AppleScript to check the system's global mute status.
    /// This is more reliable than CoreAudio for Bluetooth devices, external DACs, and modern Macs.
    nonisolated private func getSystemMute() -> Bool {
        let scriptStr = "output muted of (get volume settings) or output volume of (get volume settings) = 0"
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptStr) {
            let result = script.executeAndReturnError(&error)
            if error == nil {
                return result.booleanValue
            }
        }
        return false
    }
    
    /// Executes a small AppleScript to securely and globally mute/unmute the system volume.
    /// This is often more reliable than attempting to modify CoreAudio properties directly.
    nonisolated private func setSystemMuteAppleScript(_ mute: Bool) {
        let scriptStr = mute ? "set volume with output muted" : "set volume without output muted"
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptStr) {
            script.executeAndReturnError(&error)
        }
    }
}
