import Foundation

func runAppleScript(_ source: String) {
    if let script = NSAppleScript(source: source) {
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
        } else {
            print("AppleScript executed successfully")
        }
    }
}

// System Events key code 16 is 'y', let's test if we can send media keys via System Events.
// Actually, media key 16 play/pause is not a key code, it's a HID event.
