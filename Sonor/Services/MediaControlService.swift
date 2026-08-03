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
    private var unmuteWorkItem: DispatchWorkItem?
    private var wasMutedBeforeRecording: Bool = false
    
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
        
        let isCurrentlyRestoring = (unmuteWorkItem != nil) || (resumeWorkItem != nil)
        
        // Cancel any pending restoration from a previous session
        muteWorkItem?.cancel()
        muteWorkItem = nil
        unmuteWorkItem?.cancel()
        unmuteWorkItem = nil
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
        case .keep, .none:
            break
        }
    }
    
    private func performMute(isAlreadyManaging: Bool) {
        Task.detached(priority: .userInitiated) {
            var wasMuted = false
            if !isAlreadyManaging {
                wasMuted = self.getSystemMute()
                await MainActor.run { self.wasMutedBeforeRecording = wasMuted }
            } else {
                wasMuted = await MainActor.run { return self.wasMutedBeforeRecording }
            }
            
            if !wasMuted {
                self.setSystemMuteAppleScript(true)
            }
        }
    }
    
    private func performUnmute(delay: TimeInterval) {
        // Natychmiastowe sprawdzenie flagi na MainActor
        if self.wasMutedBeforeRecording {
            print("[MediaControlService] performUnmute: user muted before us, skipping unmute.")
            return
        }
        
        print("[MediaControlService] performUnmute: scheduling unmute with delay \(delay)s")
        
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
    
    // MARK: - Pausing Logic (MediaRemoteAdapter)
    
    private func performPause() {
        print("[MediaControlService] performPause: checking if media is playing...")
        
        // 1. Sprawdzamy czy COKOLWIEK gra, używając danych śledzonych na bieżąco.
        // Dzięki temu unikamy pauzowania z opóźnieniem.
        guard isMediaCurrentlyPlaying else {
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
            
            // Jeśli zaczął nagrywać ponownie, anuluj wznawianie
            if self?.activeAudioBehavior != nil {
                print("[MediaControlService] New recording started, skip resume")
                return
            }
            
            print("[MediaControlService] Resuming media via adapter...")
            controller.play()
            
            // Opcjonalny fallback, gdyby adapter nagle zawiódł
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self?.isMediaCurrentlyPlaying == false {
                    print("[MediaControlService] Media still not playing, using HID fallback...")
                    HIDMediaKey.sendPlayPause()
                }
            }
        }
        resumeWorkItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: item)
    }
    
    // MARK: - AppleScript Helpers
    
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
