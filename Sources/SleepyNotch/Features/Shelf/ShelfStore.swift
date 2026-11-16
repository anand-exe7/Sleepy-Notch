import AppKit

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
    /// A transform (zip, convert, combine, compress) is running.
    @Published var isWorking = false
    /// Says how a transform went; set by the app, which shows it under the notch.
    var notify: ((String) -> Void)?

    init() {}

    func add(_ urls: [URL]) {
        for url in urls.map(\.standardizedFileURL) where !items.contains(where: { $0.url == url }) {
            items.append(ShelfItem(url: url))
        }
    }

    /// Adds the files on the clipboard (copied in Finder with Cmd-C).
    /// Returns how many were added.
    @discardableResult
    func pasteFromClipboard() -> Int {
        let before = items.count
        add(Self.clipboardFiles())
        return items.count - before
    }

    /// Whether the clipboard holds files right now: read when asked (the
    /// page appearing, the menu opening), nothing is watched.
    static func clipboardHasFiles() -> Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private static func clipboardFiles() -> [URL] {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Puts files on the clipboard as Finder does, so Cmd-V in Finder
    /// copies them there and Mail or Slack attaches them.
    func copyToClipboard(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0.url as NSURL })
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
