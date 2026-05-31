import Foundation

func getCoreAudioCPU() -> Double {
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", "ps -A -o %cpu,comm | grep coreaudiod | grep -v grep | awk '{print $1}'"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
       let cpuUsage = Double(output) {
        return cpuUsage
    }
    return 0.0
}

for i in 1...5 {
    print("CoreAudio CPU: \(getCoreAudioCPU())%")
    Thread.sleep(forTimeInterval: 1.0)
}
