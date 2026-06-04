import Foundation
import Combine

@objc(DebugLogger)
public class DebugLogger: NSObject, ObservableObject {
    @objc public static let shared = DebugLogger()
    
    @Published public var logs: [String] = []
    
    private override init() { super.init() }
    
    @objc public func addLog(_ message: String) {
        DispatchQueue.main.async {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = formatter.string(from: Date())
            self.logs.append("[\(timestamp)] \(message)")
            
            if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                let logFileURL = desktop.appendingPathComponent("sonor_debug.log")
                let logLine = "[\(timestamp)] \(message)\n"
                if let data = logLine.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: logFileURL.path) {
                        if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(data)
                            fileHandle.closeFile()
                        }
                    } else {
                        try? data.write(to: logFileURL)
                    }
                }
            }
        }
    }
    
    @objc public func clearLogs() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
}

@_cdecl("c_add_log")
public func c_add_log(_ msg: UnsafePointer<CChar>) {
    let str = String(cString: msg)
    DebugLogger.shared.addLog(str)
    
    // Zapis do pliku na pulpicie w razie crashu
    if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
        let logFileURL = desktop.appendingPathComponent("sonor_debug.log")
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let logLine = "[\(timestamp)] \(str)\n"
        
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
}
