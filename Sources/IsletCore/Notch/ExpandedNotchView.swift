import SwiftUI

/// The expanded panel: a tab strip pinned under the notch and the selected feature.
struct ExpandedNotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore

    /// Inset for the sides and the top of the content area.
    ///
    /// Not `private` so the Now Playing layout guard can measure the same width the
    /// view actually gets — widening this eats directly into the space the art,
    /// metadata and visualizer columns compete for.
    static let contentInset: CGFloat = 22

    /// The bottom edge gets its own, deliberately tighter value.
    ///
    /// Every tab ends in a footer row (item count / last-edited text on the left, a
    /// button on the right), and at the shared inset that row read as floating too far
    /// above the panel's bottom edge. An earlier attempt went the wrong way entirely —
    /// it *added* clearance for the rounded corners, making the float worse. 10pt
    /// still clears the corner curve comfortably: at 10pt up from the bottom, a
    /// 22pt-radius corner has pulled the edge in by only ~3.6pt, well short of the
    /// footer button's side inset.
    static let bottomInset: CGFloat = 10

    static let headerHeight: CGFloat = 34
    static let headerTopPadding: CGFloat = 4
    /// `Divider()` renders as a hairline.
    static let dividerHeight: CGFloat = 1

    /// Height the selected tab's content actually receives, given the whole panel.
    static func contentHeight(panelHeight: CGFloat) -> CGFloat {
        panelHeight - headerHeight - headerTopPadding - dividerHeight - contentInset - bottomInset
    }

    /// Width the selected tab's content actually receives.
    static func contentWidth(panelWidth: CGFloat) -> CGFloat {
        panelWidth - contentInset * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Self.headerHeight)
                .padding(.horizontal, Self.contentInset)
                .padding(.top, Self.headerTopPadding)

            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.horizontal, Self.contentInset * 0.75)

            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Self.contentInset)
                .padding(.top, Self.contentInset)
                .padding(.bottom, Self.bottomInset)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(vm.enabledTabs) { tab in
                TabChip(tab: tab, isSelected: vm.selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) { vm.selectedTab = tab }
                }
            }
            Spacer()
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.outline(diameter: 30))
            .help("Islet Settings")
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch vm.selectedTab {
        case .nowPlaying:
            NowPlayingView().environmentObject(vm)
        case .shelf:
            DropShelfView().environmentObject(vm)
        case .clipboard:
            ClipboardView().environmentObject(vm)
        case .quickNote:
            QuickNoteView().environmentObject(vm)
        }
    }
}

private struct TabChip: View {
    let tab: NotchTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                Text(tab.title).font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            // Deliberately *not* a nested GlassEffectView: NSGlassEffectView only
            // guarantees its own contentView, and nesting one inside the panel's
            // glass makes the parent effect drop out when the selection moves.
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.18 : (isHovering ? 0.09 : 0)))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0.22 : 0), lineWidth: 0.5)
                    )
            }
            .foregroundStyle(.white.opacity(isSelected ? 1 : (isHovering ? 0.8 : 0.55)))
            // The whole chip — padding included — is the click target, rather than
            // just the glyph and label.
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
