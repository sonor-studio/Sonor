import Quartz
import Cocoa

func HIDPostAuxKey(key: Int32) {
    func doKey(down: Bool) {
        let flags = NSEvent.ModifierFlags.init(rawValue: (down ? 0xa00 : 0xb00))
        let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
        
        let ev = NSEvent.otherEvent(with: .systemDefined,
                                    location: NSPoint(x: 0, y: 0),
                                    modifierFlags: flags,
                                    timestamp: 0,
                                    windowNumber: 0,
                                    context: nil,
                                    subtype: 8,
                                    data1: data1,
                                    data2: -1)
        
        let cgEvent = ev?.cgEvent
        cgEvent?.post(tap: .cghidEventTap)
    }
    doKey(down: true)
    doKey(down: false)
}

let NX_KEYTYPE_PLAY: Int32 = 16
HIDPostAuxKey(key: NX_KEYTYPE_PLAY)
