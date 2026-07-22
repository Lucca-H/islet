import SwiftUI

/// A radial spectrum: one bar per frequency band, arranged around a ring, growing
/// outward with that band's level.
///
/// Bass sits at the top and sweeps clockwise up through treble, so the motion reads
/// as a rotating spectrum rather than arbitrary flicker. When the engine isn't
/// actually capturing, it falls back to a gentle idle animation at the same
/// geometry, so the layout never shifts based on whether the feature is on.
struct CircularVisualizerView: View {
    var levels: [CGFloat]
    var isLive: Bool
    var tint: Color = .white

    private let innerRadiusRatio: CGFloat = 0.52
    private let maxBarLengthRatio: CGFloat = 0.34
    private let barWidth: CGFloat = 2.5

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let innerRadius = size / 2 * innerRadiusRatio
            let maxBar = size / 2 * maxBarLengthRatio

            ZStack {
                Circle()
                    .stroke(tint.opacity(0.14), lineWidth: 1)
                    .frame(width: innerRadius * 2, height: innerRadius * 2)
                    .position(center)

                if isLive {
                    liveBars(center: center, innerRadius: innerRadius, maxBar: maxBar)
                } else {
                    idleBars(center: center, innerRadius: innerRadius, maxBar: maxBar)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func liveBars(center: CGPoint, innerRadius: CGFloat, maxBar: CGFloat) -> some View {
        ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
            bar(index: index,
                total: levels.count,
                level: level,
                center: center,
                innerRadius: innerRadius,
                maxBar: maxBar)
        }
    }

    private func idleBars(center: CGPoint, innerRadius: CGFloat, maxBar: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let count = max(levels.count, 24)
            ForEach(0..<count, id: \.self) { index in
                // A slow travelling wave — clearly "idle", not pretending to be audio.
                let phase = Double(index) / Double(count) * .pi * 2
                let value = (sin(t * 1.6 + phase * 3) + 1) / 2
                bar(index: index,
                    total: count,
                    level: 0.06 + CGFloat(value) * 0.16,
                    center: center,
                    innerRadius: innerRadius,
                    maxBar: maxBar)
            }
        }
    }

    private func bar(index: Int,
                     total: Int,
                     level: CGFloat,
                     center: CGPoint,
                     innerRadius: CGFloat,
                     maxBar: CGFloat) -> some View {
        let fraction = Double(index) / Double(max(total, 1))
        let angle = Angle.degrees(fraction * 360 - 90) // start at 12 o'clock
        let clamped = min(max(level, 0), 1)
        let length = max(2, clamped * maxBar)
        let mid = innerRadius + length / 2

        return Capsule()
            .fill(tint.opacity(0.35 + clamped * 0.65))
            .frame(width: barWidth, height: length)
            // A capsule's long axis is vertical, and `angle` is measured from the
            // +x axis — so +90° makes the bar point radially outward rather than
            // tangentially. Position is computed directly (no `.offset`, which
            // composes confusingly with `.position`).
            .rotationEffect(angle + .degrees(90))
            .position(x: center.x + cos(angle.radians) * mid,
                      y: center.y + sin(angle.radians) * mid)
            .animation(.easeOut(duration: 0.08), value: clamped)
    }
}
