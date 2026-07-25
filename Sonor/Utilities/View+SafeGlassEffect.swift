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
    var isInteractive: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("hudAppearance") var hudAppearance = "glass"
    
    func body(content: Content) -> some View {
        let isSolid = hudAppearance == "solid"
        if isSolid {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 1)
                )
        } else {
            if #available(macOS 26.0, *) {
            if isInteractive {
                content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            let isDark = colorScheme == .dark
            content
                .background(
                    ActiveVisualEffectView(
                        material: isDark ? .hudWindow : .headerView,
                        blendingMode: .behindWindow,
                        state: .active,
                        cornerRadius: cornerRadius,
                        colorScheme: colorScheme
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(isDark ? Color.black.opacity(0.1) : Color.white.opacity(0.2))
                    )
                )
            }
        }
    }
}

extension View {
    func safeGlassEffect(cornerRadius: CGFloat, isInteractive: Bool = false) -> some View {
        self.modifier(SafeGlassModifier(cornerRadius: cornerRadius, isInteractive: isInteractive))
    }
}

extension NSWindow {
    static let standardCornerRadius: CGFloat = {
        if let radius = NSWindow().value(forKey: "cornerRadius") as? CGFloat {
            return radius
        }
        return 10.0
    }()
}
