import SwiftUI
import AppKit

struct ActiveVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State
    var cornerRadius: CGFloat = 0
    var colorScheme: ColorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.layer?.cornerRadius = cornerRadius
        nsView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}

struct SafeGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) var colorScheme
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            let isDark = colorScheme == .dark
            content
                .background(
                    ActiveVisualEffectView(
                        material: .popover,
                        blendingMode: .behindWindow,
                        state: .active,
                        cornerRadius: cornerRadius,
                        colorScheme: colorScheme
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke((isDark ? Color.white : Color.black).opacity(0.15), lineWidth: 0.5)
                        .allowsHitTesting(false) 
                )
        }
    }
}

extension View {
    func safeGlassEffect(cornerRadius: CGFloat) -> some View {
        self.modifier(SafeGlassModifier(cornerRadius: cornerRadius))
    }
}
