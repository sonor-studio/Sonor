import Foundation

typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

func checkIsMediaPlaying(completion: @escaping (Bool) -> Void) {
    let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL)
    
    guard let bundle = bundle, 
          let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString) else {
        print("Failed to load MediaRemote")
        completion(false)
        return
    }
    
    let funcPtr = unsafeBitCast(pointer, to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction.self)
    
    funcPtr(DispatchQueue.main) { isPlaying in
        completion(isPlaying)
    }
}

checkIsMediaPlaying { isPlaying in
    print("Is playing directly:", isPlaying)
    exit(0)
}
RunLoop.main.run()
