import Cocoa
import AudioToolbox

let url = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
var soundID: SystemSoundID = 0
AudioServicesCreateSystemSoundID(url as CFURL, &soundID)
AudioServicesPlayAlertSound(soundID)
Thread.sleep(forTimeInterval: 2.0)
