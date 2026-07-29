import Foundation
import AVFoundation
import Combine

class HistoryAudioPlayer: NSObject, ObservableObject {
    static let shared = HistoryAudioPlayer()
    
    @Published var playingID: UUID?
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    
    private var currentTask: Task<Void, Never>?
    private var stopFlag = false
    private var seekTarget: Double? = nil
    
    private override init() {
        super.init()
    }
    
    func play(id: UUID, data: Data) {
        if playingID == id {
            stop()
            return
        }
        
        stop()
        playingID = id
        stopFlag = false
        
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_playback.wav")
        do {
            try data.write(to: tempURL)
            let file = try AVAudioFile(forReading: tempURL)
            let fileDuration = Double(file.length) / file.processingFormat.sampleRate
            self.duration = fileDuration
            self.currentTime = 0.0
            
            let defaults = UserDefaults.standard
            let appVolume = defaults.object(forKey: "appVolume") == nil ? 1.0 : defaults.double(forKey: "appVolume")
            let outputDeviceUID = defaults.string(forKey: "selectedAudioOutputDeviceUID") ?? ""
            
            currentTask = Task.detached(priority: .userInitiated) { [weak self] in
                let engine = AVAudioEngine()
                let playerNode = AVAudioPlayerNode()
                
                engine.attach(playerNode)
                
                if !outputDeviceUID.isEmpty && outputDeviceUID != "Default" {
                    if let dev = AudioManager().getAudioOutputDevices().first(where: { $0.uid == outputDeviceUID }) {
                        if let audioUnit = engine.outputNode.audioUnit {
                            var devId = dev.id
                            AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &devId, UInt32(MemoryLayout<AudioDeviceID>.size))
                        }
                    }
                }
                
                engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
                playerNode.volume = Float(appVolume)
                
                do {
                    try engine.start()
                    
                    var currentStartFrame: AVAudioFramePosition = 0
                    
                    while self?.stopFlag == false {
                        let semaphore = DispatchSemaphore(value: 0)
                        
                        let frameCount = AVAudioFrameCount(file.length - currentStartFrame)
                        if frameCount <= 0 { break }
                        
                        playerNode.scheduleSegment(file, startingFrame: currentStartFrame, frameCount: frameCount, at: nil) {
                            semaphore.signal()
                        }
                        
                        playerNode.play()
                        let sampleRate = file.processingFormat.sampleRate
                        
                        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
                            if self?.stopFlag == true {
                                playerNode.stop()
                                break
                            }
                            
                            if let seekTime = self?.seekTarget {
                                playerNode.stop()
                                currentStartFrame = AVAudioFramePosition(seekTime * sampleRate)
                                self?.seekTarget = nil
                                break // breaks inner wait loop, outer loop will reschedule
                            }
                            
                            if let nodeTime = playerNode.lastRenderTime, let playerTime = playerNode.playerTime(forNodeTime: nodeTime) {
                                let timePlayed = Double(playerTime.sampleTime) / sampleRate
                                let actualTime = (Double(currentStartFrame) / sampleRate) + timePlayed
                                DispatchQueue.main.async {
                                    if self?.playingID == id {
                                        self?.currentTime = min(actualTime, fileDuration)
                                    }
                                }
                            }
                        }
                        
                        if self?.stopFlag == true { break }
                        
                        // If we didn't seek, it means we naturally finished this segment
                        if self?.seekTarget == nil {
                            // Wait for the buffer to flush
                            usleep(50_000)
                            break
                        }
                    }
                    
                    playerNode.stop()
                    engine.stop()
                    
                    DispatchQueue.main.async {
                        if self?.playingID == id {
                            self?.playingID = nil
                            self?.currentTime = 0.0
                        }
                    }
                } catch {
                    print("Failed to play: \(error)")
                    DispatchQueue.main.async {
                        if self?.playingID == id {
                            self?.playingID = nil
                        }
                    }
                }
            }
            
        } catch {
            print("Failed to setup audio file: \(error)")
            stop()
        }
    }
    
    func seek(to time: Double) {
        seekTarget = max(0, min(time, duration))
        currentTime = seekTarget!
    }
    
    func stop() {
        stopFlag = true
        currentTask?.cancel()
        currentTask = nil
        playingID = nil
    }
}


