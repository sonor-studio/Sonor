import Foundation
import CoreAudio

func getPropertyData(device: AudioDeviceID, selector: AudioObjectPropertySelector) -> UInt32 {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
    if status == noErr {
        return value
    }
    return 999999
}

var defaultOutputDeviceID = AudioDeviceID(0)
var size = UInt32(MemoryLayout<AudioDeviceID>.size)
var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultOutputDeviceID)

let properties: [AudioObjectPropertySelector] = [
    kAudioDevicePropertyDeviceIsAlive,
    kAudioDevicePropertyDeviceIsRunning,
    kAudioDevicePropertyDeviceIsRunningSomewhere,
    kAudioDevicePropertyJackIsConnected,
    kAudioDevicePropertyVolumeDecibels,
    kAudioDevicePropertyVolumeScalar,
    kAudioDevicePropertyMute,
    kAudioDevicePropertyPlayThru,
    kAudioDevicePropertyDataSource,
    kAudioDevicePropertyStreamFormat,
    kAudioHardwarePropertyProcessIsAudible,
    kAudioHardwarePropertyProcessIsMaster,
    kAudioHardwarePropertySleepingIsAllowed
]

print("Device ID: \(defaultOutputDeviceID)")
for prop in properties {
    let str = String(describing: prop)
    print("\(str): \(getPropertyData(device: defaultOutputDeviceID, selector: prop))")
}
