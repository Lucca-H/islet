import SwiftUI

/// The expanded panel: a tab strip pinned under the notch and the selected feature.
struct ExpandedNotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore

    /// One inset used for the header, the content, and the bottom edge, so the black
    /// margin around the panel's contents reads as even on all sides. (Previously the
    /// horizontal inset was split across two modifiers — 10 outer + 14 inner = 24 —
    /// while the vertical inset was only 14, so the surround looked lopsided.)
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
