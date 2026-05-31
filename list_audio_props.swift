import Foundation
import CoreAudio

var defaultOutputDeviceID = AudioDeviceID(0)
var defaultOutputDeviceIDSize = UInt32(MemoryLayout<AudioDeviceID>.size)
var defaultOutputDeviceIDAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)

AudioObjectGetPropertyData(
    AudioObjectID(kAudioObjectSystemObject),
    &defaultOutputDeviceIDAddress,
    0,
    nil,
    &defaultOutputDeviceIDSize,
    &defaultOutputDeviceID
)

print("Default Output Device ID: \(defaultOutputDeviceID)")

// Check what kAudioDeviceProperty... returns
var address = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsRunning,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
)

var isRunning: UInt32 = 0
var size = UInt32(MemoryLayout<UInt32>.size)
AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &size, &isRunning)
print("DeviceIsRunning: \(isRunning)")

address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &size, &isRunning)
print("DeviceIsRunningSomewhere: \(isRunning)")

address.mSelector = kAudioDevicePropertyDeviceIsAlive
AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &size, &isRunning)
print("DeviceIsAlive: \(isRunning)")

address.mSelector = kAudioDevicePropertyJackIsConnected
AudioObjectGetPropertyData(defaultOutputDeviceID, &address, 0, nil, &size, &isRunning)
print("JackIsConnected: \(isRunning)")

