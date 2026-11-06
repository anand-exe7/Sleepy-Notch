import Foundation

/// What the downloads in progress add up to, for the live activity.
struct DownloadSummary: Equatable {
    var count: Int
    /// How far along, 0...1, when the apps say; nil when none of them do.
    var fraction: Double?
    /// The first download's name, without the browser's "in progress" suffix.
    var name: String
}

/// Watches the Downloads folder for downloads in progress, and tells the
/// notch how far along they are.
///
/// Event-driven all the way down. The folder is watched with a file-system
/// event source, so nothing runs until a file appears or goes. How far along
/// a download is comes from the apps themselves: Safari, Chrome and others
/// publish their progress for the file (the progress Finder shows), and
/// `Progress.addSubscriber` calls back as it changes. An app that doesn't
/// publish gets a download with no percentage, and a "finished" notice when
/// its file is renamed. There is no timer and no polling of file sizes.
@MainActor
final class DownloadsMonitor: ObservableObject {
    @Published private(set) var summary: DownloadSummary?

    /// Called with the name of a download that just finished.
    var onFinish: ((String) -> Void)?
    /// The folder to watch. Set before `setActive(true)`.
    var directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

    private struct Item {
        var fraction: Double?
        var subscription: Any?
        var observation: NSKeyValueObservation?
    }

    /// What browsers call a file that is still arriving.
    private static let partialExtensions: Set<String> = ["crdownload", "download", "part", "opdownload"]

    private var items: [String: Item] = [:]
    private var source: DispatchSourceFileSystemObject?
    private var rescan: DispatchWorkItem?
    private(set) var isActive = false

    /// Watches while `active` (Settings on, notch visible); stops and forgets
    /// everything otherwise.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { startWatching() } else { stopWatching() }
    }

    // MARK: - Watching

    private func startWatching() {
        let descriptor = open(directory.path, O_EVTONLY)
        // No access to the folder (macOS asks the first time): the feature
        // simply stays quiet.
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        scan()
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
        rescan?.cancel()
        for item in items.values {
            if let subscription = item.subscription { Progress.removeSubscriber(subscription) }
        }
        items = [:]
        summary = nil
    }

    /// A download writes a burst of changes; one look after they settle.
    private func scheduleScan() {
        rescan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        rescan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func scan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let partial = Set(names.filter { Self.partialExtensions.contains(($0 as NSString).pathExtension.lowercased()) })

        for name in partial where items[name] == nil {
            begin(name)
        }
        for name in items.keys where !partial.contains(name) {
            end(name)
        }
        publish()
    }

    private func begin(_ name: String) {
        var item = Item()
        let url = directory.appendingPathComponent(name)
        item.subscription = Progress.addSubscriber(forFileURL: url) { [weak self] progress in
            let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                let fraction = progress.isIndeterminate ? nil : progress.fractionCompleted
                Task { @MainActor [weak self] in self?.update(name, fraction) }
            }
            Task { @MainActor [weak self] in self?.items[name]?.observation = observation }
            return {}
        }
        items[name] = item
    }

    private func update(_ name: String, _ fraction: Double?) {
        guard items[name] != nil else { return }
        // Whole steps of 5%: an app reports many times a second, and every
        // change redraws the notch, so only a visible step gets through.
        let stepped = fraction.map { (min(1, max(0, $0)) * 20).rounded() / 20 }
        guard items[name]?.fraction != stepped else { return }
        items[name]?.fraction = stepped
        publish()
    }

    private func end(_ name: String) {
        guard let item = items.removeValue(forKey: name) else { return }
        if let subscription = item.subscription { Progress.removeSubscriber(subscription) }
        // Renamed to its real name means it finished; just gone, cancelled.
        let finished = (name as NSString).deletingPathExtension
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(finished).path) {
            onFinish?(finished)
        }
    }

    private func publish() {
        guard let first = items.keys.sorted().first else {
            if summary != nil { summary = nil }
            return
        }
        let known = items.values.compactMap(\.fraction)
        let next = DownloadSummary(
            count: items.count,
            fraction: known.isEmpty ? nil : known.reduce(0, +) / Double(known.count),
            name: (first as NSString).deletingPathExtension
        )
        if next != summary { summary = next }
    }

    // MARK: - Trying it without a download

    /// A made-up download for the Feature Lab.
    func simulate(name: String, fraction: Double?) {
        summary = DownloadSummary(count: 1, fraction: fraction, name: name)
    }

    func clearSimulated() {
        summary = nil
    }
}
