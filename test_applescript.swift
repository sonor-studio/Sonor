import Foundation

if let script = NSAppleScript(source: "set volume without output muted") {
    var error: NSDictionary?
    script.executeAndReturnError(&error)
    if let error = error {
        print("Error: \(error)")
    } else {
        print("Success")
    }
}
