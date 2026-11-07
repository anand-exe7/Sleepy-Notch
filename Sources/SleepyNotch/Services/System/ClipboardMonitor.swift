import AppKit

/// Notices when something is copied, for the "Copied" peek.
///
/// macOS sends no notification when the clipboard changes, so this is the
/// one place that polls: it reads the clipboard's change counter — a single
/// integer, not the contents — twice a second, with a generous timer
/// tolerance so the system can batch it with other work.
///
/// It polls only while someone is around: from any activity (the pointer
/// moving, a click or scroll, switching app) until `activeWindow` seconds
/// after the last one. Then a one-shot timer stops it, and nothing at all
/// runs until the next activity, which wakes it with an immediate check, so
/// a copy made while it slept is still noticed. It also stops entirely while
/// nobody can see the notch. The contents are only read after a change.
///
/// Anything a password manager marks as concealed or transient is skipped,
/// for the peek and the history alike.
///
/// The same detection feeds both: the "Copied" peek (`onCopy`) and the
/// clipboard history (`onEntry`). There is only this one timer.
@MainActor
final class ClipboardMonitor {
    var onCopy: ((ClipboardPreview) -> Void)?
    /// The full content of what was copied, for the history.
    var onEntry: ((ClipboardEntry) -> Void)?

    /// How long after the last activity it keeps polling.
    static let activeWindow: TimeInterval = 30

    private let pasteboard = NSPasteboard.general
    private var lastChange = NSPasteboard.general.changeCount
    /// Something wants the clipboard watched (a switch is on, notch visible).
    private var enabled = false
    private var timer: Timer?
    private var idleTimer: Timer?
    private var lastActivity = Date.distantPast
    private var appSwitchObserver: NSObjectProtocol?

    init() {}

    func setActive(_ active: Bool) {
        guard active != enabled else { return }
        enabled = active
        if active {
            // Whatever was copied while it was off is old news.
            lastChange = pasteboard.changeCount
            appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.noteActivity() }
            }
            noteActivity()
        } else {
            if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
            appSwitchObserver = nil
            stopPolling()
        }
    }

    /// The user did something (moved the pointer, clicked, scrolled, switched
    /// app). Called for every pointer event, so while polling it is only a
    /// timestamp.
    func noteActivity() {
        guard enabled else { return }
        lastActivity = Date()
        guard timer == nil else { return }
        // Waking from rest: look right away, then keep watching.
        check()
        // Added to the main run loop, so it fires on the main thread.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        armIdleTimer(after: Self.activeWindow)
    }

    /// One shot, set for when the quiet period would end. If there was
    /// activity since, it sets itself again for what's left; otherwise it
    /// stops the polling.
    private func armIdleTimer(after delay: TimeInterval) {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let remaining = Self.activeWindow - Date().timeIntervalSince(self.lastActivity)
                if remaining > 0.5 {
                    self.armIdleTimer(after: remaining)
                } else {
                    self.stopPolling()
                }
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stopPolling() {
        if timer != nil { check() }
        timer?.invalidate()
        timer = nil
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func check() {
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        lastChange = change
        if let preview = Self.preview(of: pasteboard) {
            onCopy?(preview)
        }
        if let entry = Self.entry(of: pasteboard) {
            onEntry?(entry)
        }
    }

    /// Our own write (copying a history entry back) isn't a new copy.
    func skipCurrentChange() {
        lastChange = pasteboard.changeCount
    }

    // MARK: - Reading

    /// Markers password managers and other apps put on clipboard contents
    /// that shouldn't be shown or kept (see nspasteboard.org).
    private static let privateTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
    ]

    /// The full content for the history: text, a link or files (not images).
    /// Nothing a password manager marked private.
    static func entry(of pasteboard: NSPasteboard) -> ClipboardEntry? {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard !types.isEmpty, types.isDisjoint(with: privateTypes) else { return nil }
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !files.isEmpty {
            return ClipboardEntry(kind: .files(files), copiedAt: Date())
        }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        if let url = link(text) { return ClipboardEntry(kind: .link(url), copiedAt: Date()) }
        return ClipboardEntry(kind: .text(text), copiedAt: Date())
    }

    static func preview(of pasteboard: NSPasteboard) -> ClipboardPreview? {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard !types.isEmpty, types.isDisjoint(with: privateTypes) else { return nil }

        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !files.isEmpty {
            return ClipboardPreview(kind: .files(files))
        }

        let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImage = types.contains(NSPasteboard.PasteboardType.tiff.rawValue)
            || types.contains(NSPasteboard.PasteboardType.png.rawValue)
        let link = text.flatMap(Self.link)

        // A copied web image often brings its address along as text.
        if hasImage, text == nil || link != nil, let image = NSImage(pasteboard: pasteboard) {
            return ClipboardPreview(kind: .image(image))
        }
        if let link {
            return ClipboardPreview(kind: .link(link))
        }
        if let text, !text.isEmpty {
            let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return ClipboardPreview(kind: .text(String(firstLine.prefix(140))))
        }
        return nil
    }

    private static func link(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }
}
