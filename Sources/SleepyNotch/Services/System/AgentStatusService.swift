import Foundation

enum AgentState: Int, Equatable, Comparable {
    case done = 0
    case working = 1
    case needsInput = 2

    static func < (a: AgentState, b: AgentState) -> Bool { a.rawValue < b.rawValue }
}

/// Which coding agent a session belongs to, for its logo and name.
enum AgentKind: String, Equatable {
    case claude, codex, gemini, cursor, other

    var name: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .cursor: return "Cursor"
        case .other: return "Agent"
        }
    }

    /// From the event: an explicit `agent` field if a hook sends one, else
    /// where the agent keeps its transcripts. The installed hooks are
    /// Claude Code's, so that's the default.
    static func detect(_ event: [String: Any]) -> AgentKind {
        if let named = (event["agent"] as? String)?.lowercased() {
            if named.contains("claude") { return .claude }
            if named.contains("codex") || named.contains("openai") { return .codex }
            if named.contains("gemini") { return .gemini }
            if named.contains("cursor") { return .cursor }
            return .other
        }
        let path = (event["transcript_path"] as? String ?? "").lowercased()
        if path.contains("/.codex/") { return .codex }
        if path.contains("/.gemini/") { return .gemini }
        if path.contains("/.cursor/") { return .cursor }
        return .claude
    }
}

struct AgentSession: Equatable, Identifiable {
    let id: String
    var kind: AgentKind = .claude
    var project: String
    var state: AgentState
    var updatedAt: Date
    /// When the current turn began (the prompt was sent); the clock beside
    /// the notch counts from here.
    var startedAt: Date
    /// What it's working on: the first line of the prompt, shortened.
    var task: String?
    /// Why it needs you, in the agent's own words ("Claude needs your
    /// permission to use Bash").
    var request: String?
    /// How long the last turn took, once it's done.
    var duration: TimeInterval?
    /// What it's doing right now, read from its transcript.
    var action: AgentAction?
    /// The turn's last few tool steps, oldest first (the newest may still
    /// be running).
    var steps: [AgentAction] = []
    /// How much the turn has done so far.
    var edits = 0
    var commands = 0
    var reads = 0
    /// The newest step is still running.
    var toolRunning = false

    /// "4 edits · 2 commands · 3 reads", nil before the first step.
    var stats: String? {
        func part(_ count: Int, _ one: String, _ many: String) -> String? {
            count == 0 ? nil : "\(count) \(count == 1 ? one : many)"
        }
        let parts = [part(edits, "edit", "edits"), part(commands, "command", "commands"), part(reads, "read", "reads")].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    /// The turn ended because the user stopped it, not because it finished.
    var stopped = false

    /// One line under the session's name.
    var subtitle: String {
        switch state {
        case .needsInput:
            return request ?? task ?? "Waiting for you"
        case .done:
            if stopped { return duration.map { "Stopped after \(AgentSession.format($0))" } ?? "Stopped" }
            let took = duration.map { "Finished in \(AgentSession.format($0))" } ?? "Finished"
            return task.map { "\(took) · \($0)" } ?? took
        case .working:
            return action?.text ?? task ?? "Working"
        }
    }

    /// "48s", "3m 12s", "1h 4m".
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \(total % 3600 / 60)m"
    }
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
    var kind: AgentKind = .claude
    var stopped = false
    var project: String
    /// A line to show instead of the usual wording (the playful one when
    /// an agent starts working).
    var message: String?
    /// A second, quieter line: why it needs you, or how long it took.
    var detail: String?
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

    /// How long "done" (or "stopped") stays after the turn ends: its
    /// notice, then the bubble with the check, which then melts back into
    /// the notch and is gone.
    static let doneLinger: TimeInterval = 6
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
            for watcher in watchers.values { watcher.stop() }
            watchers = [:]
            transcripts = [:]
            publish()
        }
    }

    // MARK: - Events

    func handle(_ event: [String: Any]) {
        guard let name = event["hook_event_name"] as? String else { return }
        let id = (event["session_id"] as? String).map { String($0.prefix(64)) } ?? "default"
        let project = Self.project(from: event["cwd"] as? String) ?? sessions[id]?.project ?? "Agent"
        let kind = AgentKind.detect(event)
        if let transcript = event["transcript_path"] as? String { transcripts[id] = transcript }

        switch name {
        case "UserPromptSubmit":
            set(id, project, .working, notify: true, kind: kind, task: Self.firstLine(event["prompt"] as? String, limit: 90))
        case "Notification":
            // A request for the user always comes in the middle of a turn,
            // so the session is working. A notification for a session that
            // is done, or that we have no record of (it faded away), is the
            // agent's reminder that it is idle, not a request: ignoring it
            // stops an orange "needs you" from appearing after the work is
            // finished and then sitting there.
            guard let current = sessions[id]?.state, current != .done else { return }
            set(id, project, .needsInput, notify: true, kind: kind, request: Self.shortRequest(Self.firstLine(event["message"] as? String, limit: 90)))
        case "Stop":
            set(id, project, .done, notify: true, kind: kind)
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

    /// The agent's usual requests, said short enough for one line:
    /// "Claude needs your permission to use Bash" -> "Wants to use Bash".
    private static func shortRequest(_ text: String?) -> String? {
        guard let text else { return nil }
        let lower = text.lowercased()
        if let range = lower.range(of: "needs your permission to use ") {
            return "Wants to use " + text[range.upperBound...]
        }
        if lower.contains("waiting for your input") { return "Waiting for your reply" }
        return text
    }

    /// The first non-empty line, cut to `limit` characters.
    private static func firstLine(_ text: String?, limit: Int) -> String? {
        guard let line = text?
            .split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty })
        else { return nil }
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    private func set(
        _ id: String,
        _ project: String,
        _ state: AgentState,
        notify: Bool = false,
        kind: AgentKind? = nil,
        task: String? = nil,
        request: String? = nil,
        stopped: Bool = false
    ) {
        let old = sessions[id]
        let previous = old?.state
        let changed = previous != state
        let now = Date()
        // A new turn starts the clock and takes the new prompt; needing you
        // or finishing keeps the turn's start and its task.
        let newTurn = state == .working && (previous == nil || previous == .done)
        let started = newTurn ? now : (old?.startedAt ?? now)
        let session = AgentSession(
            id: id,
            kind: kind ?? old?.kind ?? .claude,
            project: project,
            state: state,
            updatedAt: now,
            startedAt: started,
            task: task ?? (newTurn ? nil : old?.task),
            request: state == .needsInput ? (request ?? old?.request) : nil,
            duration: state == .done ? now.timeIntervalSince(started) : nil,
            action: state == .working && !newTurn ? old?.action : nil,
            steps: newTurn ? [] : (old?.steps ?? []),
            edits: newTurn ? 0 : (old?.edits ?? 0),
            commands: newTurn ? 0 : (old?.commands ?? 0),
            reads: newTurn ? 0 : (old?.reads ?? 0),
            stopped: state == .done && stopped
        )
        sessions[id] = session
        // The transcript is followed only while the turn is live.
        if state == .done { stopWatching(id) } else { watch(id) }
        expire(id, after: state == .done ? Self.doneLinger : Self.silenceLimit)
        publish()
        guard notify, changed else { return }
        // "Working" says something only when work begins, not when an
        // agent that needed you goes back to it.
        if state == .working {
            guard previous == nil || previous == .done else { return }
            onNotice?(AgentNotice(state: state, kind: session.kind, project: project, message: Self.banter(avoiding: &lastBanter), detail: session.task))
        } else {
            onNotice?(AgentNotice(state: state, kind: session.kind, stopped: session.stopped, project: project, detail: session.subtitle))
        }
    }

    private var lastBanter: Int?

    /// A short, light line for the moment work starts. Never the same one
    /// twice in a row.
    private static let lines = [
        "Cooking! You can watch reels btw 😎",
        "Let it cook 🍳",
        "Locked in. Go touch grass 🌱",
        "Vibe coding in progress ✨",
        "No cap, this is gonna slap 🔥",
        "Bet. On it 🫡",
        "Main character energy ⚡️",
        "Brb, being a genius 🧠",
        "It's giving productivity 💅",
        "Go grab a snack, bestie 🍿",
        "Say less. Working 🫡",
        "Sit back, I got this 🛋️",
        "Rizzing up your code 😎",
        "Understood the assignment 📝",
    ]

    static func banter(avoiding last: inout Int?) -> String {
        var index = Int.random(in: 0..<lines.count)
        if index == last { index = (index + 1) % lines.count }
        last = index
        return lines[index]
    }

    // MARK: - Transcript

    /// Steps kept per turn for the card's timeline.
    static let keptSteps = 3

    private var transcripts: [String: String] = [:]
    private var watchers: [String: AgentTranscriptWatcher] = [:]

    private func watch(_ id: String) {
        guard watchers[id] == nil, let path = transcripts[id] else { return }
        watchers[id] = AgentTranscriptWatcher(path: path) { [weak self] update in
            MainActor.assumeIsolated { self?.apply(update, to: id) }
        }
    }

    private func stopWatching(_ id: String) {
        watchers[id]?.stop()
        watchers[id] = nil
    }

    /// What the transcript said: you stopped it (it sends no Stop event for
    /// that), it's running again after you answered a prompt, or what it's
    /// doing now.
    private func apply(_ update: TranscriptUpdate, to id: String) {
        guard var session = sessions[id], session.state != .done else { return }
        if update.interrupted {
            set(id, session.project, .done, notify: true, stopped: true)
            return
        }
        if session.state == .needsInput, update.toolAnswered || update.action != nil {
            set(id, session.project, .working)
            session = sessions[id] ?? session
        }
        var changed = false
        for step in update.steps {
            switch step.kind {
            case .edit: session.edits += 1
            case .command: session.commands += 1
            case .read: session.reads += 1
            default: break
            }
            session.steps.append(step)
            changed = true
        }
        if session.steps.count > Self.keptSteps { session.steps.removeFirst(session.steps.count - Self.keptSteps) }
        if let action = update.action, action != session.action {
            session.action = action
            changed = true
        }
        if let running = update.toolRunning, running != session.toolRunning {
            session.toolRunning = running
            changed = true
        }
        guard changed else { return }
        session.updatedAt = Date()
        sessions[id] = session
        publish()
    }

    private func remove(_ id: String) {
        stopWatching(id)
        transcripts[id] = nil
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

    func simulate(_ state: AgentState, project: String = "sleepy-notch", kind: AgentKind = .claude, stopped: Bool = false) {
        set(
            "simulated", project, state, notify: true,
            kind: kind,
            task: state == .working ? "Make the shelf look better and smoother" : nil,
            request: state == .needsInput ? shortRequestForSimulation : nil,
            stopped: stopped
        )
        // A visible step, as the transcript would give.
        if state == .working, var session = sessions["simulated"] {
            session.steps = [
                AgentAction(text: "Read CalendarGlance.swift", symbol: "doc.text", kind: .read),
                AgentAction(text: "Edited DayDetailView.swift", symbol: "pencil", kind: .edit),
                AgentAction(text: "Build the app", symbol: "terminal", kind: .command),
            ]
            session.action = session.steps.last
            session.toolRunning = true
            session.edits = 4
            session.commands = 2
            session.reads = 3
            sessions["simulated"] = session
            publish()
        }
    }

    private var shortRequestForSimulation: String? {
        Self.shortRequest("Claude needs your permission to use Bash")
    }

    func clearSimulated() {
        remove("simulated")
    }
}
