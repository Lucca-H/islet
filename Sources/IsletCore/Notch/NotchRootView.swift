import SwiftUI

/// The visible notch surface. Collapsed, the brief widened "peek", and expanded
/// all render the **same material** — set once in Settings (`NotchMaterial`,
/// Liquid Glass or Solid) — so nothing about the surface's color or transparency
/// changes when it resizes. Only the geometry (`NotchShape`'s size and corner
/// radius) animates.
///
/// Two earlier attempts got this wrong:
/// - A structural `if/else` swapped between a solid fill (collapsed) and a
///   completely different glass view tree (expanded). SwiftUI can't animate
///   across two different view identities, so the glass tint popped in instantly.
/// - Layering a permanent glass view on top of a permanent *opaque* black fill.
///   `NSGlassEffectView` refracts whatever is drawn behind it — which was our own
///   opaque black, not the desktop behind the window — so it read as solid black
///   no matter what its own opacity was.
///
/// The fix: pick exactly one material and never layer a second, opaque one under it.
struct NotchRootView: View {
    let geometry: NotchGeometry

    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore

    private enum VisualState { case collapsed, peek, expanded }

    private var visualState: VisualState {
        if vm.isExpanded { return .expanded }
        if vm.peek != nil { return .peek }
        return .collapsed
    }

    private var collapsedSize: CGSize {
        CGSize(width: geometry.collapsedContentWidth,
               height: geometry.notchHeight + CGFloat(settings.closedHeightBoost))
    }

    /// Peek grows *downward* past the notch band so its row of text is never behind
    /// the camera housing — the same reason the expanded panel insets its content.
    /// On notchless displays `contentTopInset` is 0, so the pill stays compact.
    private var peekSize: CGSize {
        let width = min(CGFloat(settings.expandedWidth), collapsedSize.width + 260)
        return CGSize(width: width,
                      height: geometry.contentTopInset + geometry.notchHeight
                              + CGFloat(settings.closedHeightBoost))
    }

    private var expandedSize: CGSize {
        CGSize(width: CGFloat(settings.expandedWidth),
               height: geometry.notchHeight + CGFloat(settings.expandedHeight))
    }

    private var currentSize: CGSize {
        switch visualState {
        case .collapsed: return collapsedSize
        case .peek:       return peekSize
        case .expanded:   return expandedSize
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            notchBody
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Shared silhouette for the base fill, the glass clip, and the stroke overlay —
    /// using one `Shape` value (rather than three separately-constructed ones) keeps
    /// their corner-radius interpolation in lockstep during the expand animation.
    private var shape: NotchShape {
        NotchShape(bottomRadius: CGFloat(settings.cornerRadius), topRadius: vm.isExpanded ? 12 : 8)
    }

    /// The notch always reads as solid black while collapsed or peeking — matching
    /// the physical hardware bezel it sits against — and only reveals Liquid Glass
    /// once actually opened. In Solid mode this stays 1 always.
    private var blackOpacity: Double {
        settings.notchMaterial == .solid || !vm.isExpanded ? 1 : 0
    }

    @ViewBuilder
    private var notchBody: some View {
        ZStack(alignment: .top) {
            // Both layers are always present — never structurally inserted or
            // removed — so only their opacity needs to animate. Fading the black
            // out as the glass fades in (rather than switching between them) is
            // what lets the glass end up genuinely transparent once fully open: a
            // permanently-opaque layer behind it would refract itself, not the
            // desktop, and read as solid regardless of its own opacity.
            shape.fill(Color.black)
                .opacity(blackOpacity)

            if settings.notchMaterial == .liquidGlass {
                shape
                    .fill(Color.clear)
                    .glassPanel(cornerRadius: CGFloat(settings.cornerRadius),
                               tint: Color(white: 0.55, opacity: 0.22))
                    .clipShape(shape)
                    .opacity(vm.isExpanded ? 1 : 0)
            }

            shape.stroke(Color.white.opacity(0.1), lineWidth: 1)

            content
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .clipShape(shape)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(visualState == .expanded ? 0.45 : 0),
                radius: visualState == .expanded ? 24 : 0, x: 0, y: 12)
        .onTapGesture { vm.clicked() }
        .onHover { inside in
            // Backup for the expanded state (window is interactive then).
            if vm.isExpanded { vm.isHovering = inside; if !inside { vm.pointerExited() } }
        }
        .onDrop(of: [.fileURL], isTargeted: dropBinding) { providers in
            vm.selectedTab = .shelf
            return vm.shelf.accept(providers: providers)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.74), value: vm.isExpanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: vm.peek)
    }

    private var dropBinding: Binding<Bool> {
        Binding(get: { vm.isDropTargeted },
                set: { vm.dropTargetChanged($0) })
    }

    @ViewBuilder
    private var content: some View {
        switch visualState {
        case .expanded:
            ExpandedNotchView()
                .environmentObject(vm)
                .environmentObject(settings)
                // Keeps the tab strip (and everything under it) clear of the notch
                // band, which is otherwise dead pixels behind the camera housing.
                .padding(.top, geometry.contentTopInset)
                .frame(width: currentSize.width, height: currentSize.height)
                .clipped()
                .transition(.opacity)
        case .peek:
            if let peek = vm.peek {
                PeekContentView(peek: peek)
                    .padding(.top, geometry.contentTopInset)
                    .frame(width: currentSize.width, height: currentSize.height)
                    .clipped()
                    .transition(.opacity)
            }
        case .collapsed:
            CollapsedNotchView(notchSize: currentSize)
                .environmentObject(vm)
                .environmentObject(settings)
                .frame(width: currentSize.width, height: currentSize.height)
                .clipped()
                .transition(.opacity)
        }
    }
}

/// Compact state: optional album-art peek on the left, a live audio indicator on
/// the right when something is playing.
private struct CollapsedNotchView: View {
    let notchSize: CGSize
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore

    /// Islet tracks Apple Music and Spotify only, so playback state comes purely
    /// from track metadata — no inferring "something is making noise" from raw
    /// audio, which would light up for any browser tab or notification sound.
    private var isPlaying: Bool {
        settings.nowPlayingEnabled && (vm.nowPlaying.info?.isPlaying ?? false)
    }

    var body: some View {
        HStack(spacing: 0) {
            if settings.peekMediaArt, isPlaying {
                artwork
                    .frame(width: notchSize.height * 0.62, height: notchSize.height * 0.62)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(.leading, 10)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if isPlaying {
                AudioBars()
                    .frame(width: 16, height: notchSize.height * 0.42)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: notchSize.width, height: notchSize.height)
        .animation(.easeInOut(duration: 0.25), value: isPlaying)
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = vm.nowPlaying.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.15))
                .overlay(Image(systemName: "music.note").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)))
        }
    }
}

/// The subtle live-activity peek: a small icon and a single line of text,
/// vertically centered in the momentarily widened pill.
private struct PeekContentView: View {
    let peek: NotchPeek

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: peek.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(peek.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .tracking(0.1)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A small animated equalizer used as the "audio is playing" indicator.
///
/// Shows real frequency-band levels from `AudioVisualizerEngine` when it's actually
/// capturing (opt-in, needs Screen Recording permission — see `SettingsStore.
/// audioVisualizerEnabled`). Otherwise falls back to a lively but non-audio-reactive
/// animation, same bar count, so nothing about the layout shifts based on whether
/// the feature is enabled.
struct AudioBars: View {
    @EnvironmentObject var vm: NotchViewModel

    /// The pill is only ~16pt wide, so the full 32-band spectrum is downsampled to
    /// something legible at that size. The circular visualizer uses all of it.
    private static let compactBandCount = 4

    var body: some View {
        Group {
            if vm.audioVisualizer.isCapturing {
                let levels = vm.audioVisualizer.compactBars(count: Self.compactBandCount)
                HStack(spacing: 2) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                        Capsule()
                            .fill(Color.white)
                            .frame(height: 3 + level * 13)
                            .frame(maxHeight: .infinity, alignment: .center)
                            .animation(.easeOut(duration: 0.08), value: level)
                    }
                }
            } else {
                TimelineView(.animation(minimumInterval: 0.12)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 2) {
                        ForEach(0..<Self.compactBandCount, id: \.self) { i in
                            Capsule()
                                .fill(Color.white)
                                .frame(height: fakeBarHeight(index: i, time: t))
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                    }
                }
            }
        }
    }

    private func fakeBarHeight(index: Int, time: TimeInterval) -> CGFloat {
        let speed = 3.2
        let offset = Double(index) * 1.1
        let v = (sin(time * speed + offset) + 1) / 2 // 0...1
        return 3 + CGFloat(v) * 10
    }
}
