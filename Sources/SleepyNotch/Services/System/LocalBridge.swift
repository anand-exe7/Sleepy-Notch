import Foundation

/// What a script is allowed to ask the app to do. A fixed list: anything
/// else is dropped.
enum BridgeCommand: Equatable {
    case peek(String)
    case shelfAdd(URL)
    case timer(minutes: Double)
    case timerCancel
}

/// Lets scripts and links talk to the app: a Unix socket for the command-line
/// tool, and the `sleepynotch://` link for anything else.
///
/// Only the user can reach the socket (its folder is 0700, the socket 0600).
/// Only four actions exist, every value is checked and capped, nothing is
/// run or opened, and a command that comes too soon after the last is dropped
/// so a loop can't flood the notch. The link form leaves out `shelf-add`, so
/// a web page can't put files on the shelf.
@MainActor
final class LocalBridge {
    /// Called with each valid command.
    var onCommand: ((BridgeCommand) -> Void)?

    private let server: AgentSocketServer
    private(set) var isRunning = false
    private var lastCommand = Date.distantPast
    private static let minimumGap: TimeInterval = 0.4

    static let maxText = 80
    static let maxMinutes = 12 * 60.0

    init(socketPath: String) {
        server = AgentSocketServer(path: socketPath)
        server.onEvent = { [weak self] event in
            MainActor.assumeIsolated {
                if let command = Self.command(fromSocket: event) { self?.accept(command) }
            }
        }
    }

    static var defaultSocketPath: String {
        NSHomeDirectory() + "/Library/Application Support/Sleepy Notch/bridge.sock"
    }

    /// Listens while `on` (the Settings switch).
    func setRunning(_ on: Bool) {
        guard on != isRunning else { return }
        if on {
            isRunning = server.start()
        } else {
            isRunning = false
            server.stop()
        }
    }

    /// A `sleepynotch://action?...` link.
    func handle(url: URL) {
        guard isRunning, let command = Self.command(fromLink: url) else { return }
        accept(command)
    }

    private func accept(_ command: BridgeCommand) {
        let now = Date()
        guard now.timeIntervalSince(lastCommand) >= Self.minimumGap else { return }
        lastCommand = now
        onCommand?(command)
    }

    // MARK: - Parsing

    static func command(fromSocket event: [String: Any]) -> BridgeCommand? {
        guard let action = event["action"] as? String else { return nil }
        switch action {
        case "peek":
            return (event["text"] as? String).flatMap(cleanText).map(BridgeCommand.peek)
        case "shelf-add":
            return (event["path"] as? String).flatMap(existingFile).map(BridgeCommand.shelfAdd)
        case "timer":
            let minutes = (event["minutes"] as? NSNumber)?.doubleValue
            return minutes.flatMap(validMinutes).map { BridgeCommand.timer(minutes: $0) }
        case "timer-cancel":
            return .timerCancel
        default:
            return nil
        }
    }

    static func command(fromLink url: URL) -> BridgeCommand? {
        guard url.scheme == "sleepynotch", let action = url.host else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch action {
        case "peek":
            return value("text").flatMap(cleanText).map(BridgeCommand.peek)
        case "timer":
            return value("minutes").flatMap(Double.init).flatMap(validMinutes).map { BridgeCommand.timer(minutes: $0) }
        case "timer-cancel":
            return .timerCancel
        default:
            // Including shelf-add: not available from a link.
            return nil
        }
    }

    /// One line, no control characters, capped.
    private static func cleanText(_ text: String) -> String? {
        let line = text.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maxText))
    }

    /// An absolute path to something that exists.
    private static func existingFile(_ path: String) -> URL? {
        guard path.hasPrefix("/"), path.utf8.count < 1024,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func validMinutes(_ minutes: Double) -> Double? {
        guard minutes.isFinite, minutes > 0, minutes <= maxMinutes else { return nil }
        return minutes
    }
}
