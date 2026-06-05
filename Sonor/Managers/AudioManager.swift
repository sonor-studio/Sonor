import Foundation
import AVFoundation
import Combine
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

class AudioManager: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    private var accumulatedSamples: [Float] = []
    private let samplesQueue = DispatchQueue(label: "com.sonor.samplesQueue")
    private var isTapInstalled = false
    var isPaused = false
    private let targetFormat: AVAudioFormat?
    init() {
        self.targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        if targetFormat == nil {
        }
    }
    

    
    func startRecording(clearSamples: Bool = true) throws {
        if clearSamples {
            accumulatedSamples.removeAll()
        }
        let engine = AVAudioEngine()
        self.audioEngine = engine
        let inputNode = engine.inputNode
        if let savedDeviceUID = UserDefaults.standard.string(forKey: "selectedAudioDeviceUID"), !savedDeviceUID.isEmpty {
            let devices = getAudioInputDevices()
            if let targetDevice = devices.first(where: { $0.uid == savedDeviceUID }),
               targetDevice.id != kAudioObjectUnknown {
                if let audioUnit = inputNode.audioUnit {
                    var deviceId = targetDevice.id
                    AudioUnitSetProperty(
                        audioUnit,
                        kAudioOutputUnitProperty_CurrentDevice,
                        kAudioUnitScope_Global,
                        0,
                        &deviceId,
                        UInt32(MemoryLayout<AudioDeviceID>.size)
                    )
                }
            }
        }
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard let targetFormat = targetFormat else {
            return
        }
        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            self?.processAudio(buffer: buffer)
        }
        isTapInstalled = true
        engine.prepare()
        try engine.start()
        NotificationCenter.default.addObserver(self, selector: #selector(handleConfigurationChange), name: .AVAudioEngineConfigurationChange, object: engine)
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }
    @objc private func handleConfigurationChange(notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: audioEngine)
        if isTapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
        do {
            try startRecording(clearSamples: false)
        } catch {
        }
    }
    func stopRecording() -> [Float] {
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: audioEngine)
        if isTapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine?.stop()
        audioEngine = nil
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
        }
        return samplesQueue.sync {
            var samples = accumulatedSamples
            let chunkSize = 800 
            let silenceThreshold: Float = 0.01
            var i = samples.count
            while i >= chunkSize {
                let start = i - chunkSize
                let end = i
                var sumSq: Float = 0.0
                for j in start..<end {
                    let val = samples[j]
                    sumSq += val * val
                }
                let rms = sqrt(sumSq / Float(chunkSize))
                if rms < silenceThreshold {
                    for j in start..<end {
                        samples[j] = 0.0
                    }
                    i -= chunkSize
                } else {
                    break
                }
            }

            
            accumulatedSamples = []
            return samples
        }
    }
    private func processAudio(buffer: AVAudioPCMBuffer) {
        if isPaused {
            DispatchQueue.main.async {
                self.audioLevel = 0.0
            }
            return
        }
        autoreleasepool {
            if let channelData = buffer.floatChannelData?[0] {
                let length = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<length {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(length))
                DispatchQueue.main.async {
                    self.audioLevel = rms
                }
            }
            guard let converter = audioConverter, let targetFormat = targetFormat else { return }
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            pcmBuffer.frameLength = pcmBuffer.frameCapacity // FIX for AVAudioConverter returning 0 frames
            
            var error: NSError? = nil
            var hasData = false
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                if !hasData {
                    outStatus.pointee = .haveData
                    hasData = true
                    return buffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }
            converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
            if let floatData = pcmBuffer.floatChannelData?[0] {
                let frameLength = Int(pcmBuffer.frameLength)
                let array = Array<Float>(UnsafeBufferPointer(start: floatData, count: frameLength))
                samplesQueue.async {
                    self.accumulatedSamples.append(contentsOf: array)
                }
            }
        }
    }
    func getAudioInputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        if status != noErr { return devices }
        
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        
        for id in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize) != noErr || streamSize == 0 {
                continue 
            }
            
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var coreName: Unmanaged<CFString>? = nil
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &coreName)
            let name = (coreName?.takeRetainedValue() as String?) ?? "Unknown Device"
            
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            var coreUID: Unmanaged<CFString>? = nil
            AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &coreUID)
            let uid = (coreUID?.takeRetainedValue() as String?) ?? UUID().uuidString
            
            devices.append(AudioDevice(id: id, uid: uid, name: name))
        }
        return devices
    }
}
