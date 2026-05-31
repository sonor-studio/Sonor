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

    var status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &defaultOutputDeviceIDAddress,
        0,
        nil,
        &defaultOutputDeviceIDSize,
        &defaultOutputDeviceID
    )

    if status != noErr { return false }

    var isRunning = UInt32(0)
    var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
    var isRunningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    status = AudioObjectGetPropertyData(
        defaultOutputDeviceID,
        &isRunningAddress,
        0,
        nil,
        &isRunningSize,
        &isRunning
    )

    if status != noErr { return false }

    return isRunning != 0
}

print(isSystemAudioPlaying())
