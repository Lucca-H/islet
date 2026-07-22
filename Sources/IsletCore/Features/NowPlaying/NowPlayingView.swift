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
    /// Visualizer is sized as a fraction of the album art, so the two squares
    /// flanking the metadata column stay visually related.
    static let visualizerRatio: CGFloat = 0.92

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

    /// Fraction of available width the album art may occupy.
    ///
    /// Chosen as the largest value clearing `transportRowMinimum` *plus*
    /// `metadataBreathingRoom` across every Settings size combination. At the 640x210
    /// default it costs the art about 4pt versus letting height bind alone —
    /// imperceptible, and worth it for a guard with actual margin rather than one
    /// sitting exactly on the boundary. Widening the panel insets or growing the
    /// transport buttons will require re-deriving this; the layout check sweeps the
    /// whole slider range and fails loudly if it no longer holds.
    static let artWidthCap: CGFloat = 0.275

    /// Album art (and, at `visualizerRatio`, the visualizer) fills the available
    /// height, capped against width.
    ///
    /// Both are squares driven by height, flanking a metadata column that can't go
    /// below `transportRowMinimum`. Sizing on height alone overflowed at narrow
    /// "Expanded width" settings — at 420x210 the metadata column was left 12pt; at
    /// 420x340 it went negative.
    static func artSize(availableHeight: CGFloat, availableWidth: CGFloat) -> CGFloat {
        max(72, min(availableHeight, availableWidth * artWidthCap))
    }

    /// Width left for the metadata column once both squares and the gaps are taken.
    static func metadataWidth(availableWidth: CGFloat, artSize: CGFloat) -> CGFloat {
        availableWidth - artSize - columnSpacing * 2 - artSize * visualizerRatio
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
                let artSize = NowPlayingLayout.artSize(availableHeight: proxy.size.height,
                                                       availableWidth: proxy.size.width)
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

                    if settings.audioVisualizerEnabled {
                        // "1.7x" was peakGain (how exaggerated the peaks are), not
                        // this container size — reverted to its original proportion.
                        CircularVisualizerView(
                            levels: vm.audioVisualizer.bars,
                            isLive: vm.audioVisualizer.isCapturing && vm.audioVisualizer.hasSignal,
                            size: artSize * NowPlayingLayout.visualizerRatio
                        )
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

            Spacer(minLength: 10)

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
