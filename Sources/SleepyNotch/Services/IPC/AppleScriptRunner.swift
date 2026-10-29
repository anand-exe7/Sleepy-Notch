import Foundation

/// Why an AppleScript execution failed. The raw `NSDictionary` that
/// `NSAppleScript` hands back is parsed into these cases so callers never have
/// to guess what a failure meant.
enum AppleScriptFailure: Error, Equatable {
    /// -1743 `errAEEventNotPermitted` — the user has not granted this app
    /// Automation access, or revoked it in System Settings.
    case automationDenied

    /// -600 `procNotFound` — the target music app isn't running.
    case appNotRunning(String)

    /// -1712 `errAETimeout` — the app didn't answer within
    /// `AppleScriptRunner.timeout`, usually because it's busy or showing a
    /// dialog.
    case noResponse

    /// Anything else, preserving the AppleScript error number and message.
    case scriptError(number: Int, message: String)

    /// Whether the fix is in System Settings › Automation, so the warning
    /// badge only offers to open it when that would help.
    var isFixedInSystemSettings: Bool {
        self == .automationDenied
    }

    /// One-line, user-facing summary. Shown in the expanded player card.
    var shortDescription: String {
        switch self {
        case .automationDenied:
            return "macOS denied automation access."
        case .appNotRunning(let name):
            return "\(name) isn't running."
        case .noResponse:
            return "The music app didn't respond."
        case .scriptError(_, let message):
            return message
        }
    }

    /// Longer text for the tooltip on the failure badge.
    var helpText: String {
        switch self {
        case .automationDenied:
            return "Sleepy Notch can't control your music app until you allow it under System Settings › Privacy & Security › Automation. Click to open that pane."
        case .appNotRunning(let name):
            return "\(name) isn't running, so the last command had no effect. Open it and try again."
        case .noResponse:
            return "The music app took too long to answer, so the last command may not have gone through. It may be busy or showing a dialog."
        case .scriptError(let number, let message):
            return "AppleScript error \(number): \(message)"
        }
    }
}

/// Outcome of a successful script run. Deliberately carries only `Sendable`
/// payloads rather than `NSAppleEventDescriptor` so nothing crosses the
/// isolation boundary from the background queue.
struct AppleScriptResult: Sendable {
    let text: String?
    let data: Data?

    static let empty = AppleScriptResult(text: nil, data: nil)
}

/// Executes AppleScript on a background queue and reports real errors.
///
/// The project rule is that `executeAndReturnError` must never run on
/// `@MainActor`, because a single call blocks the UI thread for as long as the
/// target app takes to answer — often enough to drop frames or beachball.
struct AppleScriptRunner: Sendable {
    static let shared = AppleScriptRunner()

    /// How long to wait for the app to answer. Apple events wait two
    /// minutes by default, and every script shares one queue, so without
    /// this one frozen app would hold up every command behind it that long.
    static let timeout = 6

    private static let queue = DispatchQueue(
        label: "com.anandexe7.sleepy-notch.applescript",
        qos: .userInitiated
    )

    /// Runs `source` off the main thread. Throws `AppleScriptFailure` on error.
    func run(_ source: String) async throws -> AppleScriptResult {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                // autoreleasepool: without it, the AppleScript objects allocated
                // on this queue accumulate with no run loop to drain them.
                let outcome: Result<AppleScriptResult, AppleScriptFailure> = autoreleasepool {
                    var errorInfo: NSDictionary?
                    let bounded = "with timeout of \(Self.timeout) seconds\n\(source)\nend timeout"
                    guard let script = NSAppleScript(source: bounded) else {
                        return .failure(.scriptError(
                            number: -1,
                            message: "Could not compile the playback script."
                        ))
                    }
                    let descriptor = script.executeAndReturnError(&errorInfo)
                    if let errorInfo {
                        return .failure(Self.failure(from: errorInfo))
                    }
                    return .success(AppleScriptResult(
                        text: descriptor.stringValue,
                        data: descriptor.data
                    ))
                }
                continuation.resume(with: outcome)
            }
        }
    }

    private static func failure(from info: NSDictionary) -> AppleScriptFailure {
        // The SDK renamed the error-dict keys; `NSAppleScript.errorNumber` is
        // the current spelling of the old `NSAppleScriptErrorNumber` constant.
        let number = (info[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
        let message = (info[NSAppleScript.errorMessage] as? String)
            ?? "The music app returned an unknown error."

        switch number {
        case -1743:
            return .automationDenied
        case -600:
            return .appNotRunning(message)
        case -1712:
            return .noResponse
        default:
            return .scriptError(number: number, message: message)
        }
    }
}
