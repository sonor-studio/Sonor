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

/// Manages the capture of system audio or microphone input, converting it into
/// 16kHz Float32 PCM samples suitable for Whisper model processing.
class AudioManager: ObservableObject {
    static let shared = AudioManager()
    
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter? // Converts raw audio to our target format (16kHz)
    /// Serial queue that serializes ALL engine operations to prevent race conditions.
    private let engineQueue = DispatchQueue(label: "com.sonor.engine", qos: .userInitiated)
    
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0 // RMS audio level for UI visualizations
    private var accumulatedSamples: [Float] = []
    private let samplesQueue = DispatchQueue(label: "com.sonor.samplesQueue")
    private var isTapInstalled = false
    var isPaused = false
    private let targetFormat: AVAudioFormat?
    
    private init() {
        self.targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        if targetFormat == nil {
        }
        registerDeviceChangeListener()
    }
    
    deinit {
        unregisterDeviceChangeListener()
    }
    
    // MARK: - Pre-warming
    
    /// Pre-warms the audio engine by creating it (if needed), configuring the input device,
    /// and calling prepare(). Runs asynchronously on the engine queue.
    func prepareEngine() {
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.audioEngine != nil {
                // Engine already exists — just make sure it's prepared
                self.audioEngine?.prepare()
                return
            }
            
            // Create new engine
            let engine = AVAudioEngine()
            self.configureDevice(on: engine.inputNode)
            engine.prepare()
            try? engine.start()
            engine.stop()
            self.audioEngine = engine
        }
    }
    
    // MARK: - Device Change Listener
    
    private static let deviceChangeProc: AudioObjectPropertyListenerProc = { _, _, _, clientData in
        guard let clientData = clientData else { return noErr }
        let manager = Unmanaged<AudioManager>.fromOpaque(clientData).takeUnretainedValue()
        if !manager.isRecording {
            // Device changed while not recording — rebuild engine with new device
            manager.engineQueue.async {
                if let engine = manager.audioEngine {
                    if manager.isTapInstalled {
                        engine.inputNode.removeTap(onBus: 0)
                        manager.isTapInstalled = false
                    }
                    engine.stop()
                }
                manager.audioEngine = nil
                
                let newEngine = AVAudioEngine()
                manager.configureDevice(on: newEngine.inputNode)
                newEngine.prepare()
                manager.audioEngine = newEngine
            }
        }
        return noErr
    }
    
    private func registerDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            AudioManager.deviceChangeProc,
            selfPtr
        )
    }
    
    private func unregisterDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            AudioManager.deviceChangeProc,
            selfPtr
        )
    }

    // MARK: - Device Configuration
    
    private func configureDevice(on inputNode: AVAudioInputNode) {
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
    }

    // MARK: - Recording
    
    /// Initializes the audio engine and begins capturing samples.
    /// If the engine was pre-warmed via prepareEngine(), start is nearly instantaneous.
    /// - Parameter clearSamples: If true, previously recorded samples are discarded before starting.
    func startRecording(clearSamples: Bool = true) throws {
        if clearSamples {
            accumulatedSamples.removeAll()
        }
        
        // All engine work serialized on engineQueue to prevent races
        try engineQueue.sync { [self] in
            // Create engine if none exists (first time or after pause destroyed it)
            if audioEngine == nil {
                let engine = AVAudioEngine()
                configureDevice(on: engine.inputNode)
                audioEngine = engine
            }
            
            guard let engine = audioEngine else { return }
            
            if self.isTapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                self.isTapInstalled = false
            }
            
            let inputNode = engine.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            guard let targetFormat = targetFormat else {
                return
            }
            audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
                self?.processAudio(buffer: buffer)
            }
            self.isTapInstalled = true
            engine.prepare()
            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    print("Engine start failed, recovering with new engine: \(error)")
                    // Hardware state likely corrupted by rapid toggling.
                    // Destroy corrupted engine and create a fresh one.
                    if self.isTapInstalled {
                        engine.inputNode.removeTap(onBus: 0)
                        self.isTapInstalled = false
                    }
                    self.audioEngine = nil
                    
                    let newEngine = AVAudioEngine()
                    configureDevice(on: newEngine.inputNode)
                    self.audioEngine = newEngine
                    
                    let newInputNode = newEngine.inputNode
                    let newInputFormat = newInputNode.inputFormat(forBus: 0)
                    self.audioConverter = AVAudioConverter(from: newInputFormat, to: targetFormat)
                    newInputNode.installTap(onBus: 0, bufferSize: 1024, format: newInputFormat) { [weak self] (buffer, time) in
                        self?.processAudio(buffer: buffer)
                    }
                    self.isTapInstalled = true
                    newEngine.prepare()
                    try newEngine.start()
                }
            }
            NotificationCenter.default.addObserver(self, selector: #selector(handleConfigurationChange), name: .AVAudioEngineConfigurationChange, object: self.audioEngine)
        }
        
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }
    
    @objc private func handleConfigurationChange(notification: Notification) {
        engineQueue.async { [weak self] in
            guard let self = self, let engine = self.audioEngine else { return }
            
            let wasTapInstalled = self.isTapInstalled
            if wasTapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                self.isTapInstalled = false
            }
            
            engine.stop()
            
            if wasTapInstalled {
                let inputFormat = engine.inputNode.inputFormat(forBus: 0)
                if let target = self.targetFormat {
                    self.audioConverter = AVAudioConverter(from: inputFormat, to: target)
                    engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
                        self?.processAudio(buffer: buffer)
                    }
                    self.isTapInstalled = true
                    
                    engine.prepare()
                    do {
                        try engine.start()
                    } catch {
                        print("Failed to restart engine after config change: \(error)")
                    }
                }
            } else {
                // If we weren't recording, just re-prepare the engine for the new device
                engine.prepare()
            }
        }
    }

    
    func stopRecordingAsync() async -> [Float] {
        await withCheckedContinuation { continuation in
            engineQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                
                NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: self.audioEngine)
                
                if self.isTapInstalled {
                    self.audioEngine?.inputNode.removeTap(onBus: 0)
                    self.isTapInstalled = false
                }
                self.audioEngine?.stop()
                
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.audioLevel = 0.0
                }
                
                let samples = self.samplesQueue.sync {
                    let s = self.accumulatedSamples
                    self.accumulatedSamples = []
                    return s
                }
                
                continuation.resume(returning: samples)
            }
        }
    }
    /// Physically stops the audio engine to release the microphone lock and remove the yellow privacy dot.
    func pauseRecording() {
        guard !isPaused else { return }
        isPaused = true
        
        engineQueue.sync { [self] in
            NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: audioEngine)
            if isTapInstalled {
                audioEngine?.inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
            audioEngine?.stop()
            audioEngine = nil // Destroy to release mic (removes yellow privacy dot)
        }
        
        DispatchQueue.main.async {
            self.audioLevel = 0.0
        }
    }
    
    /// Recreates the audio engine and resumes recording, keeping the previously accumulated samples.
    func resumeRecording() throws {
        guard isPaused else { return }
        isPaused = false
        try startRecording(clearSamples: false)
    }

    /// Receives raw buffers from the audio engine, calculates UI volume levels,
    /// and performs format conversion into `accumulatedSamples`.
    private func processAudio(buffer: AVAudioPCMBuffer) {
        if isPaused { return }
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
            pcmBuffer.frameLength = pcmBuffer.frameCapacity // Prevents AVAudioConverter from returning 0 frames
            
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

    func getAudioOutputDevices() -> [AudioDevice] {
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
                mScope: kAudioDevicePropertyScopeOutput,
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

    func getDefaultAudioOutputDeviceUID() -> String? {
        var defaultOutputDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultOutputDeviceID) == noErr {
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var coreUID: Unmanaged<CFString>? = nil
            if AudioObjectGetPropertyData(defaultOutputDeviceID, &uidAddress, 0, nil, &uidSize, &coreUID) == noErr {
                return coreUID?.takeRetainedValue() as String?
            }
        }
        return nil
    }
}
