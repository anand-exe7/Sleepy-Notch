import Foundation

/// A file waiting on the shelf. The shelf holds a link to the original, not
/// a copy, so it costs no disk space.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    var name: String { url.lastPathComponent }
}

/// Files dropped on the notch. In-memory for the Feature Lab demo; it clears
/// when the app quits.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var items: [ShelfItem] = []

    private init() {}

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
}
