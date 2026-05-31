import Foundation
import AppKit
import CoreAudio

func isPidAudible(pid: pid_t) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessIsAudible,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var qualifier = pid
    var isAudible: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        UInt32(MemoryLayout<pid_t>.size),
        &qualifier,
        &size,
        &isAudible
    )
    
    if status == noErr {
        return isAudible != 0
    } else {
        return false
    }
}

let workspace = NSWorkspace.shared
let runningApps = workspace.runningApplications
var anyAudible = false

for app in runningApps {
    if isPidAudible(pid: app.processIdentifier) {
        print("App \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier)) is AUDIBLE!")
        anyAudible = true
    }
}

if !anyAudible {
    print("No apps are currently audible.")
}
