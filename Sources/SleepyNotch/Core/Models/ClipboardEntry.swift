import Foundation

/// Something that was copied, kept for the history: its full content (not
/// the one-line preview the "Copied" peek shows).
struct ClipboardEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case text(String)
        case link(URL)
        case files([URL])
    }

    let id = UUID()
    let kind: Kind
    let copiedAt: Date

    /// The same thing copied again.
    func sameContent(as other: ClipboardEntry) -> Bool {
        kind == other.kind
    }

    /// One line to show in a list.
    var title: String {
        switch kind {
        case .text(let text):
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return String(line.trimmingCharacters(in: .whitespaces).prefix(120))
        case .link(let url):
            return url.absoluteString
        case .files(let urls):
            guard let first = urls.first else { return "Files" }
            return urls.count == 1 ? first.lastPathComponent : "\(first.lastPathComponent) and \(urls.count - 1) more"
        }
    }

    /// The glyph for its kind.
    var symbol: String {
        switch kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .files: return "doc.fill"
        }
    }

    /// How much memory it counts for, in characters, for the history's cap.
    var weight: Int {
        switch kind {
        case .text(let text): return text.count
        case .link(let url): return url.absoluteString.count
        case .files(let urls): return urls.reduce(0) { $0 + $1.path.count }
        }
    }
}
