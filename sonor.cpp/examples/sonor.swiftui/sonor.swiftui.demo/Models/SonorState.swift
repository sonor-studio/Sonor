import Foundation
import SwiftUI
import AVFoundation

@MainActor
class SonorState: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isModelLoaded = false
    @Published var messageLog = ""
    @Published var canTranscribe = false
    @Published var isRecording = false
    private var sonorContext: SonorContext?
    private let recorder = Recorder()
    private var recordedFile: URL? = nil
    private var audioPlayer: AVAudioPlayer?
    private var builtInModelUrl: URL? {
        Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "models")
    }
    private var sampleUrl: URL? {
        Bundle.main.url(forResource: "jfk", withExtension: "wav", subdirectory: "samples")
    }
    private enum LoadError: Error {
        case couldNotLocateModel
    }
    override init() {
        super.init()
        loadModel()
    }
    func loadModel(path: URL? = nil, log: Bool = true) {
        do {
            sonorContext = nil
            if (log) { messageLog += "Loading model...\n" }
            let modelUrl = path ?? builtInModelUrl
            if let modelUrl {
                sonorContext = try SonorContext.createContext(path: modelUrl.path())
                if (log) { messageLog += "Loaded model \(modelUrl.lastPathComponent)\n" }
            } else {
                if (log) { messageLog += "Could not locate model\n" }
            }
            canTranscribe = true
        } catch {
            if (log) { messageLog += "\(error.localizedDescription)\n" }
        }
    }

    func benchCurrentModel() async {
        if sonorContext == nil {
            messageLog += "Cannot bench without loaded model\n"
            return
        }
        messageLog += "Running benchmark for loaded model\n"
        let result = await sonorContext?.benchFull(modelName: "<current>", nThreads: Int32(min(4, cpuCount())))
        if (result != nil) { messageLog += result! + "\n" }
    }

    func bench(models: [Model]) async {
        let nThreads = Int32(min(4, cpuCount()))







        messageLog += "Running benchmark for all downloaded models\n"
        messageLog += "| CPU | OS | Config | Model | Th | FA | Enc. | Dec. | Bch5 | PP | Commit |\n"
        messageLog += "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n"
        for model in models {
            loadModel(path: model.fileURL, log: false)
            if sonorContext == nil {
                messageLog += "Cannot bench without loaded model\n"
                break
            }
            let result = await sonorContext?.benchFull(modelName: model.name, nThreads: nThreads)
            if (result != nil) { messageLog += result! + "\n" }
        }
        messageLog += "Benchmarking completed\n"
    }
    func transcribeSample() async {
        if let sampleUrl {
            await transcribeAudio(sampleUrl)
        } else {
            messageLog += "Could not locate sample\n"
        }
    }
    private func transcribeAudio(_ url: URL) async {
        if (!canTranscribe) {
            return
        }
        guard let sonorContext else {
            return
        }
        do {
            canTranscribe = false
            messageLog += "Reading wave samples...\n"
            let data = try readAudioSamples(url)
            messageLog += "Transcribing data...\n"
            await sonorContext.fullTranscribe(samples: data)
            let text = await sonorContext.getTranscription()
            messageLog += "Done: \(text)\n"
        } catch {
            messageLog += "\(error.localizedDescription)\n"
        }
        canTranscribe = true
    }
    private func readAudioSamples(_ url: URL) throws -> [Float] {
        stopPlayback()
        try startPlayback(url)
        return try decodeWaveFile(url)
    }
    func toggleRecord() async {
        if isRecording {
            await recorder.stopRecording()
            isRecording = false
            if let recordedFile {
                await transcribeAudio(recordedFile)
            }
        } else {
            requestRecordPermission { granted in
                if granted {
                    Task {
                        do {
                            self.stopPlayback()
                            let file = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                                .appending(path: "output.wav")
                            try await self.recorder.startRecording(toOutputFile: file, delegate: self)
                            self.isRecording = true
                            self.recordedFile = file
                        } catch {
                            self.messageLog += "\(error.localizedDescription)\n"
                            self.isRecording = false
                        }
                    }
                }
            }
        }
    }
    private func requestRecordPermission(response: @escaping (Bool) -> Void) {
#if os(macOS)
        response(true)
#else
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            response(granted)
        }
#endif
    }
    private func startPlayback(_ url: URL) throws {
        audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
    }
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            Task {
                await handleRecError(error)
            }
        }
    }
    private func handleRecError(_ error: Error) {
        messageLog += "\(error.localizedDescription)\n"
        isRecording = false
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task {
            await onDidFinishRecording()
        }
    }
    private func onDidFinishRecording() {
        isRecording = false
    }
}


fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}
