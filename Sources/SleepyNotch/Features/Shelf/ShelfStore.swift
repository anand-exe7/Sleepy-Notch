import AppKit

/// A file waiting on the shelf. The shelf holds a link to the original, not
/// a copy, so it costs no disk space (except for an app's temporary files,
/// which it copies so they can't vanish; see `ShelfStore.add`).
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

    init() {
        // Copies kept from a past run (see `keep`) are no longer on any
        // shelf: the shelf lives in memory only.
        let folder = Self.keptFolder
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    func add(_ urls: [URL]) {
        let fresh = urls.map(\.standardizedFileURL).filter { url in !items.contains(where: { $0.url == url }) }
        let temporary = fresh.filter(Self.isTemporary)
        for url in fresh where !Self.isTemporary(url) {
            items.append(ShelfItem(url: url))
        }
        guard !temporary.isEmpty else { return }
        // Off the main thread: a dragged video can take a moment to copy.
        DispatchQueue.global(qos: .userInitiated).async {
            let kept = temporary.map(Self.keep)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for url in kept where !self.items.contains(where: { $0.url == url }) {
                    self.items.append(ShelfItem(url: url))
                }
            }
        }
    }

    // MARK: - Temporary files

    /// Where copies of temporary files are kept while they're on the shelf.
    nonisolated private static var keptFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sleepy Notch/Shelf", isDirectory: true)
    }

    /// A file an app handed over from its temporary folder (a photo dragged
    /// out of WhatsApp or a browser): that app may delete it moments later,
    /// or still be writing it, so the shelf keeps its own copy.
    nonisolated private static func isTemporary(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return path.hasPrefix("/private/var/folders/") || path.hasPrefix("/var/folders/")
            || (path.contains("/Library/Containers/") && path.contains("/tmp/"))
            || path.hasPrefix(NSTemporaryDirectory())
    }

    /// Copies the file into `keptFolder` under its own name (in a folder of
    /// its own, so two "image.jpg" never clash). Falls back to the original
    /// if the copy fails.
    nonisolated private static func keep(_ url: URL) -> URL {
        let folder = keptFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return url
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
