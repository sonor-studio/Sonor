import Foundation
import AVFoundation
import AppKit

@MainActor
class SoundPlayer: NSObject, NSSoundDelegate {
    static let shared = SoundPlayer()
    private var activeSounds: [NSSound] = []
    private var continuations: [NSSound: CheckedContinuation<Void, Never>] = [:]
    private var cachedUrls: [String: URL] = [:]
    
    private override init() {
        super.init()
        preloadSounds()
    }
    
    private func preloadSounds() {
        let soundsToPreload = ["Start", "End", "Error"]
        for name in soundsToPreload {
            if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
                cachedUrls[name] = url
            } else {
                let localURL = URL(fileURLWithPath: "/Users/macbook/Desktop/Dev/Sonor/Sonor/\(name).wav")
                if FileManager.default.fileExists(atPath: localURL.path) {
                    cachedUrls[name] = localURL
                }
            }
        }
    }
    
    func playSound(named name: String) async {
        let defaults = UserDefaults.standard
        let playAnySound = defaults.object(forKey: "playAnySound") == nil ? true : defaults.bool(forKey: "playAnySound")
        let playSpecificSound = defaults.object(forKey: "playSound_\(name)") == nil ? true : defaults.bool(forKey: "playSound_\(name)")
        
        guard playAnySound && playSpecificSound else { return }
        
        return await withCheckedContinuation { continuation in
            guard let url = cachedUrls[name], let sound = NSSound(contentsOf: url, byReference: true) else {
                continuation.resume()
                return
            }
            
            sound.delegate = self
            activeSounds.append(sound)
            continuations[sound] = continuation
            
            if !sound.play() {
                activeSounds.removeAll { $0 == sound }
                continuations.removeValue(forKey: sound)
                continuation.resume()
            }
        }
    }
    
    nonisolated func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        Task { @MainActor in
            if let continuation = continuations[sound] {
                continuation.resume()
                continuations.removeValue(forKey: sound)
            }
            activeSounds.removeAll { $0 == sound }
        }
    }
}
