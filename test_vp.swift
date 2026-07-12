import Foundation
import AVFoundation

let engine = AVAudioEngine()
if #available(macOS 10.15, *) {
    do {
        print("VP is enabled: \(engine.inputNode.isVoiceProcessingEnabled)")
        try engine.inputNode.setVoiceProcessingEnabled(false)
        print("VP after: \(engine.inputNode.isVoiceProcessingEnabled)")
    } catch {
        print("Error: \(error)")
    }
}
