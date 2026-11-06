import Foundation
import CryptoKit

/// Adds and removes the agent's hooks that report to the notch.
///
/// Opt-in: nothing here runs until the user presses Install in Settings.
/// Each hook is one short command that exits at once when the notch app
/// isn't running (the socket isn't there) and otherwise hands the event to
/// the socket. Install keeps a byte-for-byte copy of the settings file;
/// Uninstall puts that copy back exactly if the file hasn't been touched
/// since, and otherwise removes only our own entries, leaving everything
/// else as it is.
@MainActor
final class AgentHookInstaller: ObservableObject {
    @Published private(set) var isInstalled = false
    /// The last problem or confirmation, for Settings.
    @Published private(set) var status: String?

    /// The agent's settings file (its user-level settings, a JSON object).
    let settingsPath: String
    private let socketPath: String
    private let defaults: UserDefaults

    /// Tags our entries so they can be told from the user's own.
    static let marker = "sleepy-notch-hook"
    /// The events the notch follows.
    static let events = ["UserPromptSubmit", "Notification", "Stop", "SessionEnd"]

    /// Where the agent keeps its user-level settings.
    static var defaultSettingsPath: String {
        NSHomeDirectory() + "/.claude/settings.json"
    }

    /// Where the notch listens: a folder only the user can open.
    static var defaultSocketPath: String {
        NSHomeDirectory() + "/Library/Application Support/Sleepy Notch/agent.sock"
    }

    private static let installedHashKey = "agent.installedSettingsHash"

    init(settingsPath: String, socketPath: String, defaults: UserDefaults = .standard) {
        self.settingsPath = settingsPath
        self.socketPath = socketPath
        self.defaults = defaults
        refresh()
    }

    private var backupPath: String { settingsPath + ".sleepynotch-backup" }

    private var command: String {
        let quoted = "'" + socketPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "[ -S \(quoted) ] && /usr/bin/nc -U -w 1 \(quoted) >/dev/null 2>&1; exit 0 # \(Self.marker)"
    }

    func refresh() {
        let text = (try? String(contentsOfFile: settingsPath, encoding: .utf8)) ?? ""
        isInstalled = text.contains(Self.marker)
    }

    // MARK: - Install

    func install() {
        let original: Data
        var root: [String: Any]
        let existed = FileManager.default.fileExists(atPath: settingsPath)
        if existed {
            guard let data = FileManager.default.contents(atPath: settingsPath) else {
                return fail("Couldn't read the settings file.")
            }
            original = data
            if data.isEmpty {
                root = [:]
            } else if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                root = object
            } else {
                return fail("The settings file isn't valid JSON, so it was left alone.")
            }
        } else {
            original = Data()
            root = [:]
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var added = false
        for event in Self.events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let present = groups.contains { group in
                ((group["hooks"] as? [[String: Any]]) ?? []).contains {
                    (($0["command"] as? String) ?? "").contains(Self.marker)
                }
            }
            if present { continue }
            groups.append(["hooks": [["type": "command", "command": command]]])
            hooks[event] = groups
            added = true
        }
        guard added else { refresh(); return }
        root["hooks"] = hooks

        guard let output = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return fail("Couldn't write the settings.") }

        do {
            // A copy of exactly what was there, kept until Uninstall.
            if existed, !FileManager.default.fileExists(atPath: backupPath) {
                try original.write(to: URL(fileURLWithPath: backupPath), options: .atomic)
            }
            try write(output, over: settingsPath, existed: existed)
        } catch {
            return fail("Couldn't write the settings file: \(error.localizedDescription)")
        }
        defaults.set(Self.hash(output), forKey: Self.installedHashKey)
        status = "Installed. New agent sessions will report to the notch."
        refresh()
    }

    // MARK: - Uninstall

    func uninstall() {
        guard let current = FileManager.default.contents(atPath: settingsPath) else {
            status = nil
            return refresh()
        }
        let untouched = defaults.string(forKey: Self.installedHashKey) == Self.hash(current)
        do {
            if untouched, let backup = FileManager.default.contents(atPath: backupPath) {
                // Nothing else changed the file: put the original back, byte
                // for byte.
                try write(backup, over: settingsPath, existed: true)
            } else if untouched, !FileManager.default.fileExists(atPath: backupPath) {
                // We created the file ourselves: remove it again.
                try FileManager.default.removeItem(atPath: settingsPath)
            } else {
                try removeOurEntries(from: current)
            }
        } catch {
            return fail("Couldn't update the settings file: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(atPath: backupPath)
        defaults.removeObject(forKey: Self.installedHashKey)
        status = "Removed. The settings file is as it was."
        refresh()
    }

    /// The file changed after install: take out only what's ours.
    private func removeOurEntries(from data: Data) throws {
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            var groups = value as? [[String: Any]] ?? []
            groups = groups.compactMap { group in
                var group = group
                let kept = ((group["hooks"] as? [[String: Any]]) ?? []).filter {
                    !((($0["command"] as? String) ?? "").contains(Self.marker))
                }
                guard !kept.isEmpty else { return nil }
                group["hooks"] = kept
                return group
            }
            hooks[event] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        let output = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try write(output, over: settingsPath, existed: true)
    }

    // MARK: - Helpers

    /// Writes `data`, keeping the file's permissions.
    private func write(_ data: Data, over path: String, existed: Bool) throws {
        let permissions = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? NSNumber
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        if let permissions {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
        }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fail(_ message: String) {
        status = message
    }
}
