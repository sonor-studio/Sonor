import Foundation

let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework") as CFURL)
guard let bundle = bundle else {
    print("No MediaRemote framework")
    exit(1)
}

let MRMediaRemoteGetNowPlayingInfoPointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString)
typealias MRMediaRemoteGetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void

guard let pointer = MRMediaRemoteGetNowPlayingInfoPointer else {
    print("No MRMediaRemoteGetNowPlayingInfo")
    exit(1)
}

let MRMediaRemoteGetNowPlayingInfo = unsafeBitCast(pointer, to: MRMediaRemoteGetNowPlayingInfoFunction.self)

let semaphore = DispatchSemaphore(value: 0)

MRMediaRemoteGetNowPlayingInfo(DispatchQueue.main) { info in
    print("Info: \(info)")
    semaphore.signal()
}

_ = semaphore.wait(timeout: .now() + 5.0)
