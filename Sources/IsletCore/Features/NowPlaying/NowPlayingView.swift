import SwiftUI

/// Expanded Now Playing panel: artwork, track metadata, and transport controls.
struct NowPlayingView: View {
    @EnvironmentObject var vm: NotchViewModel

    private var info: NowPlayingInfo? { vm.nowPlaying.info }

    var body: some View {
        if let info {
            HStack(spacing: 16) {
                artwork
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if let icon = vm.nowPlaying.sourceIcon {
                            Image(nsImage: icon).resizable().frame(width: 11, height: 11)
                        }
                        Text(info.sourceName.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                            .tracking(1.2)
                    }

                    Text(info.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .tracking(-0.2)
                        .lineLimit(1)
                    Text(info.artist)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    HStack(spacing: 16) {
                        transportButton("backward.fill") { vm.nowPlaying.previousTrack() }
                        transportButton(info.isPlaying ? "pause.fill" : "play.fill", size: 20) {
                            vm.nowPlaying.togglePlayPause()
                        }
                        transportButton("forward.fill") { vm.nowPlaying.nextTrack() }
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = vm.nowPlaying.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.white.opacity(0.4)))
        }
    }

    private func transportButton(_ symbol: String, size: CGFloat = 14, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size + 14, height: size + 14)
        }
        .buttonStyle(.glass)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list").font(.system(size: 26)).foregroundStyle(.white.opacity(0.35))
            Text("Nothing playing")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Text("Play something in Music, Spotify, or your browser")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
