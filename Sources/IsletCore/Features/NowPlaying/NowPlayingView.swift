import SwiftUI

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
                // Fills the content height rather than sitting at a fixed size, so
                // the black margin above and below the art equals the panel's own
                // inset instead of being padding + leftover slack.
                let artSize = max(72, proxy.size.height)
                HStack(alignment: .center, spacing: 18) {
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
                        // artSize already equals the row's full available height — a
                        // literal 1.7x here would need to be 70% taller than the row
                        // itself and get clipped. This fills the row completely
                        // (0.92 -> 1.0, its actual ceiling); the requested boldness
                        // otherwise comes from CircularVisualizerView's thicker bars.
                        CircularVisualizerView(
                            levels: vm.audioVisualizer.bars,
                            isLive: vm.audioVisualizer.isCapturing && vm.audioVisualizer.hasSignal,
                            size: artSize
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

            HStack(spacing: 10) {
                transportButton("backward.fill", diameter: 30, glyph: 12) {
                    vm.nowPlaying.previousTrack()
                }
                transportButton(info.isPlaying ? "pause.fill" : "play.fill", diameter: 38, glyph: 15) {
                    vm.nowPlaying.togglePlayPause()
                }
                transportButton("forward.fill", diameter: 30, glyph: 12) {
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
