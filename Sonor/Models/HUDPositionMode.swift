import Foundation

enum HUDPositionMode: String, CaseIterable, Identifiable {
    case top = "top"
    case bottom = "bottom"
    case free = "free"
    
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .free: return "Free"
        }
    }
}
