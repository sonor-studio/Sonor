import Foundation

let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL)
guard let bundle = bundle else {
    print("No MediaRemote framework")
    exit(1)
}

let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
typealias MRMediaRemoteSendCommandFunction = @convention(c) (UInt32, CFDictionary?) -> Bool

guard let pointer = MRMediaRemoteSendCommandPointer else {
    print("No MRMediaRemoteSendCommand")
    exit(1)
}

let MRMediaRemoteSendCommand = unsafeBitCast(pointer, to: MRMediaRemoteSendCommandFunction.self)

// Command 2 is Pause
let result = MRMediaRemoteSendCommand(2, nil)
print("Sent Pause command: \(result)")
