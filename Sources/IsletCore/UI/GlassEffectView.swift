import AppKit
import SwiftUI

/// Bridges AppKit's native `NSGlassEffectView` (macOS 26's real Liquid Glass
/// material) into SwiftUI as a **background layer**.
///
/// Deliberately does not host SwiftUI content inside the glass view's
/// `contentView`. `NSGlassEffectView` manages its own content layout, and swapping
/// a hosted SwiftUI tree underneath it (e.g. changing notch tabs) makes the effect
/// drop out. Rendering glass behind ordinary SwiftUI content is stable and looks
/// identical for opaque panels.
struct GlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tint: Color?
    var style: NSGlassEffectView.Style = .regular

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        // An empty content view guarantees the material renders even though we
        // draw the real content above it in SwiftUI.
        glass.contentView = NSView()
        apply(to: glass)
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        apply(to: glass)
    }

    private func apply(to glass: NSGlassEffectView) {
        glass.cornerRadius = cornerRadius
        glass.style = style
        glass.tintColor = tint.map(NSColor.init)
    }
}

extension View {
    /// Render this view on top of a native Liquid Glass panel.
    func glassPanel(cornerRadius: CGFloat,
                    tint: Color? = nil,
                    style: NSGlassEffectView.Style = .regular) -> some View {
        background(GlassBackground(cornerRadius: cornerRadius, tint: tint, style: style))
    }
}
