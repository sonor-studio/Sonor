import Foundation

typealias MRMediaRemoteSendCommandFunction = @convention(c) (Int, Any?) -> Bool

func sendPauseCommand() {
    let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL)
    
    guard let bundle = bundle, 
          let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else {
        print("Failed to load MediaRemote")
        return
    }
    
    let funcPtr = unsafeBitCast(pointer, to: MRMediaRemoteSendCommandFunction.self)
    
    let result = funcPtr(2, nil)
    print("Pause command result:", result)
}

sendPauseCommand()
