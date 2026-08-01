import SwiftUI

/// A rounded-rectangle-with-notch-shoulders shape.
///
/// The top edge is flush and square (it meets the physical bezel), while the
/// bottom two corners curve inward, and the top-left/top-right "shoulders" flare
/// outward with a small inverse radius — the signature notch silhouette.
struct NotchShape: Shape {
    /// Shoulder radius for each state.
    ///
    /// Not just styling: because the shoulders flare *outward*, the pill's straight
    /// left and right body edges sit `topRadius` points inside the frame. Content
    /// padded from the frame edge is therefore that much closer to the visible edge
    /// than its padding suggests — so anything laying out against the pill's sides
    /// has to start from here, not from zero.
    static let collapsedTopRadius: CGFloat = 8
    static let expandedTopRadius: CGFloat = 12

    var bottomRadius: CGFloat
    var topRadius: CGFloat

    init(bottomRadius: CGFloat = 22, topRadius: CGFloat = 10) {
        self.bottomRadius = bottomRadius
        self.topRadius = topRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let br = min(bottomRadius, rect.height / 2, rect.width / 2)
        let tr = min(topRadius, rect.height / 2)

        // Start just below the top-left, after the outward shoulder curve.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left inverse shoulder.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
            control: CGPoint(x: rect.minX + tr, y: rect.minY)
        )

        // Left edge down to the bottom-left curve.
        path.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
            control: CGPoint(x: rect.minX + tr, y: rect.maxY)
        )

        // Bottom edge to the bottom-right curve.
        path.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
            control: CGPoint(x: rect.maxX - tr, y: rect.maxY)
        )

        // Right edge up to the top-right shoulder.
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - tr, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
