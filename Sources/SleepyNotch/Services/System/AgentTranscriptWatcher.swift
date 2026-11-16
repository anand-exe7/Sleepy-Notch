import Foundation

/// What the agent's transcript said since the last look.
struct TranscriptUpdate: Equatable {
    /// The user stopped the turn (Esc): the agent sends no Stop event for
    /// that, only this line in its transcript.
    var interrupted = false
    /// A tool answered (a permission granted or refused, a command run):
    /// the agent is busy again.
    var toolAnswered = false
    /// What it's doing now, from its last tool call ("Editing NotchView.swift").
    var action: AgentAction?
}

/// One step the agent is taking, in a few words and an SF Symbol.
struct AgentAction: Equatable {
    let text: String
    let symbol: String
}

/// Follows one agent session's transcript (a JSON-lines file the agent
/// appends to) while the session is active, so the notch can tell that the
/// user stopped it, that it's running again after a permission prompt, and
/// what it's doing right now.
///
/// Event-driven: a dispatch source on the file wakes only when it's written;
/// bursts are coalesced into one read every 0.3 s at most. Only the bytes
/// added since the last read are read, off the main thread, and only the
/// user and assistant lines are decoded (the file also holds large request
/// records that are skipped by a prefix check).
final class AgentTranscriptWatcher {
    private let path: String
    private let onUpdate: (TranscriptUpdate) -> Void
    private let queue = DispatchQueue(label: "SleepyNotch.agent-transcript", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var handle: FileHandle?
    private var offset: UInt64 = 0
    private var partial = Data()
    private var pending = false

    /// Lines bigger than this are never decoded: they're request records,
    /// not conversation.
    private static let maxLine = 512 * 1024

    init?(path: String, onUpdate: @escaping (TranscriptUpdate) -> Void) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        self.path = path
        self.handle = handle
        self.onUpdate = onUpdate
        // Only what's written from now on matters.
        offset = (try? handle.seekToEnd()) ?? 0
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: handle.fileDescriptor,
            eventMask: [.write, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.schedule() }
        source.resume()
        self.source = source
    }

    deinit { stop() }

    func stop() {
        source?.cancel()
        source = nil
        try? handle?.close()
        handle = nil
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.pending = false
            self.readNew()
        }
    }

    private func readNew() {
        guard let handle else { return }
        do {
            try handle.seek(toOffset: offset)
        } catch { return }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)
        partial.append(data)
        var update = TranscriptUpdate()
        while let newline = partial.firstIndex(of: 0x0A) {
            let line = partial[partial.startIndex..<newline]
            partial.removeSubrange(partial.startIndex...newline)
            Self.read(line, into: &update)
        }
        // A runaway line with no end yet: drop what can never be decoded.
        if partial.count > Self.maxLine { partial.removeAll() }
        guard update != TranscriptUpdate() else { return }
        DispatchQueue.main.async { [onUpdate] in onUpdate(update) }
    }

    // MARK: - Decoding

    private static let userPrefix = Data(#""type":"user""#.utf8)
    private static let assistantPrefix = Data(#""type":"assistant""#.utf8)

    private static func read(_ line: Data, into update: inout TranscriptUpdate) {
        guard line.count < maxLine else { return }
        // Cheap test before decoding: the record's type sits within its
        // first few kilobytes (after ids and metadata), then confirmed.
        let head = line.prefix(8 * 1024)
        guard head.range(of: userPrefix) != nil || head.range(of: assistantPrefix) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return }
        let type = object["type"] as? String
        let isUser = type == "user"
        let isAssistant = type == "assistant"
        guard isUser || isAssistant,
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]]
        else { return }
        for item in content {
            switch item["type"] as? String {
            case "text" where isUser:
                if let text = item["text"] as? String, text.hasPrefix("[Request interrupted by user") {
                    update.interrupted = true
                    update.action = nil
                }
            case "tool_result" where isUser:
                update.toolAnswered = true
                update.interrupted = false
            case "tool_use" where isAssistant:
                update.action = action(name: item["name"] as? String ?? "", input: item["input"] as? [String: Any] ?? [:])
                update.interrupted = false
            case "text" where isAssistant:
                update.action = AgentAction(text: "Writing a reply", symbol: "text.bubble")
            case "thinking" where isAssistant:
                update.action = AgentAction(text: "Thinking", symbol: "brain")
            default:
                break
            }
        }
    }

    /// A tool call in a few words.
    static func action(name: String, input: [String: Any]) -> AgentAction {
        let file = (input["file_path"] as? String ?? input["notebook_path"] as? String)
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        switch name {
        case "Edit", "MultiEdit", "NotebookEdit":
            return AgentAction(text: "Editing \(file ?? "a file")", symbol: "pencil")
        case "Write":
            return AgentAction(text: "Writing \(file ?? "a file")", symbol: "doc.badge.plus")
        case "Read":
            return AgentAction(text: "Reading \(file ?? "a file")", symbol: "doc.text")
        case "Bash":
            let what = (input["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (input["command"] as? String).map { String($0.prefix(48)) }
                ?? "a command"
            return AgentAction(text: what, symbol: "terminal")
        case "Grep", "Glob":
            return AgentAction(text: "Searching the code", symbol: "magnifyingglass")
        case "WebFetch", "WebSearch":
            return AgentAction(text: "Searching the web", symbol: "globe")
        case "Task", "Agent":
            return AgentAction(text: "Running a helper agent", symbol: "person.2")
        case "TodoWrite":
            return AgentAction(text: "Planning", symbol: "checklist")
        default:
            let short = name.hasPrefix("mcp__") ? (name.split(separator: "_").last.map(String.init) ?? name) : name
            return AgentAction(text: "Using \(short)", symbol: "wrench.and.screwdriver")
        }
    }
}
