import Foundation
import AppKit

func runAppleScript(_ source: String) {
    if let script = NSAppleScript(source: source) {
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("Error: \(error)")
        } else {
            print("Success for: \(source)")
        }
    }
}

print("Muting...")
runAppleScript("set volume with output muted")
Thread.sleep(forTimeInterval: 2.0)
print("Unmuting...")
runAppleScript("set volume without output muted")
