import ScreenCaptureKit
import AVFoundation

@available(macOS 12.3, *)
class AudioCaptureManager: NSObject, SCStreamOutput {
    static let shared = AudioCaptureManager()
    private var stream: SCStream?
    private var isPlaying = false
    private let queue = DispatchQueue(label: "com.sonor.AudioCaptureQueue")
    
    private override init() {
        super.init()
    }
    
    func checkIsAudioPlaying(timeout: TimeInterval = 0.5) async -> Bool {
        guard CGPreflightScreenCaptureAccess() else {
            return false
        }
        self.isPlaying = false
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            self.stream = stream
            try await stream.startCapture()
            
            let start = Date()
            while Date().timeIntervalSince(start) < timeout {
                if self.isPlaying {
                    break
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            
            let result = self.isPlaying
            try? await stream.stopCapture()
            self.stream = nil
            return result
        } catch {
            self.stream = nil
            return false
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        if isBufferActive(sampleBuffer) {
            self.isPlaying = true
        }
    }
    
    private func isBufferActive(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return false }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return false }
        var bytes = [Int16](repeating: 0, count: length / MemoryLayout<Int16>.stride)
        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &bytes)
        for sample in bytes {
            if abs(sample) > 50 {
                return true
            }
        }
        return false
    }
}
