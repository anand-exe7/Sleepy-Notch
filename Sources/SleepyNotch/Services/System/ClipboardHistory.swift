import AppKit

/// What was copied lately, to copy again from the notch.
///
/// Kept in memory only: nothing is written to disk, and it is gone when the
/// app quits. Capped by count and by total size, so it can never grow into a
/// problem; a copy that a password manager marked concealed never gets here
/// (see `ClipboardMonitor`).
///
/// It adds no timer: entries arrive from `ClipboardMonitor`'s own change
/// detection.
@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    /// The entry just copied back, for a moment's checkmark.
    @Published private(set) var justCopied: UUID?

    static let maxEntries = 50
    /// Total characters kept across all entries.
    static let maxWeight = 200_000
    /// Longest text kept for one entry; a bigger one isn't history.
    static let maxTextLength = 20_000

    /// Called after our own write to the pasteboard, so the monitor doesn't
    /// take it for a new copy.
    var onOwnWrite: (() -> Void)?

    private var flash: DispatchWorkItem?

    func add(_ entry: ClipboardEntry) {
        if case .text(let text) = entry.kind, text.count > Self.maxTextLength { return }
        var next = entries
        // Copying the same thing again moves it to the top.
        next.removeAll { $0.sameContent(as: entry) }
        next.insert(entry, at: 0)
        while next.count > Self.maxEntries || (next.count > 1 && next.reduce(0, { $0 + $1.weight }) > Self.maxWeight) {
            next.removeLast()
        }
        entries = next
    }

    /// Puts an entry back on the clipboard.
    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.kind {
        case .text(let text): pasteboard.setString(text, forType: .string)
        case .link(let url):
            pasteboard.setString(url.absoluteString, forType: .string)
            pasteboard.writeObjects([url as NSURL])
        case .files(let urls): pasteboard.writeObjects(urls as [NSURL])
        }
        onOwnWrite?()
        justCopied = entry.id
        flash?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.justCopied = nil }
        flash = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        entries = []
        justCopied = nil
    }
}
