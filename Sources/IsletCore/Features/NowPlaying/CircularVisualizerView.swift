import SwiftUI

/// A radial spectrum: one bar per frequency band, arranged around a ring, growing
/// outward with that band's level.
///
/// Bass sits at 12 o'clock and sweeps clockwise up through treble, so the motion
/// reads as a rotating spectrum rather than arbitrary flicker. When the engine isn't
/// actually capturing, it falls back to a gentle idle animation at the same geometry,
/// so the layout never shifts based on whether the feature is on.
///
/// **Drawn in a single `Canvas`.** Each bar used to be its own `Capsule` view with its
/// own `.rotationEffect`, which meant ~96 independently composited layers each getting
/// antialiased on its own: bars whose rotation happened to land near the pixel grid
/// rendered crisp and thin, while diagonal ones smeared across an extra pixel and read
/// as noticeably fatter. The ring looked like it had bars of several different widths.
/// One canvas rasterizes every bar in the same pass with the same geometry, so they
/// come out uniform. It also collapses those ~96 animated views into one drawing,
/// which is a great deal less work per frame.
struct CircularVisualizerView: View {
    var levels: [CGFloat]
    var isLive: Bool
    var size: CGFloat
    var tint: Color = .white

    /// Multiplies the level before it's mapped to a length (clamped, so peaks pin at
    /// full height rather than overflow the ring). Originally this existed to rescue
    /// raw FFT magnitudes that read as barely alive at typical listening levels.
    /// 2.6 → 2.1 → 1.7 → 1.25: each step made peaks *less* exaggerated, not more — a
    /// prior reading of "1.7x" as an overall-size request was a misunderstanding,
    /// reverted. The last step down accompanies automatic gain control in
    /// `AudioVisualizerEngine`, which now normalizes the levels arriving here; with
    /// quiet input already scaled up upstream, the extra boost here was double-
    /// counting and left the ring saturated most of the time.
    private let peakGain: CGFloat = 1.25

    private var ringRadius: CGFloat { size * 0.27 }
    private var maxBarLength: CGFloat { size * 0.19 }

    /// Thin enough that `AudioVisualizerEngine.bandCount` ticks sit around the ring as
    /// distinct hairlines instead of overlapping into a solid annulus.
    ///
    /// 1.5pt is deliberately a whole number of device pixels on a 2x display (3px), so
    /// the bars have an exact width to land on rather than one that has to be
    /// distributed across a pixel boundary differently at every rotation.
    private let barWidth: CGFloat = 1.5
    /// Never shorter than its own width, so a silent band stays a round dot rather
    /// than collapsing into a clipped sliver that can't complete its end caps.
    private var minBarLength: CGFloat { barWidth }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                // The ring shares the canvas so it can't drift from the bars — it was
                // previously a sibling view in a ZStack, sized independently.
                let ring = Path(ellipseIn: CGRect(x: center.x - ringRadius,
                                                  y: center.y - ringRadius,
                                                  width: ringRadius * 2,
                                                  height: ringRadius * 2))
                context.stroke(ring, with: .color(tint.opacity(0.14)), lineWidth: 1)

                let values = isLive
                    ? levels
                    : Self.idleLevels(count: max(levels.count, 24),
                                      at: timeline.date.timeIntervalSinceReferenceDate)
                guard !values.isEmpty else { return }

                for (index, level) in values.enumerated() {
                    // The idle wave is tuned for its own look; applying the live-audio
                    // boost on top of it saturates the ring into a solid annulus.
                    let raw = min(max(level, 0), 1)
                    let clamped = isLive ? min(raw * peakGain, 1) : raw
                    let length = max(minBarLength, clamped * maxBarLength)

                    // Built pointing straight up from the origin, then rotated about
                    // it — so every bar is the same shape at a different angle, and the
                    // pivot is exactly the ring's centre by construction. Canvas y
                    // grows downward, so "up" is negative and a positive rotation
                    // sweeps clockwise: bass at 12 o'clock, treble around to its left.
                    let rect = CGRect(x: -barWidth / 2,
                                      y: -(ringRadius + length),
                                      width: barWidth,
                                      height: length)
                    let bar = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    let angle = Double(index) / Double(values.count) * 2 * .pi
                    let placement = CGAffineTransform(translationX: center.x, y: center.y)
                        .rotated(by: angle)

                    context.fill(bar.applying(placement),
                                 with: .color(tint.opacity(Self.opacity(forLevel: clamped))))
                }
            }
        }
        .frame(width: size, height: size)
    }

    /// A slow travelling wave for when nothing is being captured — clearly "idle"
    /// rather than faking audio.
    private static func idleLevels(count: Int, at time: TimeInterval) -> [CGFloat] {
        (0..<count).map { index in
            let phase = Double(index) / Double(count) * .pi * 2
            let value = (sin(time * 1.6 + phase * 3) + 1) / 2
            return 0.06 + CGFloat(value) * 0.16
        }
    }

    /// Brightness ramp for a bar at a given level.
    ///
    /// Starts brighter and reaches full tint well before the bar reaches full length,
    /// rather than mapping opacity linearly across the whole range — under a linear
    /// ramp only the single tallest bar was ever fully lit and everything else read as
    /// washed out. `fullBrightnessAt` is the level treated as maximum brightness;
    /// above it bars grow in length only. Kept as a single function so a future colour
    /// treatment has one place to hook into.
    private static let baseOpacity: CGFloat = 0.45
    private static let fullBrightnessAt: CGFloat = 0.55
    static func opacity(forLevel level: CGFloat) -> CGFloat {
        let t = min(level / fullBrightnessAt, 1)
        return baseOpacity + (1 - baseOpacity) * t
    }
}
