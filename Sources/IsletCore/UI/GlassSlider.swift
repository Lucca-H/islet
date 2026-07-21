import SwiftUI

/// A slider built entirely from Liquid Glass: a glass capsule track, a translucent
/// accent fill that lets the material show through, and a glass thumb.
struct GlassSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0.01

    @State private var isDragging = false
    private let trackHeight: CGFloat = 28
    private let thumbDiameter: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let travel = max(1, width - thumbDiameter)
            let thumbX = thumbDiameter / 2 + normalizedFraction * travel

            ZStack(alignment: .leading) {
                // Glass track.
                Color.clear
                    .frame(height: trackHeight)
                    .glassPanel(cornerRadius: trackHeight / 2, style: .clear)
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )

                // Translucent fill — kept see-through so the glass reads underneath.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.35)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(thumbDiameter, thumbX), height: trackHeight)
                    .allowsHitTesting(false)

                // Glass thumb.
                Color.clear
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .glassPanel(cornerRadius: thumbDiameter / 2)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(isDragging ? 0.3 : 0.18),
                            radius: isDragging ? 5 : 2, y: 1)
                    .scaleEffect(isDragging ? 1.1 : 1.0)
                    .position(x: thumbX, y: trackHeight / 2)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            }
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let clamped = min(max(drag.location.x, thumbDiameter / 2), width - thumbDiameter / 2)
                        set(fraction: (clamped - thumbDiameter / 2) / travel)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: trackHeight)
    }

    private var normalizedFraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return min(max(f, 0), 1)
    }

    private func set(fraction: Double) {
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        value = min(max(stepped, range.lowerBound), range.upperBound)
    }
}
