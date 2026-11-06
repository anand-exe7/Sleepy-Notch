import Foundation

enum AgentState: Int, Equatable, Comparable {
    case done = 0
    case working = 1
    case needsInput = 2

    static func < (a: AgentState, b: AgentState) -> Bool { a.rawValue < b.rawValue }
}

struct AgentSession: Equatable, Identifiable {
    let id: String
    var project: String
    var state: AgentState
    var updatedAt: Date
}

/// What the notch shows for all agent sessions together.
struct AgentSummary: Equatable {
    var state: AgentState
    var sessions: [AgentSession]

    /// The session that decides the headline: the most recent one in the
    /// state that wins.
    var lead: AgentSession? {
        sessions.filter { $0.state == state }.max { $0.updatedAt < $1.updatedAt }
    }
}

/// What a notice under the notch says.
struct AgentNotice: Equatable {
    var state: AgentState
    var project: String
}

/// Turns hook events into session states, and keeps them tidy with one-shot
/// timers only: a finished session fades after a while, and a session that
/// stopped reporting (the agent was killed) is dropped.
@MainActor
final class AgentStatusService: ObservableObject {
    @Published private(set) var summary: AgentSummary?

    /// A session just needed input or finished.
    var onNotice: ((AgentNotice) -> Void)?

    private var sessions: [String: AgentSession] = [:]
    private var expiries: [String: DispatchWorkItem] = [:]
    private let server: AgentSocketServer
    private(set) var isActive = false

    /// How long "done" stays after the agent stops.
    static let doneLinger: TimeInterval = 25
    /// How long a working session may go quiet before it's dropped.
    static let silenceLimit: TimeInterval = 15 * 60

    init(socketPath: String) {
        server = AgentSocketServer(path: socketPath)
        server.onEvent = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    /// Listens while `active` (the Settings switch).
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        if active {
            isActive = server.start()
        } else {
            isActive = false
            server.stop()
            for work in expiries.values { work.cancel() }
            expiries = [:]
            sessions = [:]
            publish()
        }
    }

    // MARK: - Events

    func handle(_ event: [String: Any]) {
        guard let name = event["hook_event_name"] as? String else { return }
        let id = (event["session_id"] as? String).map { String($0.prefix(64)) } ?? "default"
        let project = Self.project(from: event["cwd"] as? String) ?? sessions[id]?.project ?? "Agent"

        switch name {
        case "UserPromptSubmit":
            set(id, project, .working)
        case "Notification":
            set(id, project, .needsInput, notify: true)
        case "Stop":
            set(id, project, .done, notify: true)
        case "SessionEnd":
            remove(id)
        case "SessionStart":
            // Waiting for the first prompt: nothing to show yet.
            break
        default:
            break
        }
    }

    private static func project(from cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? nil : String(name.prefix(40))
    }

    private func set(_ id: String, _ project: String, _ state: AgentState, notify: Bool = false) {
        let changed = sessions[id]?.state != state
        sessions[id] = AgentSession(id: id, project: project, state: state, updatedAt: Date())
        expire(id, after: state == .done ? Self.doneLinger : Self.silenceLimit)
        publish()
        if notify && changed { onNotice?(AgentNotice(state: state, project: project)) }
    }

    private func remove(_ id: String) {
        expiries[id]?.cancel()
        expiries[id] = nil
        guard sessions.removeValue(forKey: id) != nil else { return }
        publish()
    }

    /// One one-shot per session, replaced by each new event.
    private func expire(_ id: String, after delay: TimeInterval) {
        expiries[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.remove(id) }
        expiries[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func publish() {
        guard let top = sessions.values.map(\.state).max() else {
            if summary != nil { summary = nil }
            return
        }
        let next = AgentSummary(state: top, sessions: sessions.values.sorted { $0.updatedAt > $1.updatedAt })
        if next != summary { summary = next }
    }

    // MARK: - Trying it without an agent

    func simulate(_ state: AgentState, project: String = "sleepy-notch") {
        set("simulated", project, state, notify: true)
    }

    func clearSimulated() {
        remove("simulated")
    }
}
