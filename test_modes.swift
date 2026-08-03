import Foundation

struct VoiceMode: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var audioBehavior: AudioBehavior?
    var pauseMusic: Bool?
}

enum AudioBehavior: String, Codable {
    case keep
    case mute
    case pause
}

let json = """
[
    {
        "name": "Test",
        "pauseMusic": true,
        "audioBehavior": "pause"
    }
]
"""

let data = json.data(using: .utf8)!
do {
    let modes = try JSONDecoder().decode([VoiceMode].self, from: data)
    let newModes = modes.map { old -> VoiceMode in
        var newMode = old
        if old.audioBehavior == nil {
            newMode.audioBehavior = (old.pauseMusic ?? false) ? .mute : .keep
        }
        return newMode
    }
    print("Modes: \\(newModes.map { $0.audioBehavior })")
} catch {
    print("Error: \\(error)")
}
