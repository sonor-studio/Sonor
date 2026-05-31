import Foundation

func isAudioPlayingAccordingToPmset() -> Bool {
    let task = Process()
    task.launchPath = "/usr/bin/pmset"
    task.arguments = ["-g", "assertions"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
        // Look for PreventUserIdleSystemSleep by coreaudiod
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("coreaudiod") && line.contains("PreventUserIdleSystemSleep") {
                return true
            }
        }
    }
    return false
}

print("Is audio playing according to pmset?", isAudioPlayingAccordingToPmset())
