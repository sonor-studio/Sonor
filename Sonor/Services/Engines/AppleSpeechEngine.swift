import Foundation
import Speech
import AVFoundation

public class AppleSpeechEngine: TranscriptionEngine {
    public let name: String = "Apple Speech (System)"
    
    private var recognizer: SFSpeechRecognizer?
    
    public var isReady: Bool {
        return recognizer != nil
    }
    
    public init() {}
    
    public func prepare() async throws {
        // Request authorization if needed
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in
                    continuation.resume()
                }
            }
        }
        
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw NSError(domain: "AppleSpeechEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized."])
        }
        
        // Initialize recognizer with the default locale or let it automatically detect
        self.recognizer = SFSpeechRecognizer()
        if self.recognizer?.isAvailable == false {
            throw NSError(domain: "AppleSpeechEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available."])
        }
    }
    
    public func transcribe(audioSamples: [Float], language: String, initialPrompt: String?) async throws -> String {
        guard let recognizer = recognizer else {
            throw NSError(domain: "AppleSpeechEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Engine not prepared."])
        }
        
        // Sonor provides 16kHz mono PCM Float arrays
        let sampleRate: Double = 16000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw NSError(domain: "AppleSpeechEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format."])
        }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audioSamples.count)) else {
            throw NSError(domain: "AppleSpeechEngine", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer."])
        }
        
        buffer.frameLength = buffer.frameCapacity
        if let channelData = buffer.floatChannelData?[0] {
            audioSamples.withUnsafeBufferPointer { sourcePtr in
                channelData.update(from: sourcePtr.baseAddress!, count: audioSamples.count)
            }
        }
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.append(buffer)
        request.endAudio()
        
        if language != "auto" {
            // Note: In a full implementation, you would map language codes to Locale properly
            // and instantiate a new SFSpeechRecognizer(locale:) if needed.
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let result = result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
    
    public func unload() {
        self.recognizer = nil
    }
}
