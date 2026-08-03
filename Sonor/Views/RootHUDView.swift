import SwiftUI

struct RootHUDView: View {
    @ObservedObject var controller: AppController
    @AppStorage("hudPositionMode") private var hudPositionMode: HUDPositionMode = .free
    
    var body: some View {
        if hudPositionMode == .notch {
            NotchHUDView(controller: controller)
        } else {
            CapsuleHUDView(controller: controller)
        }
    }
}
