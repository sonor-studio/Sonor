import Foundation
import AVFoundation
import AppKit

@MainActor
class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = SoundPlayer()
    private var activePlayers: [AVAudioPlayer] = []
    private var continuations: [AVAudioPlayer: CheckedContinuation<Void, Never>] = [:]
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
            guard let url = cachedUrls[name], let player = try? AVAudioPlayer(contentsOf: url) else {
                continuation.resume()
                return
            }
            
            player.delegate = self
            activePlayers.append(player)
            continuations[player] = continuation
            
            if !player.play() {
                activePlayers.removeAll { $0 == player }
                continuations.removeValue(forKey: player)
                continuation.resume()
            }
        }
    }
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if let continuation = continuations[player] {
                continuation.resume()
                continuations.removeValue(forKey: player)
            }
            activePlayers.removeAll { $0 == player }
        }
    }
}
