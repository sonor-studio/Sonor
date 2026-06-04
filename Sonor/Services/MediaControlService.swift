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
        if behavior == .pause {
            let NX_KEYTYPE_PLAY: Int32 = 16
            postMediaKeyEvent(key: NX_KEYTYPE_PLAY)
        } else if behavior == .mute {
            runAppleScript("set volume with output muted")
        }
    }
    
    func resumeMultimedia() {
        if !self.didPauseMusic { return }
        self.didPauseMusic = false
        let behavior = self.activeAudioBehavior ?? .mute
        self.activeAudioBehavior = nil
        if behavior == .pause {
            let NX_KEYTYPE_PLAY: Int32 = 16
            postMediaKeyEvent(key: NX_KEYTYPE_PLAY)
        } else if behavior == .mute {
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
    
    private func postMediaKeyEvent(key: Int32) {
        func doKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: (down ? 0xa00 : 0xb00))
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
            let ev = NSEvent.otherEvent(with: .systemDefined,
                                        location: NSPoint(x: 0, y: 0),
                                        modifierFlags: flags,
                                        timestamp: 0,
                                        windowNumber: 0,
                                        context: nil,
                                        subtype: 8,
                                        data1: data1,
                                        data2: -1)
            let cgEvent = ev?.cgEvent
            cgEvent?.post(tap: .cghidEventTap)
        }
        doKey(down: true)
        doKey(down: false)
    }
    
    nonisolated func isAudioActivelyPlayingPmset() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("PreventUserIdleDisplaySleep") || line.contains("PreventUserIdleSystemSleep") {
                    if line.contains("coreaudiod") || line.contains("powerd") || line.contains("WindowServer") || line.contains("Sonor") {
                        continue
                    }
                    if line.contains("Audio Playback") || line.contains("WebKit Media Playback") || line.contains("Spotify") {
                        return true
                    }
                }
            }
        }
        return false
    }
}
