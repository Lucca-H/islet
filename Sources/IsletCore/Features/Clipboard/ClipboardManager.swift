import AppKit
import Combine

/// One entry in the clipboard history.
struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    let kind: Kind
    let date: Date

    enum Kind: Equatable {
        case text(String)
        case image(NSImage)

        static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case let (.text(a), .text(b)): return a == b
            case let (.image(a), .image(b)): return a.tiffRepresentation == b.tiffRepresentation
            default: return false
            }
        }
    }

    var isText: Bool { if case .text = kind { return true }; return false }

    var textValue: String? {
        if case let .text(value) = kind { return value }
        return nil
    }

    var imageValue: NSImage? {
        if case let .image(value) = kind { return value }
        return nil
    }
}

/// Watches the system pasteboard and keeps a rolling history you can re-copy from.
@MainActor
final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let settings: SettingsStore
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    /// Set while we write to the pasteboard ourselves so we don't re-record it.
    private var suppressNextCapture = false

    init(settings: SettingsStore) {
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.capture() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func capture() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if suppressNextCapture {
            suppressNextCapture = false
            return
        }

        // Skip passwords / transient content when configured to.
        if settings.clipboardIgnoreConcealed, isConcealed() { return }

        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            record(.text(string))
        } else if settings.clipboardStoreImages,
                  let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
                  let image = NSImage(data: data) {
            record(.image(image))
        }
    }

    private func isConcealed() -> Bool {
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let types = pasteboard.types ?? []
        return types.contains(concealed) || types.contains(transient)
    }

    private func record(_ kind: ClipItem.Kind) {
        // De-duplicate: if identical to the newest entry, just bump it.
        if let first = items.first, first.kind == kind { return }
        items.removeAll { $0.kind == kind }
        items.insert(ClipItem(kind: kind, date: Date()), at: 0)
        trim()
    }

    private func trim() {
        let limit = max(1, settings.clipboardLimit)
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
    }

    /// Put an item back on the system pasteboard so the user can paste it.
    func copyToPasteboard(_ item: ClipItem) {
        suppressNextCapture = true
        pasteboard.clearContents()
        switch item.kind {
        case let .text(value):
            pasteboard.setString(value, forType: .string)
        case let .image(image):
            if let tiff = image.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
        lastChangeCount = pasteboard.changeCount
        // Move it to the front of the history.
        items.removeAll { $0.id == item.id }
        items.insert(ClipItem(kind: item.kind, date: Date()), at: 0)
        trim()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }
}
