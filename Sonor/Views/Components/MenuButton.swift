import SwiftUI

struct MenuButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundColor(isSelected ? (colorScheme == .dark ? .black : .white) : .primary.opacity(0.8))
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? (colorScheme == .dark ? .black : .white) : .primary.opacity(0.8))
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(colorScheme == .dark ? Color.black : Color.white)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white : Color.black)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.primary.opacity(0.05))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false) // Wyłączenie focusu
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}
