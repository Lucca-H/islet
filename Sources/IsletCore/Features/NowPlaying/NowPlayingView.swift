import SwiftUI

/// Sizing rules for the Now Playing row.
///
/// These live here rather than inline in the view so the layout guard in
/// `SelfChecks`/tests measures the *same* numbers the view actually renders with —
/// otherwise the guard silently stops reflecting reality the moment a constant is
/// tweaked. Several of them are load-bearing together: widening the panel insets or
/// growing the transport buttons both eat width that the art/visualizer columns are
/// competing for.
enum NowPlayingLayout {
    static let columnSpacing: CGFloat = 18

    /// Share of the panel the song itself (album art + metadata + transport) may
    /// occupy, pinned to the left. The remainder belongs to the visualizer.
    static let songColumnFraction: CGFloat = 0.65

    /// How much of that remainder the visualizer square fills, centred in it. Sizing
    /// the visualizer from its own region rather than from the album art is what lets
    /// it sit centred in the space it's given — as a fraction of the art it had no
    /// relationship to the gap it was actually sitting in.
    static let visualizerFillFraction: CGFloat = 0.80

    static let smallButtonDiameter: CGFloat = 34
    static let largeButtonDiameter: CGFloat = 42
    static let buttonSpacing: CGFloat = 10

    /// The transport row can't shrink — it's three fixed circles. This is the hard
    /// floor the metadata column must always clear.
    static var transportRowMinimum: CGFloat {
        smallButtonDiameter * 2 + largeButtonDiameter + buttonSpacing * 2
    }

    /// Breathing room required *beyond* the bare transport row.
    ///
    /// Sizing the art so the metadata column lands exactly on `transportRowMinimum`
    /// technically fits, but leaves the buttons flush against both edges and gives
    /// the layout guard no margin — any later tweak would tip it straight into
    /// overflow. This keeps a deliberate buffer.
    static let metadataBreathingRoom: CGFloat = 8

    /// Fraction of the **song column** the album art may occupy.
    ///
    /// Chosen as the largest value clearing `transportRowMinimum` plus
    /// `metadataBreathingRoom` across every Settings size combination. Widening the
    /// panel insets, growing the transport buttons, or giving the visualizer a larger
    /// share will require re-deriving it; the layout check sweeps the whole slider
    /// range and fails loudly if it no longer holds.
    static let artWidthCap: CGFloat = 0.34

    /// The visualizer square: `visualizerFillFraction` of its nominal share, but never
    /// taller than the panel — at wide-and-short settings width alone would overflow it.
    static func visualizerSize(availableWidth: CGFloat, availableHeight: CGFloat) -> CGFloat {
        min(availableWidth * (1 - songColumnFraction) * visualizerFillFraction,
            availableHeight)
    }

    /// The region the visualizer is centred in.
    ///
    /// Derived *back* from the square rather than being a flat share of the panel.
    /// When height binds — which it does at the default size — the square comes out
    /// smaller than its share, and a fixed region left that slack sitting as dead
    /// space between the metadata and the ring, plus a wider right margin than the
    /// left one. Sizing the region to the square keeps the 80% fill (so the ring still
    /// has breathing room either side) and hands the leftover back to the song column,
    /// which is where the eye actually wants it.
    static func visualizerRegionWidth(availableWidth: CGFloat, availableHeight: CGFloat) -> CGFloat {
        visualizerSize(availableWidth: availableWidth, availableHeight: availableHeight)
            / visualizerFillFraction
    }

    /// Width the song column gets: everything the visualizer doesn't need. With the
    /// visualizer off there's no second region at all, so it takes the whole panel.
    static func songColumnWidth(availableWidth: CGFloat,
                                availableHeight: CGFloat,
                                hasVisualizer: Bool) -> CGFloat {
        guard hasVisualizer else { return availableWidth }
        return availableWidth - visualizerRegionWidth(availableWidth: availableWidth,
                                                      availableHeight: availableHeight)
    }

    /// Album art fills the available height, capped against the song column's width.
    ///
    /// It's a square driven by height, beside a metadata column that can't go below
    /// `transportRowMinimum`. Sizing on height alone overflowed at narrow "Expanded
    /// width" settings — at 420x210 the metadata column was left 12pt; at 420x340 it
    /// went negative.
    static func artSize(availableHeight: CGFloat, songColumnWidth: CGFloat) -> CGFloat {
        max(72, min(availableHeight, songColumnWidth * artWidthCap))
    }

    /// Width left for the metadata column once the art and its gap are taken.
    static func metadataWidth(songColumnWidth: CGFloat, artSize: CGFloat) -> CGFloat {
        songColumnWidth - artSize - columnSpacing
    }

    // MARK: Vertical budget

    /// What the metadata column costs before any progress bar: the source line, title,
    /// artist, transport row, and the two spacers' minimums. The column is capped at
    /// the album art's height, so this is what's left to spend.
    static let metadataFixedHeight: CGFloat = 12 + 22 + 18 + largeButtonDiameter
    /// The two `Spacer(minLength:)` values in the metadata column, summed.
    static let metadataSpacerMinimum: CGFloat = 6 + 6
    /// Bar plus the clearance below it, and additionally the timestamp row plus its gap.
    static let progressBarOnlyHeight: CGFloat = 3 + 8
    static let progressBarWithLabelsHeight: CGFloat = 3 + 2 + 11 + 8

    /// How much of the progress bar fits in a column of the given height.
    ///
    /// The panel is small and the vertical budget genuinely doesn't always stretch to
    /// elapsed/remaining labels — at the shortest "Expanded height" it doesn't stretch
    /// to a bar at all. Degrading in two steps beats either overflowing the column or
    /// dropping the feature entirely on smaller panels.
    enum ProgressStyle { case hidden, barOnly, withLabels }

    static func progressStyle(columnHeight: CGFloat) -> ProgressStyle {
        let spare = columnHeight - metadataFixedHeight - metadataSpacerMinimum
        if spare >= progressBarWithLabelsHeight { return .withLabels }
        if spare >= progressBarOnlyHeight { return .barOnly }
        return .hidden
    }
}

/// Expanded Now Playing panel.
///
/// Three columns, left to right: large album art, the track's identity and transport
/// controls, and a circular spectrum visualizer. The metadata column is the flexible
/// one — art and visualizer keep fixed square footprints so the layout stays balanced
/// as the notch width setting changes.
struct NowPlayingView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore

    private var info: NowPlayingInfo? { vm.nowPlaying.info }

    var body: some View {
        if let info {
            // Sized from the actual available height rather than a fixed constant, so
            // a smaller "Expanded height" setting (or the notch inset on real
            // hardware) shrinks the art instead of overflowing the panel.
            GeometryReader { proxy in
                let hasVisualizer = settings.audioVisualizerEnabled
                let songWidth = NowPlayingLayout.songColumnWidth(availableWidth: proxy.size.width,
                                                                 availableHeight: proxy.size.height,
                                                                 hasVisualizer: hasVisualizer)
                let artSize = NowPlayingLayout.artSize(availableHeight: proxy.size.height,
                                                       songColumnWidth: songWidth)
                // Two fixed-width regions rather than one flexible HStack: the song
                // column is capped at its share and pinned left, and the visualizer
                // gets the rest to centre itself in. Letting the columns size
                // themselves left the visualizer wherever the metadata happened to
                // end, which is why it never looked centred.
                HStack(spacing: 0) {
                    HStack(alignment: .center, spacing: NowPlayingLayout.columnSpacing) {
                        artwork
                            .frame(width: artSize, height: artSize)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.45), radius: 12, y: 5)

                        metadata(info, height: artSize)
                    }
                    .frame(width: songWidth, alignment: .leading)

                    if hasVisualizer {
                        CircularVisualizerView(
                            levels: vm.audioVisualizer.bars,
                            isLive: vm.audioVisualizer.isCapturing && vm.audioVisualizer.hasSignal,
                            size: NowPlayingLayout.visualizerSize(availableWidth: proxy.size.width,
                                                                  availableHeight: proxy.size.height)
                        )
                        .frame(width: NowPlayingLayout.visualizerRegionWidth(availableWidth: proxy.size.width,
                                                                             availableHeight: proxy.size.height),
                               alignment: .center)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            }
        } else {
            emptyState
        }
    }

    private func metadata(_ info: NowPlayingInfo, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                if let icon = vm.nowPlaying.sourceIcon {
                    Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                }
                Text(info.sourceName.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(1.3)
            }

            Spacer(minLength: 6)

            Text(info.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(info.artist)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .padding(.top, 2)

            // Tighter above the bar than below it. Even gaps put the timestamp row
            // immediately on top of the transport circles, which read as one crowded
            // block; the bar belongs with the track text it describes, and the buttons
            // need the clearance more.
            Spacer(minLength: 6)

            let progressStyle = NowPlayingLayout.progressStyle(columnHeight: height)
            if progressStyle != .hidden,
               let progress = vm.nowPlaying.progress, progress.isMeasurable {
                PlaybackProgressBar(progress: progress,
                                    showsLabels: progressStyle == .withLabels)
                    .padding(.bottom, 8)
            }

            // `.firstTextBaseline` and friends would align on glyph metrics, which
            // differ per symbol; `.center` keeps the three circles concentric on one
            // horizontal axis regardless of the differing diameters.
            HStack(alignment: .center, spacing: NowPlayingLayout.buttonSpacing) {
                transportButton("backward.fill",
                                diameter: NowPlayingLayout.smallButtonDiameter,
                                glyph: 13) {
                    vm.nowPlaying.previousTrack()
                }
                transportButton(info.isPlaying ? "pause.fill" : "play.fill",
                                diameter: NowPlayingLayout.largeButtonDiameter,
                                glyph: 16) {
                    vm.nowPlaying.togglePlayPause()
                }
                transportButton("forward.fill",
                                diameter: NowPlayingLayout.smallButtonDiameter,
                                glyph: 13) {
                    vm.nowPlaying.nextTrack()
                }
            }
            // Centred under the progress bar rather than left-aligned with the text.
            // Left-aligned, the three circles sat in a cluster at one end of a
            // full-width bar with a large void beside them; centring gives the bar and
            // the transport row a shared axis. The title and artist stay left-aligned —
            // they're read as text, and ragged-left would be worse.
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: height, alignment: .leading)
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = vm.nowPlaying.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.35))
                )
        }
    }

    private func transportButton(_ symbol: String,
                                 diameter: CGFloat,
                                 glyph: CGFloat,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .medium))
                // A play triangle's visual mass sits left of its geometric centre, so
                // centring it mathematically makes it look shifted left. Every other
                // transport glyph here is symmetric and needs no nudge.
                .offset(x: symbol == "play.fill" ? 1.5 : 0)
        }
        .buttonStyle(.outline(diameter: diameter))
    }

    /// Elapsed/remaining track position.
    ///
    /// The underlying sample only refreshes every few seconds (an AppleScript poll —
    /// neither player pushes position), so the bar is driven by a `TimelineView` that
    /// extrapolates from the last sample rather than animating between them. Animating
    /// sample-to-sample would visibly step every 3 seconds; extrapolating is smooth and
    /// self-corrects each time a real reading lands.
    private struct PlaybackProgressBar: View {
        let progress: PlaybackProgress
        let showsLabels: Bool

        private static let barHeight: CGFloat = 3

        var body: some View {
            // A paused track ticks slowly rather than 10x a second: the bar isn't
            // moving, so there is nothing to redraw. (Both branches have to be the
            // same schedule *type*, so this is a long period rather than `.everyMinute`.)
            TimelineView(.periodic(from: .now, by: progress.isPlaying ? 0.1 : 60)) { timeline in
                let now = timeline.date
                VStack(spacing: 2) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                            Capsule()
                                .fill(Color.white.opacity(0.75))
                                .frame(width: proxy.size.width * progress.fraction(at: now))
                        }
                    }
                    .frame(height: Self.barHeight)

                    if showsLabels {
                        HStack {
                            Text(Self.timestamp(progress.elapsed(at: now)))
                            Spacer(minLength: 4)
                            Text(Self.timestamp(progress.duration - progress.elapsed(at: now)))
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        // Digits of differing widths would make the labels twitch every
                        // second as the numbers change.
                        .monospacedDigit()
                    }
                }
            }
        }

        private static func timestamp(_ seconds: TimeInterval) -> String {
            let total = Int(max(0, seconds.rounded()))
            return String(format: "%d:%02d", total / 60, total % 60)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing playing")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Text("Play something in Music or Spotify")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
