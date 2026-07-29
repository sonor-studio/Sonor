import Foundation
import AVFoundation
import SwiftUI
import Combine

struct MemoryMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let date: Date
    var hasAudio: Bool? = false // Optional for backwards compatibility with existing JSON
}

@MainActor
class MessageMemoryManager: ObservableObject {
    static let shared = MessageMemoryManager()
    @Published var messages: [MemoryMessage] = []
    @Published var historyStorageType: String = UserDefaults.standard.string(forKey: "historyStorageType") ?? "RAM" {
        didSet {
            UserDefaults.standard.set(historyStorageType, forKey: "historyStorageType")
        }
    }
    
    // RAM storage for audio samples (WAV Data)
    private var ramAudioSamples: [UUID: Data] = [:]
    
    var sonorURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupportURL.appendingPathComponent("Sonor", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }
    
    var historyFileURL: URL {
        return sonorURL.appendingPathComponent("history.json")
    }
    
    var audioDirectoryURL: URL {
        let url = sonorURL.appendingPathComponent("AudioHistory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }
    
    func historyAudioURL(for id: UUID) -> URL {
        return audioDirectoryURL.appendingPathComponent("\(id.uuidString).wav")
    }
    
    private init() {
        loadHistory()
    }
    func loadHistory() {
        guard historyStorageType == "File" else {
            self.messages = []
            return
        }
        let url = historyFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            self.messages = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([MemoryMessage].self, from: data)
            self.messages = decoded
        } catch {
            self.messages = []
        }
    }
    private func saveToDisk() {
        guard historyStorageType == "File" else { return }
        let url = historyFileURL
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: url, options: [.atomic])
        } catch {
        }
    }
    
    private func deleteDiskFile() {
        let url = historyFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        // Also delete audio directory
        let audioDir = audioDirectoryURL
        if FileManager.default.fileExists(atPath: audioDir.path) {
            try? FileManager.default.removeItem(at: audioDir)
        }
    }
    func switchToFileMode() {
        historyStorageType = "File"
        saveToDisk()
        
        // Move RAM audio to File
        for (id, data) in ramAudioSamples {
            let url = historyAudioURL(for: id)
            try? data.write(to: url)
        }
        ramAudioSamples.removeAll()
    }
    
    func switchToRAMMode() {
        historyStorageType = "RAM"
        // Move File audio to RAM before deleting
        for msg in messages {
            if msg.hasAudio == true {
                let url = historyAudioURL(for: msg.id)
                if let data = try? Data(contentsOf: url) {
                    ramAudioSamples[msg.id] = data
                }
            }
        }
        deleteDiskFile()
    }
    
    func saveMessage(_ text: String, samples: [Float]? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        if UserDefaults.standard.bool(forKey: "isIncognitoMode") {
            return
        }
        
        let id = UUID()
        let hasAudio = samples != nil && !samples!.isEmpty
        let msg = MemoryMessage(id: id, text: trimmed, date: Date(), hasAudio: hasAudio)
        messages.append(msg)
        
        if hasAudio, let samples = samples, let wavData = convertToWAVData(samples: samples) {
            if historyStorageType == "RAM" {
                ramAudioSamples[id] = wavData
            } else if historyStorageType == "File" {
                let url = historyAudioURL(for: id)
                try? wavData.write(to: url)
            }
        }
        
        if historyStorageType == "File" {
            saveToDisk()
        }
        var totalBytes = 0
        for m in messages {
            totalBytes += m.text.utf8.count
        }
        let kb = Double(totalBytes) / 1024.0
        let mb = kb / 1024.0
        if mb > 1.0 {
        } else if kb > 1.0 {
        } else {
        }
    }
    func clearHistory() {
        messages.removeAll()
        ramAudioSamples.removeAll()
        if historyStorageType == "File" {
            deleteDiskFile()
        }
    }
    
    func deleteMessage(id: UUID) {
        messages.removeAll { $0.id == id }
        ramAudioSamples.removeValue(forKey: id)
        if historyStorageType == "File" {
            let url = historyAudioURL(for: id)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            saveToDisk()
        }
    }
    
    func getAudioData(for id: UUID) -> Data? {
        if historyStorageType == "RAM" {
            return ramAudioSamples[id]
        } else {
            let url = historyAudioURL(for: id)
            return try? Data(contentsOf: url)
        }
    }
    
    private func convertToWAVData(samples: [Float]) -> Data? {
        guard !samples.isEmpty else { return nil }
        
        // Trim leading silence
        let chunkSize = 800
        
        var maxRms: Float = 0.0001
        var chunkIndex = 0
        while chunkIndex <= samples.count - chunkSize {
            var sumSq: Float = 0.0
            for i in chunkIndex..<chunkIndex+chunkSize {
                sumSq += samples[i] * samples[i]
            }
            let rms = sqrt(sumSq / Float(chunkSize))
            if rms > maxRms { maxRms = rms }
            chunkIndex += chunkSize
        }
        
        let silenceThreshold = maxRms * 0.1 // 10% of peak volume
        
        var startIndex = 0
        while startIndex <= samples.count - chunkSize {
            var sumSq: Float = 0.0
            for i in startIndex..<startIndex+chunkSize {
                sumSq += samples[i] * samples[i]
            }
            if sqrt(sumSq / Float(chunkSize)) >= silenceThreshold {
                break
            }
            startIndex += chunkSize
        }
        
        // Trim trailing silence
        var endIndex = samples.count
        while endIndex >= chunkSize {
            var sumSq: Float = 0.0
            for i in endIndex-chunkSize..<endIndex {
                sumSq += samples[i] * samples[i]
            }
            if sqrt(sumSq / Float(chunkSize)) >= silenceThreshold {
                break
            }
            endIndex -= chunkSize
        }
        
        // Add 0.2s padding (3200 samples) to avoid cutting too abruptly
        startIndex = max(0, startIndex - 3200)
        endIndex = min(samples.count, endIndex + 3200)
        
        guard startIndex < endIndex else { return nil }
        
        let trimmedSamples = Array(samples[startIndex..<endIndex])
        
        var maxAmplitude: Float = 0.001
        for i in 0..<trimmedSamples.count {
            let absVal = abs(trimmedSamples[i])
            if absVal > maxAmplitude {
                maxAmplitude = absVal
            }
        }
        let scale = 0.9 / maxAmplitude
        
        var pcmData = Data(capacity: trimmedSamples.count * 2)
        for sample in trimmedSamples {
            let val = max(-1.0, min(1.0, sample * scale))
            var int16Val = Int16(val * 32767.0).littleEndian
            withUnsafePointer(to: &int16Val) { ptr in
                pcmData.append(UnsafeBufferPointer(start: ptr, count: 1))
            }
        }
        
        return createWAV(from: pcmData, sampleRate: 16000, channels: 1)
    }
    
    private func createWAV(from pcmData: Data, sampleRate: Int32, channels: Int16) -> Data {
        var header = Data()
        let byteRate = sampleRate * Int32(channels) * 2 // 16-bit
        let blockAlign = channels * 2
        
        // RIFF
        header.append(contentsOf: "RIFF".utf8)
        var chunkSize = Int32(36 + pcmData.count).littleEndian
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append(contentsOf: "WAVE".utf8)
        
        // fmt
        header.append(contentsOf: "fmt ".utf8)
        var fmtSize = Int32(16).littleEndian
        header.append(Data(bytes: &fmtSize, count: 4))
        var audioFormat = Int16(1).littleEndian // PCM
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = channels.littleEndian
        header.append(Data(bytes: &numChannels, count: 2))
        var rate = sampleRate.littleEndian
        header.append(Data(bytes: &rate, count: 4))
        var bRate = byteRate.littleEndian
        header.append(Data(bytes: &bRate, count: 4))
        var bAlign = blockAlign.littleEndian
        header.append(Data(bytes: &bAlign, count: 2))
        var bitsPerSample = Int16(16).littleEndian
        header.append(Data(bytes: &bitsPerSample, count: 2))
        
        // data
        header.append(contentsOf: "data".utf8)
        var dataSize = Int32(pcmData.count).littleEndian
        header.append(Data(bytes: &dataSize, count: 4))
        
        var fullData = header
        fullData.append(pcmData)
        return fullData
    }
}

