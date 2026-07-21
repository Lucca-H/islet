import SwiftUI

/// The expanded panel: a tab strip pinned under the notch and the selected feature.
struct ExpandedNotchView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 34)
                .padding(.top, 2)

            Divider().overlay(Color.white.opacity(0.06))

            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .help("Islet Settings")
        }
        .padding(.horizontal, 6)
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                Text(tab.title).font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // Deliberately *not* a nested GlassEffectView: NSGlassEffectView only
            // guarantees its own contentView, and nesting one inside the panel's
            // glass makes the parent effect drop out when the selection moves.
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.18 : 0))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0.22 : 0), lineWidth: 0.5)
                    )
            }
            .foregroundStyle(.white.opacity(isSelected ? 1 : 0.55))
        }
        .buttonStyle(.plain)
    }
}
