import Foundation

typealias MRMediaRemoteGetNowPlayingApplicationPlaybackStateFunction = @convention(c) (DispatchQueue, @escaping (Int) -> Void) -> Void

func checkIsMediaPlaying(completion: @escaping (Bool) -> Void) {
    let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL)
    
    guard let bundle = bundle, 
          let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingApplicationPlaybackState" as CFString) else {
        print("Failed to load MediaRemote")
        completion(false)
        return
    }
    
    let funcPtr = unsafeBitCast(pointer, to: MRMediaRemoteGetNowPlayingApplicationPlaybackStateFunction.self)
    
    funcPtr(DispatchQueue.main) { state in
        print("MediaRemote state:", state)
        completion(state == 1) // 1 means playing
    }
}

checkIsMediaPlaying { isPlaying in
    print("Is playing:", isPlaying)
    exit(0)
}
RunLoop.main.run()
