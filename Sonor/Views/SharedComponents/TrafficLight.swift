import SwiftUI

struct TrafficLight: View {
    let color: Color
    let icon: String
    let isHovered: Bool
    let action: () -> Void
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.black.opacity(0.6))
                    .opacity(isHovered ? 1 : 0)
            )
            .onTapGesture {
                action()
            }
    }
}
