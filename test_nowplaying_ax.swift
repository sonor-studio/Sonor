import Foundation
import ApplicationServices
import AppKit

let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
let accessEnabled = AXIsProcessTrustedWithOptions(options)
if !accessEnabled {
    print("No accessibility access")
    exit(1)
}

let systemWideElement = AXUIElementCreateSystemWide()
print("System Wide Element created")

let runningApps = NSWorkspace.shared.runningApplications
var controlCenterPid: pid_t = 0
for app in runningApps {
    if app.bundleIdentifier == "com.apple.controlcenter" {
        controlCenterPid = app.processIdentifier
        break
    }
}

if controlCenterPid != 0 {
    print("Control Center PID: \(controlCenterPid)")
    let ccApp = AXUIElementCreateApplication(controlCenterPid)
    
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(ccApp, kAXChildrenAttribute as CFString, &value)
    
    if result == .success, let children = value as? [AXUIElement] {
        print("Control Center children count: \(children.count)")
    } else {
        print("Could not get children")
    }
}
