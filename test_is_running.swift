import Foundation
import CoreAudio

func isSystemAudioPlaying() -> Bool {
    var defaultOutputDeviceID = AudioDeviceID(0)
    var defaultOutputDeviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var defaultOutputDeviceIDAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    let status1 = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &defaultOutputDeviceIDAddress,
        0,
        nil,
        &defaultOutputDeviceIDSize,
        &defaultOutputDeviceID
    )

    if status1 != noErr { return false }

    var isRunning: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var isRunningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    let status2 = AudioObjectGetPropertyData(
        defaultOutputDeviceID,
        &isRunningAddress,
        0,
        nil,
        &size,
        &isRunning
    )

    return status2 == noErr && isRunning != 0
}

print("Is running somewhere?", isSystemAudioPlaying())
