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

    /// How the peek pill grows, per `SettingsStore.peekDirection`.
    ///
    /// **Down** grows past the notch band so its row of text is never behind the
    /// camera housing — the same reason the expanded panel insets its content. On
    /// notchless displays `contentTopInset` is 0, so the pill stays compact.
    ///
    /// **Left** / **Right** pin the pill's opposite edge and extend sideways into the
    /// menu-bar strip beside the notch. Those are real, displayable pixels, so they
    /// need no vertical growth at all and stay exactly as tall as the collapsed pill.
    private var peekSize: CGSize {
        // Sized to the text actually being shown rather than a fixed amount of
        // growth: a short "Copied an image" opened exactly as far as a long song
        // title did, which read as the notch overshooting for no reason. Long titles
        // hit the cap in `peekWidth` and truncate.
        let content = vm.peek.map(PeekMetrics.contentWidth(for:)) ?? collapsedSize.width
        let width = geometry.peekWidth(forContentWidth: content,
                                       direction: settings.peekDirection,
                                       expandedWidth: CGFloat(settings.expandedWidth))
        if settings.peekDirection.isLateral {
            return CGSize(width: width, height: collapsedSize.height)
        }
        return CGSize(width: width,
                      height: geometry.contentTopInset + geometry.notchHeight
                              + CGFloat(settings.closedHeightBoost))
    }

    /// Only a sideways peek is off-center; every other state is centered on the notch.
    private var horizontalOffset: CGFloat {
        guard visualState == .peek else { return 0 }
        return geometry.lateralPeekShift(peekWidth: peekSize.width)
            * settings.peekDirection.lateralSign
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
            // The click-to-toggle target lives on the background layer, not on the
            // whole notch body. When it was on the container it competed with the
            // tab chips for hit-testing, which made switching tabs feel sluggish and
            // occasionally drop a click. Buttons consume their own taps, so putting
            // the gesture underneath them leaves both working.
            shape.fill(Color.black)
                .opacity(blackOpacity)
                .contentShape(shape)
                .onTapGesture { vm.clicked() }

            if settings.notchMaterial == .liquidGlass {
                shape
                    .fill(Color.clear)
                    .glassPanel(cornerRadius: CGFloat(settings.cornerRadius),
                               tint: Color(white: 0.55, opacity: 0.22))
                    .clipShape(shape)
                    .opacity(vm.isExpanded ? 1 : 0)
                    .allowsHitTesting(false) // purely decorative
            }

            shape.stroke(Color.white.opacity(0.1), lineWidth: 1)
                .allowsHitTesting(false)

            content
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .clipShape(shape)
        .offset(x: horizontalOffset)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(visualState == .expanded ? 0.45 : 0),
                radius: visualState == .expanded ? 24 : 0, x: 0, y: 12)
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
                // Down: the pill grew below the band, so drop the row past it.
                // Sideways: the pill never left the band, so instead keep the row
                // clear of the cutout at the pinned end — the growth is all on the
                // other side, which is where the text goes.
                let lateral = settings.peekDirection.isLateral
                let growsLeft = settings.peekDirection == .left
                PeekContentView(peek: peek,
                                alignment: !lateral ? .leading : (growsLeft ? .trailing : .leading))
                    .padding(.top, lateral ? 0 : geometry.contentTopInset)
                    .padding(.leading, lateral && !growsLeft ? geometry.peekLateralDeadWidth : 0)
                    .padding(.trailing, lateral && growsLeft ? geometry.peekLateralDeadWidth : 0)
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
                // 1.2x requested — container and bar-height formula (in AudioBars)
                // scaled together so bars stay proportional to their box instead of
                // just clipping against an unchanged frame.
                AudioBars()
                    // Width comes from the bars themselves rather than a literal, so
                    // changing the bar count or thickness can't leave the container
                    // stretching or squashing them.
                    .frame(width: AudioBars.width, height: notchSize.height * 0.42 * 1.2)
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

/// Layout constants for the peek row, shared by the view that draws it and the
/// measurement that sizes the pill around it. Keeping them in one place is what makes
/// "open as wide as the text needs" trustworthy — measuring with a different font or
/// padding than is drawn shows up as either a clipped word or a stray gap.
enum PeekMetrics {
    static let horizontalPadding: CGFloat = 14
    static let iconSpacing: CGFloat = 8
    static let fontSize: CGFloat = 12
    static let tracking: CGFloat = 0.1
    /// SF Symbols at this weight are near enough to square; measuring each glyph for
    /// a couple of points of accuracy isn't worth the per-peek cost.
    static let iconWidth: CGFloat = 15
    /// A little slack so text that measures to almost exactly the available width
    /// isn't truncated by a rounding difference between measurement and layout.
    static let slack: CGFloat = 6

    /// Matches `PeekContentView`'s `.system(size:weight:design:)`.
    static let textFont: NSFont = {
        let base = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: fontSize) else { return base }
        return rounded
    }()

    /// Total width the peek row wants: icon, spacing, the text at its natural width,
    /// and the padding either side.
    static func contentWidth(for peek: NotchPeek) -> CGFloat {
        let text = peek.text as NSString
        let measured = text.size(withAttributes: [.font: textFont]).width
        return iconWidth + iconSpacing + measured
            + tracking * CGFloat(text.length)
            + horizontalPadding * 2 + slack
    }
}

/// The subtle live-activity peek: a small icon and a single line of text,
/// vertically centered in the momentarily widened pill.
private struct PeekContentView: View {
    let peek: NotchPeek
    /// `.leading` for a downward peek (the row owns the full widened pill);
    /// `.trailing` for a leftward one, so the row hugs the notch and the text
    /// trails off toward the free space on the left.
    var alignment: Alignment = .leading

    var body: some View {
        HStack(spacing: PeekMetrics.iconSpacing) {
            Image(systemName: peek.symbol)
                .font(.system(size: PeekMetrics.fontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: PeekMetrics.iconWidth)
            Text(peek.text)
                .font(.system(size: PeekMetrics.fontSize, weight: .medium, design: .rounded))
                .tracking(PeekMetrics.tracking)
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, PeekMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: alignment)
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

    /// The pill is narrow, so the full spectrum is downsampled to something legible at
    /// that size. The circular visualizer uses all of it.
    private static let compactBandCount = 6
    /// Matches the 1.2x applied to this view's container frame — kept as one factor
    /// here rather than baked into the base/amplitude constants individually, so the
    /// two stay obviously in sync if either changes again.
    private static let scale: CGFloat = 1.2

    /// Bars are an explicit width rather than sharing out the container's.
    ///
    /// Left to divide a fixed frame between them they got *fatter* as the bar count
    /// went up or the pill widened, which is backwards — a spectrum reads as finer
    /// detail, not chunkier blocks. Sizing the bars first and deriving `width` from
    /// them keeps the ticks thin at any count.
    ///
    /// There's a floor on how thin this can go before the shape changes character: a
    /// bar's corner radius is half its width, so thinning the bar thins its rounding in
    /// proportion. At 2pt the caps are a 1pt radius and the bars read as plain sticks.
    /// 2.5 is the compromise — clearly slimmer than the ~3.1pt they were when
    /// stretching to fill the frame, while the rounded ends still register.
    static let barWidth: CGFloat = 2.5
    /// Kept just under the bar width. Spacing wider than the bars themselves reads as
    /// separate ticks that happen to sit near each other rather than as one meter,
    /// which is what made the gaps stand out more than the bars did.
    static let barSpacing: CGFloat = 2

    /// Keeps even a silent bar tall enough to be a full rounded dot rather than a
    /// clipped sliver — below `barWidth` a bar can't complete its own end caps.
    static var minimumBarHeight: CGFloat { barWidth }
    static var width: CGFloat {
        barWidth * CGFloat(compactBandCount) + barSpacing * CGFloat(compactBandCount - 1)
    }

    /// All six bars are drawn in **one `Canvas`**, for the same reason the circular
    /// visualizer is.
    ///
    /// As an `HStack` of `Capsule`s each bar was a separate layer, and each layer's
    /// frame gets snapped to the backing pixel grid on its own. With a 4.5pt stride
    /// that snapping alternated — every other bar absorbed the rounding differently, so
    /// its caps rasterized fully while its neighbour's flattened, and the row read as
    /// alternately rounded and squared. Whole-point sizes don't fix it, because a
    /// scaled Retina mode doesn't put whole points on whole pixels either. Drawing
    /// every bar into one canvas removes the per-layer snapping entirely: identical
    /// geometry, one rasterization, uniform caps.
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let levels = barLevels(at: timeline.date.timeIntervalSinceReferenceDate)
            Canvas { context, size in
                for (index, height) in levels.enumerated() {
                    let x = CGFloat(index) * (Self.barWidth + Self.barSpacing)
                    let rect = CGRect(x: x,
                                      y: (size.height - height) / 2,
                                      width: Self.barWidth,
                                      height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: Self.barWidth / 2),
                                 with: .color(.white))
                }
            }
        }
    }

    /// Bar heights for this frame: real spectrum levels when capturing, the idle wave
    /// otherwise. Both go through the same renderer so the two states can't drift.
    private func barLevels(at time: TimeInterval) -> [CGFloat] {
        guard vm.audioVisualizer.isCapturing else {
            return (0..<Self.compactBandCount).map { fakeBarHeight(index: $0, time: time) }
        }
        return vm.audioVisualizer.compactBars(count: Self.compactBandCount).map {
            max(Self.minimumBarHeight, (3 + $0 * 13) * Self.scale)
        }
    }

    private func fakeBarHeight(index: Int, time: TimeInterval) -> CGFloat {
        let speed = 3.2
        let offset = Double(index) * 1.1
        let v = (sin(time * speed + offset) + 1) / 2 // 0...1
        return max(Self.minimumBarHeight, (3 + CGFloat(v) * 10) * Self.scale)
    }
}
