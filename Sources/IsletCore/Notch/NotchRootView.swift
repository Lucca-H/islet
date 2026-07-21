import SwiftUI

/// The visible notch surface: a black rounded shape that morphs between a compact
/// collapsed pill and a full expanded panel with tabs.
struct NotchRootView: View {
    let geometry: NotchGeometry

    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore

    private var collapsedSize: CGSize {
        CGSize(width: geometry.notchWidth,
               height: geometry.notchHeight + CGFloat(settings.closedHeightBoost))
    }

    private var expandedSize: CGSize {
        CGSize(width: CGFloat(settings.expandedWidth),
               height: geometry.notchHeight + CGFloat(settings.expandedHeight))
    }

    private var currentSize: CGSize {
        vm.isExpanded ? expandedSize : collapsedSize
    }

    var body: some View {
        VStack(spacing: 0) {
            notchBody
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var notchBody: some View {
        ZStack(alignment: .top) {
            NotchShape(bottomRadius: CGFloat(settings.cornerRadius),
                       topRadius: vm.isExpanded ? 12 : 8)
                .fill(Color.black)
                .overlay(
                    NotchShape(bottomRadius: CGFloat(settings.cornerRadius),
                               topRadius: vm.isExpanded ? 12 : 8)
                        .stroke(Color.white.opacity(vm.isExpanded ? 0.08 : 0), lineWidth: 1)
                )

            content
                .frame(width: currentSize.width, height: currentSize.height)
                .clipped()
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .contentShape(NotchShape(bottomRadius: CGFloat(settings.cornerRadius),
                                 topRadius: vm.isExpanded ? 12 : 8))
        .shadow(color: .black.opacity(vm.isExpanded ? 0.45 : 0),
                radius: vm.isExpanded ? 24 : 0, x: 0, y: 12)
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
    }

    private var dropBinding: Binding<Bool> {
        Binding(get: { vm.isDropTargeted },
                set: { vm.dropTargetChanged($0) })
    }

    @ViewBuilder
    private var content: some View {
        if vm.isExpanded {
            ExpandedNotchView()
                .environmentObject(vm)
                .environmentObject(settings)
                .transition(.opacity)
        } else {
            CollapsedNotchView(notchSize: collapsedSize)
                .environmentObject(vm)
                .environmentObject(settings)
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

/// A small animated equalizer used as the "audio is playing" indicator.
struct AudioBars: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(Color.white)
                        .frame(height: barHeight(index: i, time: t))
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let speed = 3.2
        let offset = Double(index) * 1.1
        let v = (sin(time * speed + offset) + 1) / 2 // 0...1
        return 3 + CGFloat(v) * 10
    }
}
