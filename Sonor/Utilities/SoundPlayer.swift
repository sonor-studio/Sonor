import Foundation
import AVFoundation

class SoundPlayer: NSObject {
    static let shared = SoundPlayer()
    
    private var cachedBuffers: [String: AVAudioPCMBuffer] = [:]
    
    private override init() {
        super.init()
        preloadSounds()
    }
    
    private func preloadSounds() {
        let soundsToPreload = ["Start", "End", "Error"]
        for name in soundsToPreload {
            let url: URL?
            if let bUrl = Bundle.main.url(forResource: name, withExtension: "wav") {
                url = bUrl
            } else {
                let localURL = URL(fileURLWithPath: "/Users/macbook/Desktop/Dev/Sonor/Sonor/\(name).wav")
                if FileManager.default.fileExists(atPath: localURL.path) {
                    url = localURL
                } else { url = nil }
            }
            
            if let url = url, let file = try? AVAudioFile(forReading: url),
               let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) {
                try? file.read(into: buffer)
                cachedBuffers[name] = buffer
            }
        }
    }
    private let playbackQueue = DispatchQueue(label: "com.sonor.soundPlayback")
    
    func playSound(named name: String) async {
        let defaults = UserDefaults.standard
        let playAnySound = defaults.object(forKey: "playAnySound") == nil ? true : defaults.bool(forKey: "playAnySound")
        let playSpecificSound = defaults.object(forKey: "playSound_\(name)") == nil ? true : defaults.bool(forKey: "playSound_\(name)")
        
        guard playAnySound && playSpecificSound else { return }
        guard let buffer = cachedBuffers[name] else { return }
        
        let appVolume = defaults.object(forKey: "appVolume") == nil ? 1.0 : defaults.double(forKey: "appVolume")
        let outputDeviceUID = defaults.string(forKey: "selectedAudioOutputDeviceUID") ?? ""
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playbackQueue.async {
                let engine = AVAudioEngine()
                let playerNode = AVAudioPlayerNode()
                
                engine.attach(playerNode)
                
                // Konfiguracja sprzętu
                if !outputDeviceUID.isEmpty && outputDeviceUID != "Default" {
                    if let dev = AudioManager.shared.getAudioOutputDevices().first(where: { $0.uid == outputDeviceUID }) {
                        if let audioUnit = engine.outputNode.audioUnit {
                            var devId = dev.id
                            AudioUnitSetProperty(
                                audioUnit,
                                kAudioOutputUnitProperty_CurrentDevice,
                                kAudioUnitScope_Global,
                                0,
                                &devId,
                                UInt32(MemoryLayout<AudioDeviceID>.size)
                            )
                        }
                    }
                }
                
                engine.connect(playerNode, to: engine.mainMixerNode, format: buffer.format)
                
                playerNode.volume = Float(appVolume)
                
                do {
                    try engine.start()
                    
                    let semaphore = DispatchSemaphore(value: 0)
                    
                    playerNode.scheduleBuffer(buffer, at: nil, options: []) {
                        semaphore.signal()
                    }
                    
                    playerNode.play()
                    
                    semaphore.wait()
                    usleep(50_000)
                    
                    playerNode.stop()
                    engine.stop()
                } catch {
                    print("Error playing sound '\(name)': \(error)")
                }
                
                continuation.resume()
            }
        }
    }
}
