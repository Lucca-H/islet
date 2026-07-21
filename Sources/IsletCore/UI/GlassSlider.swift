import SwiftUI

/// A bespoke slider rendered as a Liquid Glass capsule track with a glass thumb —
/// matching the notch's overall material rather than the stock `Slider` control.
struct GlassSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 0.01

    @State private var isDragging = false
    private let trackHeight: CGFloat = 26
    private let thumbDiameter: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let fraction = normalizedFraction
            let thumbX = thumbDiameter / 2 + fraction * (width - thumbDiameter)

            ZStack(alignment: .leading) {
                GlassEffectView(cornerRadius: trackHeight / 2, tint: Color.white.opacity(0.05)) {
                    Color.clear
                }
                .frame(height: trackHeight)

                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: max(thumbDiameter, thumbX), height: trackHeight)
                    .allowsHitTesting(false)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.35), radius: isDragging ? 4 : 2, y: 1)
                    .scaleEffect(isDragging ? 1.12 : 1.0)
                    .position(x: thumbX, y: trackHeight / 2)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let clampedX = min(max(drag.location.x, thumbDiameter / 2), width - thumbDiameter / 2)
                        let newFraction = (clampedX - thumbDiameter / 2) / max(1, width - thumbDiameter)
                        set(fraction: newFraction)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: trackHeight)
    }

    private var normalizedFraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func set(fraction: Double) {
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let stepped = (raw / step).rounded() * step
        value = min(max(stepped, range.lowerBound), range.upperBound)
    }
}
