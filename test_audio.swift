import Foundation
import AVFoundation

let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff"))
player?.play()
print("Played")
