import AppKit
import SwiftUI

/// Which glass material a panel wants.
///
/// Mirrors the cases of `NSGlassEffectView.Style` that Islet actually uses, but as
/// a plain enum available on every supported OS. The real, macOS 26-only type is
/// never named outside an availability check: a type in a function signature or a
/// stored property is resolved at compile time regardless of runtime branches, so
/// referring to `NSGlassEffectView.Style` in the `glassPanel` signature would pin
/// the whole app to macOS 26 even though every call site is guarded.
enum GlassStyle {
    case regular
    case clear
}

/// Whether this Mac can render real Liquid Glass.
///
/// A single place to ask, so the settings picker, the persisted-value sanitizer,
/// and the rendering layer can never disagree about it.
enum SystemCapabilities {
    static var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

/// Bridges AppKit's native `NSGlassEffectView` (macOS 26's real Liquid Glass
/// material) into SwiftUI as a **background layer**, falling back to
/// `NSVisualEffectView` on earlier systems.
///
/// Deliberately does not host SwiftUI content inside the glass view's
/// `contentView`. `NSGlassEffectView` manages its own content layout, and swapping
/// a hosted SwiftUI tree underneath it (e.g. changing notch tabs) makes the effect
/// drop out. Rendering glass behind ordinary SwiftUI content is stable and looks
/// identical for opaque panels.
///
/// The fallback is deliberately *not* offered as the notch's "Liquid Glass"
/// material — that option is hidden outright on older systems, since a vibrancy
/// blur is a visibly different thing and dressing it up as glass would only make
/// the setting a lie. The fallback exists for chrome that is glass unconditionally,
/// like `GlassSlider`, which needs *some* translucent surface everywhere rather
/// than a hole in the UI.
struct GlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tint: Color?
    var style: GlassStyle = .regular

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            // An empty content view guarantees the material renders even though we
            // draw the real content above it in SwiftUI.
            glass.contentView = NSView()
            apply(to: glass)
            return glass
        }
        let fallback = NSVisualEffectView()
        fallback.blendingMode = .behindWindow
        fallback.state = .active
        apply(to: fallback)
        return fallback
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            apply(to: glass)
        } else if let fallback = view as? NSVisualEffectView {
            apply(to: fallback)
        }
    }

    @available(macOS 26.0, *)
    private func apply(to glass: NSGlassEffectView) {
        glass.cornerRadius = cornerRadius
        glass.style = style == .clear ? .clear : .regular
        glass.tintColor = tint.map(NSColor.init)
    }

    private func apply(to fallback: NSVisualEffectView) {
        // `.clear` asks for the most see-through surface available; the closest
        // pre-26 equivalents are the HUD and popover materials.
        fallback.material = style == .clear ? .hudWindow : .popover
        fallback.wantsLayer = true
        fallback.layer?.cornerRadius = cornerRadius
        fallback.layer?.masksToBounds = true
        fallback.layer?.backgroundColor = tint.map { NSColor($0).cgColor }
    }
}

extension View {
    /// Render this view on top of a native Liquid Glass panel, or its closest
    /// pre-macOS 26 equivalent.
    func glassPanel(cornerRadius: CGFloat,
                    tint: Color? = nil,
                    style: GlassStyle = .regular) -> some View {
        background(GlassBackground(cornerRadius: cornerRadius, tint: tint, style: style))
    }
}
