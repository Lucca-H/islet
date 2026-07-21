import SwiftUI
import Combine

/// The tabs shown in the expanded notch.
enum NotchTab: String, CaseIterable, Identifiable {
    case nowPlaying
    case shelf
    case clipboard
    case quickNote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .shelf:      return "Shelf"
        case .clipboard:  return "Clipboard"
        case .quickNote:  return "Quick Note"
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .shelf:      return "tray.full"
        case .clipboard:  return "doc.on.clipboard"
        case .quickNote:  return "note.text"
        }
    }
}

/// A brief, low-key indicator shown by momentarily widening the collapsed pill —
/// distinct from a full expand, so background events don't feel intrusive.
enum NotchPeek: Equatable {
    case nowPlaying(title: String, artist: String)
    case fileAdded(name: String)
    case copied(preview: String)

    var symbol: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .fileAdded:  return "tray.and.arrow.down.fill"
        case .copied:     return "doc.on.clipboard.fill"
        }
    }

    var text: String {
        switch self {
        case let .nowPlaying(title, artist): return artist.isEmpty ? title : "\(title) — \(artist)"
        case let .fileAdded(name): return "Added \(name)"
        case let .copied(preview): return preview
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
    let audioVisualizer: AudioVisualizerEngine
    let quickNote: QuickNoteManager

    @Published var isExpanded = false
    @Published var isHovering = false
    @Published var isDropTargeted = false
    @Published var selectedTab: NotchTab = .nowPlaying
    @Published private(set) var peek: NotchPeek?

    private var cancellables = Set<AnyCancellable>()
    private var closeWorkItem: DispatchWorkItem?
    private var peekWorkItem: DispatchWorkItem?

    init(settings: SettingsStore,
         nowPlaying: NowPlayingManager,
         shelf: DropShelfManager,
         clipboard: ClipboardManager,
         audioVisualizer: AudioVisualizerEngine,
         quickNote: QuickNoteManager) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.shelf = shelf
        self.clipboard = clipboard
        self.audioVisualizer = audioVisualizer
        self.quickNote = quickNote

        // Re-publish nested manager changes so SwiftUI updates.
        for object in [settings, nowPlaying, shelf, clipboard, audioVisualizer, quickNote] as [any ObservableObject] {
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
            case .quickNote:  return settings.quickNoteEnabled
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

    /// A click landed outside the open notch: collapse right away rather than
    /// waiting out the hover close delay, which reads as lag when the user has
    /// clearly moved on. A drag hovering the shelf still wins.
    func clickedOutside() {
        guard isExpanded, !isDropTargeted else { return }
        closeWorkItem?.cancel()
        isHovering = false
        close()
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

    // MARK: Peek (subtle live activity)

    /// Briefly widen the collapsed pill to show a low-key indicator. No-ops while
    /// the notch is already expanded or actively hovered, so it never interrupts
    /// something the user is looking at.
    func showPeek(_ kind: NotchPeek, duration: TimeInterval = 2.0) {
        guard !isExpanded, !isHovering else { return }
        peekWorkItem?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            peek = kind
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.peek = nil
            }
        }
        peekWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
