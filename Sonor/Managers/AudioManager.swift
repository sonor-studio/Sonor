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
    
    // Sonor needs 16kHz, 1 channel
    private let targetFormat: AVAudioFormat?
    
    init() {
        self.targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        if targetFormat == nil {
            print("❌ AudioManager: Nie udało się utworzyć formatu docelowego")
        }
    }
    
    func startRecording(clearSamples: Bool = true) throws {
        print("🎙️ AudioManager: Start nagrywania...")
        if clearSamples {
            accumulatedSamples.removeAll()
        }
        
        let engine = AVAudioEngine()
        self.audioEngine = engine
        
        let inputNode = engine.inputNode
        
        // Ustaw wybrane urządzenie wejściowe na podstawie UID
        if let savedDeviceUID = UserDefaults.standard.string(forKey: "selectedAudioDeviceUID"), !savedDeviceUID.isEmpty {
            let devices = getAudioInputDevices()
            if let targetDevice = devices.first(where: { $0.uid == savedDeviceUID }) {
                if let audioUnit = inputNode.audioUnit {
                    var deviceId = targetDevice.id
                    let status = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceId, UInt32(MemoryLayout<AudioDeviceID>.size))
                    if status != noErr {
                        print("❌ AudioManager: Nie udało się ustawić urządzenia audio (kod: \(status))")
                    } else {
                        print("✅ AudioManager: Ustawiono urządzenie audio: \(targetDevice.name)")
                    }
                }
            } else {
                print("⚠️ AudioManager: Nie znaleziono zapisanego urządzenia o UID: \(savedDeviceUID). Używam domyślnego.")
            }
        }
        
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        guard let targetFormat = targetFormat else {
            print("❌ AudioManager: Brak formatu docelowego")
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
            print("✅ AudioManager: Nagrywanie aktywne")
        }
    }
    
    @objc private func handleConfigurationChange(notification: Notification) {
        print("⚠️ AudioManager: Zmiana konfiguracji audio (urządzenie odłączone). Wznawiam nagrywanie...")
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
            print("❌ AudioManager: Błąd podczas wznawiania nagrywania: \(error)")
        }
    }
    
    func stopRecording() -> [Float] {
        print("⏹️ AudioManager: Zatrzymywanie...")
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
            let samples = accumulatedSamples
            // Clear for next recording
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
            // Calculate RMS for visualizer
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
            
            // Convert to 16kHz
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            
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
            if let error = error {
                print("❌ AudioManager: Błąd konwersji audio: \(error.localizedDescription)")
            }
            
            if let floatData = pcmBuffer.floatChannelData?[0] {
                let frameLength = Int(pcmBuffer.frameLength)
                let array = Array<Float>(UnsafeBufferPointer(start: floatData, count: frameLength))
                samplesQueue.async {
                    self.accumulatedSamples.append(contentsOf: array)
                }
            }
        }
    }
    
    /// Pobiera listę dostępnych urządzeń wejściowych audio (mikrofonów).
    func getAudioInputDevices() -> [AudioDevice] {
        // Używamy AVCaptureDevice do pobrania listy, aby uwzględnić np. mikrofony z iPhone'a (Continuity)
        let captureDevices = AVCaptureDevice.devices(for: .audio)
        var devices: [AudioDevice] = []
        
        // Pobieramy wszystkie urządzenia CoreAudio, aby dopasować ID dla AVAudioEngine
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
            
            // Szukamy odpowiednika w CoreAudio, aby mieć ID do ustawienia na AVAudioEngine
            for id in deviceIDs {
                var uidAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceUID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var uidSize = UInt32(MemoryLayout<CFString>.size)
                var coreUID: CFString = "" as CFString
                AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &coreUID)
                
                if (coreUID as String) == uid {
                    matchedID = id
                    break
                }
            }
            
            devices.append(AudioDevice(id: matchedID, uid: uid, name: name))
        }
        
        return devices
    }
}
