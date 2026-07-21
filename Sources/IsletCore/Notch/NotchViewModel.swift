import SwiftUI
import Combine

/// The tabs shown in the expanded notch.
enum NotchTab: String, CaseIterable, Identifiable {
    case nowPlaying
    case shelf
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .shelf:      return "Shelf"
        case .clipboard:  return "Clipboard"
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .shelf:      return "tray.full"
        case .clipboard:  return "doc.on.clipboard"
        }
    }
}

/// Drives a single notch surface: expansion state, the selected tab, and the
/// shared feature managers the views render.
@MainActor
final class NotchViewModel: ObservableObject {
    let settings: SettingsStore
    let nowPlaying: NowPlayingManager
    let shelf: DropShelfManager
    let clipboard: ClipboardManager

    @Published var isExpanded = false
    @Published var isHovering = false
    @Published var isDropTargeted = false
    @Published var selectedTab: NotchTab = .nowPlaying

    private var cancellables = Set<AnyCancellable>()
    private var closeWorkItem: DispatchWorkItem?

    init(settings: SettingsStore,
         nowPlaying: NowPlayingManager,
         shelf: DropShelfManager,
         clipboard: ClipboardManager) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.shelf = shelf
        self.clipboard = clipboard

        // Re-publish nested manager changes so SwiftUI updates.
        for object in [settings, nowPlaying, shelf, clipboard] as [any ObservableObject] {
            (object.objectWillChange as any Publisher as? ObservableObjectPublisher)?
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        // If a tab gets disabled while selected, fall back to the first enabled one.
        settings.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.ensureValidTab() } }
            .store(in: &cancellables)
    }

    var enabledTabs: [NotchTab] {
        NotchTab.allCases.filter { tab in
            switch tab {
            case .nowPlaying: return settings.nowPlayingEnabled
            case .shelf:      return settings.dropShelfEnabled
            case .clipboard:  return settings.clipboardEnabled
            }
        }
    }

    private func ensureValidTab() {
        if !enabledTabs.contains(selectedTab), let first = enabledTabs.first {
            selectedTab = first
        }
    }

    // MARK: Expansion

    func pointerEntered() {
        isHovering = true
        closeWorkItem?.cancel()
        guard settings.expandTrigger == .hover else { return }
        let delay = settings.hoverOpenDelay
        scheduleOpen(after: delay)
    }

    func pointerExited() {
        isHovering = false
        guard !isDropTargeted else { return }
        scheduleClose(after: settings.hoverCloseDelay)
    }

    func clicked() {
        guard settings.expandTrigger == .click else { return }
        if isExpanded { close() } else { open() }
    }

    func dropTargetChanged(_ targeted: Bool) {
        isDropTargeted = targeted
        if targeted {
            closeWorkItem?.cancel()
            selectedTab = .shelf
            open()
        } else if !isHovering {
            scheduleClose(after: settings.hoverCloseDelay)
        }
    }

    private func scheduleOpen(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isHovering else { return }
            self.open()
        }
    }

    private func scheduleClose(after delay: TimeInterval) {
        closeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isHovering, !self.isDropTargeted else { return }
            self.close()
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func open() {
        guard !isExpanded else { return }
        ensureValidTab()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            isExpanded = true
        }
        if settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func close() {
        guard isExpanded else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            isExpanded = false
        }
    }
}
