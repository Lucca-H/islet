import AppKit
import SwiftUI

/// Bridges AppKit's native `NSGlassEffectView` (macOS 26's real Liquid Glass
/// material) into SwiftUI. `NSGlassEffectView` only supports a single uniform
/// corner radius — it cannot mask to an arbitrary path — so this is used for
/// the expanded notch panel (a plain rounded rectangle), not the collapsed
/// pill's notch-hugging silhouette.
struct GlassEffectView<Content: View>: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tint: Color?
    var style: NSGlassEffectView.Style = .regular
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = hosting
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: glass.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
        ])
        context.coordinator.hosting = hosting
        apply(to: glass)
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        context.coordinator.hosting?.rootView = content
        apply(to: glass)
    }

    private func apply(to glass: NSGlassEffectView) {
        glass.cornerRadius = cornerRadius
        glass.style = style
        glass.tintColor = tint.map(NSColor.init)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var hosting: NSHostingView<Content>?
    }
}
