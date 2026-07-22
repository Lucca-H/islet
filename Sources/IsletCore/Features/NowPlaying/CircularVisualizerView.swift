import SwiftUI

/// A radial spectrum: one bar per frequency band, arranged around a ring, growing
/// outward with that band's level.
///
/// Bass sits at 12 o'clock and sweeps clockwise up through treble, so the motion
/// reads as a rotating spectrum rather than arbitrary flicker. When the engine isn't
/// actually capturing, it falls back to a gentle idle animation at the same geometry,
/// so the layout never shifts based on whether the feature is on.
///
/// Layout note: each bar is laid out centred, pushed outward with `.offset`, then
/// `.rotationEffect` is applied. That ordering is what makes it exact — `.offset` is
/// a render-time transform that leaves the layout frame centred, so the subsequent
/// rotation pivots around the ring's true centre. (An earlier version positioned
/// every bar manually inside a `GeometryReader` via `.position`, which put the bars
/// and the ring in subtly different coordinate spaces and left them misaligned.)
struct CircularVisualizerView: View {
    var levels: [CGFloat]
    var isLive: Bool
    var size: CGFloat
    var tint: Color = .white

    /// Raw FFT magnitudes are perceptually flat at typical listening levels — the
    /// bars technically move but read as barely alive. This multiplies the level
    /// before it's mapped to a length (clamped, so peaks pin at full height rather
    /// than overflow the ring), which is what gives the spectrum visible punch.
    private let peakGain: CGFloat = 2.1

    private var ringRadius: CGFloat { size * 0.27 }
    private var maxBarLength: CGFloat { size * 0.22 }
    private let barWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: 1)
                .frame(width: ringRadius * 2, height: ringRadius * 2)

            if isLive {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    bar(index: index, total: levels.count, level: level)
                }
            } else {
                idleBars
            }
        }
        .frame(width: size, height: size)
    }

    private var idleBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let count = max(levels.count, 24)
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    // A slow travelling wave — clearly "idle", not faking audio.
                    let phase = Double(index) / Double(count) * .pi * 2
                    let value = (sin(t * 1.6 + phase * 3) + 1) / 2
                    // Idle wave is already tuned for its own look — don't apply the
                    // live-audio boost on top, or it saturates into a solid ring.
                    bar(index: index, total: count, level: 0.06 + CGFloat(value) * 0.16, boost: false)
                }
            }
        }
    }

    private func bar(index: Int, total: Int, level: CGFloat, boost: Bool = true) -> some View {
        let raw = min(max(level, 0), 1)
        let clamped = boost ? min(raw * peakGain, 1) : raw
        let length = max(2, clamped * maxBarLength)
        let degrees = Double(index) / Double(max(total, 1)) * 360

        return Capsule()
            .fill(tint.opacity(0.35 + clamped * 0.65))
            .frame(width: barWidth, height: length)
            // Push outward from centre, *then* rotate about that centre.
            .offset(y: -(ringRadius + length / 2))
            .rotationEffect(.degrees(degrees))
            .animation(.easeOut(duration: 0.08), value: clamped)
    }
}
