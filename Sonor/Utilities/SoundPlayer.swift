import Foundation
import AVFoundation
import AppKit

@MainActor
class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = SoundPlayer()
    
    private var activePlayers: [AVAudioPlayer] = []
    private var continuations: [AVAudioPlayer: CheckedContinuation<Void, Never>] = [:]
    
    private override init() {}
    
    func playSound(named name: String) async {
        let defaults = UserDefaults.standard
        
        // Domyślne wartości to true, jeśli nie są ustawione
        let playAnySound = defaults.object(forKey: "playAnySound") == nil ? true : defaults.bool(forKey: "playAnySound")
        let playSpecificSound = defaults.object(forKey: "playSound_\(name)") == nil ? true : defaults.bool(forKey: "playSound_\(name)")
        
        guard playAnySound && playSpecificSound else { return }
        
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            // Fallback do absolutnej ścieżki dla testów (gdy pliki nie są w Copy Bundle Resources)
            let localURL = URL(fileURLWithPath: "/Users/macbook/Desktop/Dev/Sonor/Sonor/\(name).wav")
            if FileManager.default.fileExists(atPath: localURL.path) {
                await play(url: localURL)
            } else {
                print("❌ SoundPlayer: Nie znaleziono dźwięku \(name).wav")
            }
            return
        }
        await play(url: url)
    }
    
    private func play(url: URL) async {
        return await withCheckedContinuation { continuation in
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                activePlayers.append(player)
                continuations[player] = continuation
                player.play()
            } catch {
                print("❌ SoundPlayer error: \(error)")
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
