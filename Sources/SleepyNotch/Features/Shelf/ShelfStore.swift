import Foundation

/// A file waiting on the shelf. The shelf holds a link to the original, not
/// a copy, so it costs no disk space.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    var name: String { url.lastPathComponent }
}

/// Files dropped on the notch. Kept in memory only, so the shelf clears
/// when the app quits or the shelf is turned off.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    init() {}

    func add(_ urls: [URL]) {
        for url in urls.map(\.standardizedFileURL) where !items.contains(where: { $0.url == url }) {
            items.append(ShelfItem(url: url))
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }

    /// Drops files that were deleted or moved since they were shelved, so
    /// the shelf never offers something that can't be opened.
    func removeMissingFiles() {
        let fileManager = FileManager.default
        items.removeAll { !fileManager.fileExists(atPath: $0.url.path) }
    }
}
