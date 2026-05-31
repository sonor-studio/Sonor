import Foundation

func isAudioActivelyPlayingFast() -> Bool {
    let task = Process()
    task.launchPath = "/usr/bin/pmset"
    task.arguments = ["-g", "assertions"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            // Szukamy asercji snu (PreventUserIdleSystemSleep lub PreventUserIdleDisplaySleep)
            if line.contains("PreventUserIdleSystemSleep") || line.contains("PreventUserIdleDisplaySleep") {
                // Ignorujemy powolne lub systemowe asercje
                if line.contains("coreaudiod") || line.contains("powerd") || line.contains("WindowServer") {
                    continue
                }
                
                // Ignorujemy asercje, które nie pochodzą od aplikacji (zazwyczaj zawierają "named:")
                if line.contains("named:") {
                    print("Found active fast assertion:", line)
                    return true
                }
            }
        }
    }
    return false
}

print("Is playing fast?", isAudioActivelyPlayingFast())
