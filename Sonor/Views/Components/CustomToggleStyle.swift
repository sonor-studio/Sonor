import SwiftUI

struct CustomToggleStyle: ToggleStyle {
    @Environment(\.colorScheme) var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            RoundedRectangle(cornerRadius: 12)
                .fill(configuration.isOn ? (colorScheme == .dark ? Color.white : Color.black) : Color.primary.opacity(0.1))
                .frame(width: 40, height: 20)
                .overlay(
                    Circle()
                        .fill(configuration.isOn ? (colorScheme == .dark ? Color.black : Color.white) : Color.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 10 : -10)
                )
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}
