import SwiftUI

struct SafeGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            let isDark = colorScheme == .dark
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                )
                .background(
                    // Rozjaśniamy lekko w ciemnym motywie, a w jasnym zostawiamy jak było (przezroczyste)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isDark ? Color.white.opacity(0.08) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke((isDark ? Color.white : Color.black).opacity(0.15), lineWidth: 0.5) // Ramka zostaje
                )
        }
    }
}

extension View {
    func safeGlassEffect(cornerRadius: CGFloat) -> some View {
        self.modifier(SafeGlassModifier(cornerRadius: cornerRadius))
    }
}
