import AppKit
import Combine
import UniformTypeIdentifiers
import os

/// A single file held on the drop shelf.
struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let addedAt: Date

    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }
}

/// A temporary "shelf" you can drag files onto and later drag back out —
/// a scratch space that lives between the notch and Finder.
@MainActor
final class DropShelfManager: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    /// Fires each time a file is successfully added to the shelf.
    let itemAdded = PassthroughSubject<ShelfItem, Never>()

    private let log = Logger(subsystem: "com.dynamicisland.islet", category: "DropShelf")
    private let shelfDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        shelfDir = support.appendingPathComponent("Islet/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: shelfDir, withIntermediateDirectories: true)
        reload()
    }

    /// Load any files left on disk from a previous session.
    private func reload() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: shelfDir,
            includingPropertiesForKeys: [.addedToDirectoryDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        items = contents
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                return ShelfItem(id: UUID(), url: url, addedAt: date)
            }
            .sorted { $0.addedAt > $1.addedAt }
    }

    /// Accept dropped item providers (from `.onDrop`). Returns true if anything was taken.
    func accept(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] data, _ in
                guard
                    let data = data as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                Task { @MainActor in self?.copyIntoShelf(url) }
            }
        }
        return accepted
    }

    /// Copy an external file into the shelf directory, de-duplicating the name.
    private func copyIntoShelf(_ source: URL) {
        let destination = uniqueDestination(for: source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            let item = ShelfItem(id: UUID(), url: destination, addedAt: Date())
            items.insert(item, at: 0)
            itemAdded.send(item)
        } catch {
            log.error("Could not add \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func uniqueDestination(for filename: String) -> URL {
        var candidate = shelfDir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var index = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = shelfDir.appendingPathComponent(newName)
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    func remove(_ item: ShelfItem) {
        try? FileManager.default.removeItem(at: item.url)
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        for item in items { try? FileManager.default.removeItem(at: item.url) }
        items.removeAll()
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }
}
