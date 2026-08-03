import Foundation
import CoreAudio
import AppKit
import MediaRemoteAdapter

// MARK: - HID Media Key Helper

/// Sends system-level media key events (Play/Pause) via CGEvent.
/// Used as an absolute fallback.
private enum HIDMediaKey {
    static func sendPlayPause() {
        let NX_KEYTYPE_PLAY: Int32 = 16
        
        let downFlags: UInt = 0xa00
        let downData1 = Int((NX_KEYTYPE_PLAY << 16) | (0xa << 8))
        if let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: downFlags),
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: downData1, data2: -1
        ) {
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        
        let upFlags: UInt = 0xb00
        let upData1 = Int((NX_KEYTYPE_PLAY << 16) | (0xb << 8))
        if let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: upFlags),
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: upData1, data2: -1
        ) {
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - MediaControlService

/// Manages the system's multimedia during voice recording.
/// Supports two behaviors:
/// - `.mute`: Mutes system audio via AppleScript (existing proven logic)
/// - `.pause`: Pauses media playback via MediaRemoteAdapter (Perl backend) + state tracking
@MainActor
class MediaControlService {
    static let shared = MediaControlService()
    
    /// The currently active audio behavior for the ongoing recording session.
    private var activeAudioBehavior: AudioBehavior? = nil
    
    // === MUTING STATE ===
    private var muteWorkItem: DispatchWorkItem?
    private var unmuteTask: Task<Void, Never>?
    private var muteGeneration: Int = 0
    private var didMuteAudio: Bool = false
    private var wasAudioMutedBeforeRecording: Bool = false
    
    // === PAUSING STATE ===
    private var wasPlayingBeforeRecording = false
    private var pausedMediaBundleId: String? = nil
    private var resumeWorkItem: DispatchWorkItem?
    
    // === MEDIA REMOTE ADAPTER ===
    private let mediaController = MediaRemoteAdapter.MediaController()
    private var isMediaCurrentlyPlaying = false
    private var currentPlayingBundleId: String? = nil
    
    private init() {
        // Start tracking media state continuously in the background
        // This is necessary because querying it on-demand might take too long (latency)
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            Task { @MainActor in
                self?.isMediaCurrentlyPlaying = trackInfo?.payload.isPlaying ?? false
                self?.currentPlayingBundleId = trackInfo?.payload.bundleIdentifier
            }
        }
        mediaController.startListening()
    }
    
    deinit {
        mediaController.stopListening()
    }
    
    // MARK: - Public API
    
    /// Pauses or mutes multimedia depending on the selected behavior.
    func pauseMultimedia(behavior: AudioBehavior) {
        print("[MediaControlService] pauseMultimedia: \(behavior.rawValue)")
        
        let isCurrentlyRestoring = (unmuteTask != nil) || (resumeWorkItem != nil)
        
        // Cancel any pending restoration from a previous session
        muteWorkItem?.cancel()
        muteWorkItem = nil
        unmuteTask?.cancel()
        unmuteTask = nil
        resumeWorkItem?.cancel()
        resumeWorkItem = nil
        
        switch behavior {
        case .mute:
            let isAlreadyManagingMute = (self.activeAudioBehavior == .mute) || isCurrentlyRestoring
            self.activeAudioBehavior = behavior
            performMute(isAlreadyManaging: isAlreadyManagingMute)
            
        case .pause:
            self.activeAudioBehavior = behavior
            performPause()
            
        case .muteAndPause:
            let isAlreadyManagingMute = (self.activeAudioBehavior == .muteAndPause) || isCurrentlyRestoring
            self.activeAudioBehavior = behavior
            performPause()
            performMute(isAlreadyManaging: isAlreadyManagingMute)
            
        case .keep:
            self.activeAudioBehavior = nil
        }
    }
    
    /// Resumes multimedia playback or unmutes system audio after recording ends.
    func resumeMultimedia(delay: TimeInterval = 0.5) {
        let prevBehavior = activeAudioBehavior
        print("[MediaControlService] resumeMultimedia, prev: \(prevBehavior?.rawValue ?? "nil")")
        activeAudioBehavior = nil
        
        // Zatrzymujemy jakiekolwiek zaplanowane akcje wyciszania/pauzowania,
        // jeśli użytkownik bardzo szybko zakończył nagrywanie.
        muteWorkItem?.cancel()
        muteWorkItem = nil
        
        switch prevBehavior {
        case .mute:
            performUnmute(delay: delay)
        case .pause:
            performResume(delay: delay)
        case .muteAndPause:
            performResume(delay: delay)
            performUnmute(delay: delay)
        case .keep, .none:
            break
        }
    }
    
    /// Updates the multimedia state dynamically while a recording is already active.
    func updateMultimedia(from oldBehavior: AudioBehavior, to newBehavior: AudioBehavior) {
        guard oldBehavior != newBehavior else { return }
        print("[MediaControlService] updateMultimedia: from \(oldBehavior.rawValue) to \(newBehavior.rawValue)")
        
        let oldMute = (oldBehavior == .mute || oldBehavior == .muteAndPause)
        let newMute = (newBehavior == .mute || newBehavior == .muteAndPause)
        let oldPause = (oldBehavior == .pause || oldBehavior == .muteAndPause)
        let newPause = (newBehavior == .pause || newBehavior == .muteAndPause)
        
        self.activeAudioBehavior = newBehavior
        
        // Unmute if previously muted but new mode doesn't mute
        if oldMute && !newMute {
            performUnmute(delay: 0)
        }
        // Resume if previously paused but new mode doesn't pause
        if oldPause && !newPause {
            performResume(delay: 0)
        }
        
        // Mute if new mode mutes and we weren't already muting
        if newMute && !oldMute {
            performMute(isAlreadyManaging: false)
        }
        // Pause if new mode pauses and we weren't already pausing
        if newPause && !oldPause {
            performPause()
        }
    }
    
    private func performMute(isAlreadyManaging: Bool) {
        muteWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                
                // Wolne calle do CoreAudio wykonujemy w tle
                let currentlyMuted = self.isSystemAudioMuted()
                
                await MainActor.run {
                    self.unmuteTask?.cancel()
                    self.unmuteTask = nil
                    self.muteGeneration += 1
                    
                    if currentlyMuted {
                        if self.didMuteAudio {
                            self.wasAudioMutedBeforeRecording = false
                        } else {
                            self.wasAudioMutedBeforeRecording = true
                            self.didMuteAudio = false
                        }
                    } else {
                        self.wasAudioMutedBeforeRecording = false
                    }
                }
                
                if !currentlyMuted {
                    let success = self.setSystemMuted(true)
                    await MainActor.run {
                        self.didMuteAudio = success
                    }
                }
            }
        }
        muteWorkItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5, execute: item)
    }
    
    private func performUnmute(delay: TimeInterval) {
        let shouldUnmute = didMuteAudio && !wasAudioMutedBeforeRecording
        let myGeneration = muteGeneration
        
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            guard !Task.isCancelled else { return }
            
            let isSameGeneration = await MainActor.run { [weak self] in self?.muteGeneration == myGeneration }
            guard isSameGeneration == true else { return }
            
            if shouldUnmute {
                _ = self?.setSystemMuted(false)
            }
            
            await MainActor.run { [weak self] in
                self?.didMuteAudio = false
            }
        }
        
        unmuteTask = task
    }
    
    // MARK: - Pausing Logic (MediaRemoteAdapter)
    
    private func performPause() {
        print("[MediaControlService] performPause: checking if media is playing...")
        
        // 1. Sprawdzamy czy COKOLWIEK gra, używając danych śledzonych na bieżąco.
        // Jeśli adapter jeszcze nie złapał stanu, ratujemy się AppleScriptem.
        var isPlaying = isMediaCurrentlyPlaying
        if !isPlaying {
            isPlaying = checkIfMediaIsPlayingAppleScript()
        }
        
        guard isPlaying else {
            print("[MediaControlService] Nothing is currently playing, skipping pause.")
            wasPlayingBeforeRecording = false
            pausedMediaBundleId = nil
            return
        }
        
        print("[MediaControlService] Media IS playing (App: \(currentPlayingBundleId ?? "unknown")). Pausing now...")
        
        // 2. Skoro gra, oznaczamy że to MY będziemy odpowiedzialni za wznowienie.
        wasPlayingBeforeRecording = true
        pausedMediaBundleId = currentPlayingBundleId
        
        // 3. Wykonujemy faktyczną pauzę (używając stabilnego adaptera)
        mediaController.pause()
    }
    
    private func performResume(delay: TimeInterval) {
        // 1. Jeśli to nie my zapauzowaliśmy (nic nie grało w momencie startu), nic nie robimy!
        guard wasPlayingBeforeRecording else {
            print("[MediaControlService] performResume: nothing was paused by us, skipping resume.")
            return
        }
        
        print("[MediaControlService] performResume: scheduling resume with delay \(delay)s")
        
        // Snapshot
        let bundleIdToVerify = pausedMediaBundleId
        let controller = mediaController
        
        // Reset state
        wasPlayingBeforeRecording = false
        pausedMediaBundleId = nil
        
        resumeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            // Upewnijmy się, że aplikacja z której pauzowaliśmy muzykę nadal istnieje
            if let bid = bundleIdToVerify {
                let stillRunning = NSWorkspace.shared.runningApplications.contains {
                    $0.bundleIdentifier == bid
                }
                if !stillRunning {
                    print("[MediaControlService] App \(bid) no longer running, skip resume")
                    return
                }
            }
            
            // Jeśli nagrywa z trybem, który nadal wymaga pauzy, anuluj wznawianie
            let active = self?.activeAudioBehavior
            if active == .pause || active == .muteAndPause {
                print("[MediaControlService] New recording started with pause, skip resume")
                return
            }
            
            print("[MediaControlService] Resuming media via adapter...")
            controller.play()
            
            // Opcjonalny fallback, gdyby adapter nagle zawiódł
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if self?.isMediaCurrentlyPlaying == false {
                    print("[MediaControlService] Media still not playing, using HID fallback...")
                    HIDMediaKey.sendPlayPause()
                }
            }
        }
        resumeWorkItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: item)
    }
    
    // MARK: - CoreAudio Helpers
    
    nonisolated private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceID)
        return status == noErr ? deviceID : nil
    }

    nonisolated private func isSystemAudioMuted() -> Bool {
        guard let deviceID = getDefaultOutputDevice() else { return false }
        var muted: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return false }
        }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &muted)
        return status == noErr && muted != 0
    }

    nonisolated private func setSystemMuted(_ muted: Bool) -> Bool {
        guard let deviceID = getDefaultOutputDevice() else { return false }
        var muteValue: UInt32 = muted ? 1 : 0
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &address) {
            address.mElement = 0
            if !AudioObjectHasProperty(deviceID, &address) { return false }
        }
        var isSettable: DarwinBoolean = false
        var status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        if status != noErr || !isSettable.boolValue { return false }
        
        status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, propertySize, &muteValue)
        return status == noErr
    }
    
    nonisolated private func checkIfMediaIsPlayingAppleScript() -> Bool {
        let script = """
        tell application "System Events"
            set processList to name of every process whose background only is false
        end tell
        if "Music" is in processList then
            try
                run script "tell application \\"Music\\" to return (player state is playing)"
                if result is true then return true
            end try
        end if
        if "Spotify" is in processList then
            try
                run script "tell application \\"Spotify\\" to return (player state is playing)"
                if result is true then return true
            end try
        end if
        return false
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            return appleScript.executeAndReturnError(&error).booleanValue
        }
        return false
    }
}
