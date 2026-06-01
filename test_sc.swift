import ScreenCaptureKit
import AVFoundation

if #available(macOS 12.3, *) {
    Task {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { print("no display"); exit(1) }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 1
            config.height = 1
            config.showsCursor = false
            config.capturesAudio = true
            
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try await stream.startCapture()
            print("started successfully")
            try await stream.stopCapture()
            exit(0)
        } catch {
            print("error: \(error)")
            exit(1)
        }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(3))
}
