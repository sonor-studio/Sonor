import Foundation
import CoreAudio
import AppKit

@MainActor
class MediaControlService {
    static let shared = MediaControlService()
    
    private var activeAudioBehavior: AudioBehavior? = nil
    private var unmuteWorkItem: DispatchWorkItem?
    private var wasMutedBeforeRecording: Bool = false
    
    private init() {}
    
    func pauseMultimedia(behavior: AudioBehavior) {
        print("MediaControlService: pauseMultimedia called")
        unmuteWorkItem?.cancel()
        unmuteWorkItem = nil
        
        self.activeAudioBehavior = behavior
        if behavior == .mute {
            self.wasMutedBeforeRecording = getSystemMute()
            print("MediaControlService: wasMutedBeforeRecording = \(self.wasMutedBeforeRecording)")
            if !self.wasMutedBeforeRecording {
                setSystemMuteAppleScript(true)
            }
        }
    }
    
    func resumeMultimedia(delay: TimeInterval = 0.5) {
        print("MediaControlService: resumeMultimedia called")
        self.activeAudioBehavior = nil
        
        if self.wasMutedBeforeRecording {
            print("MediaControlService: System was muted before recording, skipping unmute.")
            return
        }
        
        unmuteWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            print("MediaControlService: Starting hybrid AppleScript unmute loop")
            
            // Hybrid approach: wait an extra 0.5s (so 1.0s total) for the driver to recover
            Thread.sleep(forTimeInterval: 0.5)
            
            // Bombard the system with 'unmute' commands 5 times over 1 second (every 0.2s)
            for i in 1...5 {
                if self.unmuteWorkItem?.isCancelled == true {
                    print("MediaControlService: Bombardment cancelled (User started recording again)")
                    return
                }
                
                print("MediaControlService: Bombardment attempt \(i)...")
                self.setSystemMuteAppleScript(false)
                Thread.sleep(forTimeInterval: 0.2)
            }
            print("MediaControlService: Bombardment finished")
        }
        unmuteWorkItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: item)
    }
    
    func resetDidPauseMusic() {
        print("MediaControlService: resetDidPauseMusic called")
    }
    
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
    
    nonisolated private func setSystemMuteAppleScript(_ mute: Bool) {
        let scriptStr = mute ? "set volume with output muted" : "set volume without output muted"
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptStr) {
            script.executeAndReturnError(&error)
        }
    }
}
