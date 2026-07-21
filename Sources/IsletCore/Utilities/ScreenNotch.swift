import AppKit

/// Geometry describing the physical notch (or a synthesized virtual notch on
/// notchless displays) for a given `NSScreen`.
struct NotchGeometry {
    /// The screen this geometry belongs to.
    let screen: NSScreen
    /// Rect of the notch itself, in screen (bottom-left origin) coordinates.
    let notchRect: CGRect
    /// Whether the display physically has a notch.
    let hasPhysicalNotch: Bool

    var notchWidth: CGFloat { notchRect.width }
    var notchHeight: CGFloat { notchRect.height }
}

enum ScreenNotch {
    /// Default synthesized notch size for displays without a physical notch.
    static let virtualNotchSize = CGSize(width: 220, height: 32)

    /// Resolve notch geometry for a screen, using the real notch when present
    /// and a centered virtual handle otherwise.
    static func geometry(for screen: NSScreen) -> NotchGeometry {
        if let physical = physicalNotchRect(for: screen) {
            return NotchGeometry(screen: screen, notchRect: physical, hasPhysicalNotch: true)
        }

        // Notchless display: synthesize a centered handle flush with the top edge.
        let frame = screen.frame
        let size = virtualNotchSize
        let rect = CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return NotchGeometry(screen: screen, notchRect: rect, hasPhysicalNotch: false)
    }

    /// Compute the real notch rect from the screen's auxiliary top areas.
    ///
    /// On notched Macs the menu bar is split into a left and right area with the
    /// notch in between; the gap between those two areas is the notch.
    private static func physicalNotchRect(for screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0 else { return nil }

        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchX = left.maxX
            let notchWidth = right.minX - left.maxX
            if notchWidth > 0 {
                return CGRect(
                    x: notchX,
                    y: frame.maxY - topInset,
                    width: notchWidth,
                    height: topInset
                )
            }
        }

        // Fallback: estimate a centered notch using the safe-area inset height.
        let estimatedWidth: CGFloat = 200
        return CGRect(
            x: frame.midX - estimatedWidth / 2,
            y: frame.maxY - topInset,
            width: estimatedWidth,
            height: topInset
        )
    }

    /// The screen that carries the built-in notch, if any; otherwise the main screen.
    static var builtInScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    /// Resolve the set of target screens for a given targeting preference.
    static func targetScreens(for targeting: ScreenTargeting) -> [NSScreen] {
        switch targeting {
        case .builtInOnly:
            return builtInScreen.map { [$0] } ?? []
        case .primaryOnly:
            return NSScreen.main.map { [$0] } ?? []
        case .allScreens:
            return NSScreen.screens
        }
    }
}
