import AppKit

let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
print("ContentView corner radius: \(String(describing: window.contentView?.layer?.cornerRadius))")
print("Window corner radius: \(window.value(forKey: "cornerRadius") ?? "nil")")

