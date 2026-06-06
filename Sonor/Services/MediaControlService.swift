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
        unmuteWorkItem?.cancel()
        unmuteWorkItem = nil
        
        self.activeAudioBehavior = behavior
        if behavior == .mute {
            self.wasMutedBeforeRecording = getSystemMute()
            if !self.wasMutedBeforeRecording {
                setSystemMuteAppleScript(true)
            }
        }
    }
    
    /// Unmutes the system volume. If the volume was already muted before the app 
    /// started recording, it leaves it muted to respect the user's prior state.
    /// - Parameter delay: Delay before unmuting, allowing audio drivers to settle.
    func resumeMultimedia(delay: TimeInterval = 0.5) {
        self.activeAudioBehavior = nil
        
        if self.wasMutedBeforeRecording {
            return
        }
        
        unmuteWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Hybrid approach: wait an extra 0.5s (so 1.0s total) for the driver to recover
            Thread.sleep(forTimeInterval: 0.5)
            
            // Bombard the system with 'unmute' commands 5 times over 1 second (every 0.2s)
            for i in 1...5 {
                if self.unmuteWorkItem?.isCancelled == true {
                    return
                }
                
                self.setSystemMuteAppleScript(false)
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        unmuteWorkItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: item)
    }
    

    
    /// Uses CoreAudio to check the current hardware mute status of the default output device.
    /// We do this nonisolated because CoreAudio calls can be executed on background threads.
    nonisolated private func getSystemMute() -> Bool {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID
        )
        
        if status == noErr {
            var muteVal: UInt32 = 0
            var muteSize = UInt32(MemoryLayout.size(ofValue: muteVal))
            var muteAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(defaultOutputDeviceID, &muteAddress) {
                AudioObjectGetPropertyData(defaultOutputDeviceID, &muteAddress, 0, nil, &muteSize, &muteVal)
                return muteVal != 0
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
