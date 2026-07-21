import Foundation
import Combine

/// A single persistent scratchpad note — the same idea as macOS's own Quick Note,
/// but living in the notch: always there, no note-management UI, just somewhere to
/// jot something down and have it survive.
@MainActor
final class QuickNoteManager: ObservableObject {
    @Published var text: String {
        didSet {
            guard text != oldValue else { return }
            scheduleSave()
        }
    }

    /// Last-edited timestamp, so the view can show a lightweight "edited just now"
    /// style hint without the manager needing to know anything about formatting.
    @Published private(set) var lastEditedAt: Date?

    private let defaults: UserDefaults
    private var saveWorkItem: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        text = defaults.string(forKey: "quickNoteText") ?? ""
        if let interval = defaults.object(forKey: "quickNoteLastEditedAt") as? Double, interval > 0 {
            lastEditedAt = Date(timeIntervalSince1970: interval)
        }
    }

    func clear() {
        text = ""
    }

    private func scheduleSave() {
        lastEditedAt = Date()
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        // Debounced: avoids hammering UserDefaults on every keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func save() {
        defaults.set(text, forKey: "quickNoteText")
        defaults.set(lastEditedAt?.timeIntervalSince1970 ?? 0, forKey: "quickNoteLastEditedAt")
    }
}
