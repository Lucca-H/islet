import AppKit
import SwiftUI
import Combine

/// Owns one notch surface on one screen: builds the window, positions it over the
/// notch, hosts the SwiftUI content, and translates pointer movement into
/// expand/collapse commands on the view model.
@MainActor
final class NotchController {
    let viewModel: NotchViewModel
    private let geometry: NotchGeometry
    private let window: NotchWindow
    private var cancellables = Set<AnyCancellable>()

    /// Extra breathing room around the interactive content inside the window.
    private let horizontalPadding: CGFloat = 24
    private let bottomPadding: CGFloat = 24

    init(geometry: NotchGeometry, viewModel: NotchViewModel) {
        self.geometry = geometry
        self.viewModel = viewModel

        let frame = Self.windowFrame(for: geometry, settings: viewModel.settings,
                                     horizontalPadding: horizontalPadding, bottomPadding: bottomPadding)
        window = NotchWindow(contentRect: frame)

        let root = NotchRootView(geometry: geometry)
            .environmentObject(viewModel)
            .environmentObject(viewModel.settings)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()

        // Toggle click-through with expansion so buttons work only when open.
        viewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.window.ignoresMouseEvents = !expanded
            }
            .store(in: &cancellables)

        // Reposition/resize when size settings change.
        viewModel.settings.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.relayout() } }
            .store(in: &cancellables)
    }

    /// The window covers the full potential (expanded) footprint, anchored to the
    /// top of the screen and centered on the notch.
    private static func windowFrame(for geometry: NotchGeometry, settings: SettingsStore,
                                    horizontalPadding: CGFloat, bottomPadding: CGFloat) -> NSRect {
        let screen = geometry.screen.frame
        let width = max(CGFloat(settings.expandedWidth), geometry.notchWidth) + horizontalPadding * 2
        let height = geometry.notchHeight + CGFloat(settings.expandedHeight)
            + CGFloat(settings.closedHeightBoost) + bottomPadding
        let x = geometry.notchRect.midX - width / 2
        let y = screen.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func relayout() {
        let frame = Self.windowFrame(for: geometry, settings: viewModel.settings,
                                     horizontalPadding: horizontalPadding, bottomPadding: bottomPadding)
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Pointer regions (screen coordinates)

    /// The area that opens the notch when the pointer enters it while collapsed.
    /// Matches `NotchRootView.collapsedSize` — the visible pill is wider than the
    /// bare notch cutout (see `NotchGeometry.contentSafeMargin`), so the hover
    /// target has to be too, or hovering directly over the now-visible audio bars
    /// or artwork thumbnail wouldn't register.
    var collapsedRegion: CGRect {
        let inset: CGFloat = 4
        return geometry.notchRect
            .insetBy(dx: -(geometry.contentSafeMargin + inset), dy: 0)
    }

    /// The area that keeps the notch open; leaving it collapses the notch.
    var expandedRegion: CGRect {
        let screen = geometry.screen.frame
        let width = max(CGFloat(viewModel.settings.expandedWidth), geometry.notchWidth)
        let height = geometry.notchHeight + CGFloat(viewModel.settings.expandedHeight)
            + CGFloat(viewModel.settings.closedHeightBoost)
        let x = geometry.notchRect.midX - width / 2
        let y = screen.maxY - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Feed a global pointer location (bottom-left origin) into the state machine.
    func handlePointer(at point: CGPoint) {
        // Only react to the screen this controller owns.
        guard geometry.screen.frame.contains(point) || expandedRegion.contains(point) else {
            if viewModel.isHovering { viewModel.pointerExited() }
            return
        }

        if viewModel.isExpanded {
            if !expandedRegion.contains(point) {
                viewModel.pointerExited()
            } else {
                viewModel.isHovering = true
            }
        } else {
            if collapsedRegion.contains(point) {
                viewModel.pointerEntered()
            } else if viewModel.isHovering {
                viewModel.pointerExited()
            }
        }
    }

    /// Feed a global click location (bottom-left origin). Clicks away from an open
    /// notch dismiss it immediately; clicks on it are left to the SwiftUI content.
    func handleClick(at point: CGPoint) {
        guard viewModel.isExpanded, !expandedRegion.contains(point) else { return }
        viewModel.clickedOutside()
    }

    func teardown() {
        cancellables.removeAll()
        window.orderOut(nil)
    }
}
