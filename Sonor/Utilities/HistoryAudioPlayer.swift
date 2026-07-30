import Foundation
import AVFoundation
import Combine

class HistoryAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = HistoryAudioPlayer()
    
    @Published var playingID: UUID?
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var isPaused: Bool = false
    
    private var player: AVAudioPlayer?
    private var timer: Timer?
    
    private override init() {
        super.init()
    }
    
    func play(id: UUID, data: Data) {
        if playingID == id {
            if isPaused {
                player?.play()
                isPaused = false
                startTimer()
            } else if currentTime >= duration {
                seek(to: 0.0)
                player?.play()
                isPaused = false
                startTimer()
            }
            return
        }
        
        stop()
        playingID = id
        isPaused = false
        
        do {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_playback.wav")
            try data.write(to: tempURL)
            
            player = try AVAudioPlayer(contentsOf: tempURL)
            player?.delegate = self
            
            let defaults = UserDefaults.standard
            let appVolume = defaults.object(forKey: "appVolume") == nil ? 1.0 : defaults.double(forKey: "appVolume")
            player?.volume = Float(appVolume)
            
            player?.prepareToPlay()
            self.duration = player?.duration ?? 0.0
            self.currentTime = 0.0
            
            player?.play()
            startTimer()
        } catch {
            print("Failed to setup AVAudioPlayer: \(error)")
            stop()
        }
    }
    
    func seek(to time: Double) {
        guard let p = player else { return }
        let wasPlaying = p.isPlaying
        
        let target = max(0, min(time, duration - 0.1))
        p.currentTime = target
        currentTime = target
        
        if wasPlaying {
            p.play()
        }
    }
    
    func pause() {
        player?.pause()
        isPaused = true
        stopTimer()
    }
    
    func stop() {
        player?.stop()
        player = nil
        playingID = nil
        isPaused = false
        currentTime = 0.0
        stopTimer()
    }
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.player, p.isPlaying else { return }
            self.currentTime = p.currentTime
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stop()
        }
    }
}


