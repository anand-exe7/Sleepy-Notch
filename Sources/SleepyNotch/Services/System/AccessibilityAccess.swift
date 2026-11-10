import AppKit
import ApplicationServices

/// Whether the app may use macOS Accessibility, which three opt-in features
/// need: seeing what's in the menu bar next to the notch, noticing a screen
/// recording, and taking over the volume and brightness keys.
///
/// Event-driven: macOS announces a change in who is trusted with a
/// distributed notification, and the answer is also read again whenever the
/// app is brought forward (after the user came back from System Settings).
@MainActor
final class AccessibilityAccess: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var observers: [NSObjectProtocol] = []

    init() {
        let recheck: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        observers = [
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main,
                using: recheck
            ),
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main,
                using: recheck
            ),
        ]
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// Asks macOS to show its Accessibility prompt (once; after that the
    /// user has to use System Settings).
    func request() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
