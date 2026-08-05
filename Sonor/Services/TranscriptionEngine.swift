import Foundation

public protocol TranscriptionEngine {
    var name: String { get }
    var isReady: Bool { get }
    
    func prepare() async throws
    
    func transcribe(audioSamples: [Float], language: String, initialPrompt: String?) async throws -> String
    
    func unload()
}
