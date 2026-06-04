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
    
    // DEBUG: Save WAV file to Desktop to verify audio integrity
    func saveWav(samples: [Float], sampleRate: Double = 16000) {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
        let url = desktop.appendingPathComponent("sonor_debug_audio.wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<samples.count {
            buffer.floatChannelData?[0][i] = samples[i]
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            DebugLogger.shared.addLog("Saved debug audio to \(url.path)")
        } catch {
            DebugLogger.shared.addLog("Failed to save debug audio: \(error)")
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
        DebugLogger.shared.addLog("AudioManager.startRecording: inputFormat = \(inputFormat)")
        guard let targetFormat = targetFormat else {
            DebugLogger.shared.addLog("AudioManager.startRecording: targetFormat is nil!")
            return
        }
        audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            self?.processAudio(buffer: buffer)
        }
        isTapInstalled = true
        DebugLogger.shared.addLog("AudioManager.startRecording: tap installed, calling engine.prepare()...")
        engine.prepare()
        DebugLogger.shared.addLog("AudioManager.startRecording: calling engine.start()...")
        try engine.start()
        DebugLogger.shared.addLog("AudioManager.startRecording: engine.start() succeeded!")
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
            let samplesCount = samples.count
            var finalSumSq: Float = 0.0
            for val in samples {
                finalSumSq += val * val
            }
            let finalRms = samplesCount > 0 ? sqrt(finalSumSq / Float(samplesCount)) : 0.0
            DebugLogger.shared.addLog("Finished recording. Samples: \(samplesCount), RMS of 16kHz audio: \(finalRms)")
            
            self.saveWav(samples: samples)
            
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
        let captureDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        var devices: [AudioDevice] = []
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        var deviceIDs: [AudioDeviceID] = []
        if status == noErr {
            let count = Int(size) / MemoryLayout<AudioDeviceID>.size
            deviceIDs = [AudioDeviceID](repeating: 0, count: count)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        }
        for captureDevice in captureDevices {
            let uid = captureDevice.uniqueID
            let name = captureDevice.localizedName
            var matchedID: AudioDeviceID = 0
            for id in deviceIDs {
                var uidAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceUID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var uidSize = UInt32(MemoryLayout<CFString>.size)
                var coreUID: Unmanaged<CFString>? = nil
                AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &coreUID)
                if let uidStr = coreUID?.takeRetainedValue() as String?, uidStr == uid {
                    matchedID = id
                    break
                }
            }
            devices.append(AudioDevice(id: matchedID, uid: uid, name: name))
        }
        return devices.filter { $0.id != kAudioObjectUnknown }
    }
}
