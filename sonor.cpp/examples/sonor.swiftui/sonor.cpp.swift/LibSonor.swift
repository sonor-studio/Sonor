import Foundation
import UIKit
import sonor

enum SonorError: Error {
    case couldNotInitializeContext
}


actor SonorContext {
    private var context: OpaquePointer

    init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        sonor_free(context)
    }

    func fullTranscribe(samples: [Float]) {
        let maxThreads = max(1, min(8, cpuCount() - 2))
        var params = sonor_full_default_params(SONOR_SAMPLING_GREEDY)
        "en".withCString { en in
            params.print_realtime   = true
            params.print_progress   = false
            params.print_timestamps = true
            params.print_special    = false
            params.translate        = false
            params.language         = en
            params.n_threads        = Int32(maxThreads)
            params.offset_ms        = 0
            params.no_context       = true
            params.single_segment   = false

            sonor_reset_timings(context)
            samples.withUnsafeBufferPointer { samples in
                if (sonor_full(context, params, samples.baseAddress, Int32(samples.count)) != 0) {
                } else {
                    sonor_print_timings(context)
                }
            }
        }
    }

    func getTranscription() -> String {
        var transcription = ""
        for i in 0..<sonor_full_n_segments(context) {
            transcription += String.init(cString: sonor_full_get_segment_text(context, i))
        }
        return transcription
    }

    static func benchMemcpy(nThreads: Int32) async -> String {
        return String.init(cString: sonor_bench_memcpy_str(nThreads))
    }

    static func benchGgmlMulMat(nThreads: Int32) async -> String {
        return String.init(cString: sonor_bench_ggml_mul_mat_str(nThreads))
    }

    private func systemInfo() -> String {
        var info = ""
        return String(info.dropLast())
    }

    func benchFull(modelName: String, nThreads: Int32) async -> String {
        let nMels = sonor_model_n_mels(context)
        if (sonor_set_mel(context, nil, 0, nMels) != 0) {
            return "error: failed to set mel"
        }

        if (sonor_encode(context, 0, nThreads) != 0) {
            return "error: failed to encode"
        }

        var tokens = [sonor_token](repeating: 0, count: 512)

        if (sonor_decode(context, &tokens, 256, 0, nThreads) != 0) {
            return "error: failed to decode"
        }

        if (sonor_decode(context, &tokens, 1, 256, nThreads) != 0) {
            return "error: failed to decode"
        }

        sonor_reset_timings(context)

        if (sonor_encode(context, 0, nThreads) != 0) {
            return "error: failed to encode"
        }

        for i in 0..<256 {
            if (sonor_decode(context, &tokens, 1, Int32(i), nThreads) != 0) {
                return "error: failed to decode"
            }
        }

        for _ in 0..<64 {
            if (sonor_decode(context, &tokens, 5, 0, nThreads) != 0) {
                return "error: failed to decode"
            }
        }

        for _ in 0..<16 {
            if (sonor_decode(context, &tokens, 256, 0, nThreads) != 0) {
                return "error: failed to decode"
            }
        }

        sonor_print_timings(context)

        let deviceModel = await UIDevice.current.model
        let systemName = await UIDevice.current.systemName
        let systemInfo = self.systemInfo()
        let timings: sonor_timings = sonor_get_timings(context).pointee
        let encodeMs = String(format: "%.2f", timings.encode_ms)
        let decodeMs = String(format: "%.2f", timings.decode_ms)
        let batchdMs = String(format: "%.2f", timings.batchd_ms)
        let promptMs = String(format: "%.2f", timings.prompt_ms)
        return "| \(deviceModel) | \(systemName) | \(systemInfo) | \(modelName) | \(nThreads) | 1 | \(encodeMs) | \(decodeMs) | \(batchdMs) | \(promptMs) | <todo> |"
    }

    static func createContext(path: String) throws -> SonorContext {
        var params = sonor_context_default_params()
#if targetEnvironment(simulator)
        params.use_gpu = false
#else
        params.flash_attn = true 
#endif
        let context = sonor_init_from_file_with_params(path, params)
        if let context {
            return SonorContext(context: context)
        } else {
            throw SonorError.couldNotInitializeContext
        }
    }
}

fileprivate func cpuCount() -> Int {
    ProcessInfo.processInfo.processorCount
}
