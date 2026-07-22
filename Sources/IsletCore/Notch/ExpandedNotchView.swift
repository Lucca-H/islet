import SwiftUI

/// The expanded panel: a tab strip pinned under the notch and the selected feature.
struct ExpandedNotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore

    /// One inset on every side, so the black margin reads as even all around.
    ///
    /// A previous version gave the bottom edge extra padding on a theory that the
    /// panel's rounded corners needed more clearance there — backwards. The actual
    /// feedback was that the footer floated too far *above* the bottom edge, and
    /// the corner-clearance version made exactly that worse (16pt → ~26pt at the
    /// default corner radius). Uniform 16pt on every side, as originally asked for.
    private static let contentInset: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 34)
                .padding(.horizontal, Self.contentInset)
                .padding(.top, 4)

            Divider()
                .overlay(Color.white.opacity(0.06))
                .padding(.horizontal, Self.contentInset * 0.75)

            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Self.contentInset)
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
