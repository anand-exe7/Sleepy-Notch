import AppKit

/// The quick toggles on the Controls page: Dark Mode and Mute (Stay Awake
/// and Focus are their own services). Each is read when the tab opens, and Dark Mode
/// also follows the system's own notification when it changes, so nothing is
/// polled.
@MainActor
final class ControlsService: ObservableObject {
    @Published private(set) var darkMode = false
    @Published private(set) var muted = false
    /// Says what went wrong, for the notice.
    var onProblem: ((String) -> Void)?

    private var observer: NSObjectProtocol?

    init() {
        darkMode = Self.systemIsDark()
        muted = SystemLevels.isMuted() ?? false
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let dark = Self.systemIsDark()
                if dark != self.darkMode { self.darkMode = dark }
            }
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    nonisolated static func systemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Reads the state that isn't pushed to us: called when the tab opens.
    func refresh() {
        // Only what changed is set, so opening the tab redraws nothing
        // when all is as it was.
        let mute = SystemLevels.isMuted() ?? false
        if mute != muted { muted = mute }
        let dark = Self.systemIsDark()
        if dark != darkMode { darkMode = dark }
    }

    // MARK: - Dark Mode

    func toggleDarkMode() {
        let target = !darkMode
        darkMode = target
        Task {
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(target)"
            do { _ = try await AppleScriptRunner.shared.run(script) } catch {
                darkMode = !target
                onProblem?(error is AppleScriptFailure && (error as? AppleScriptFailure)?.isFixedInSystemSettings == true
                    ? "Allow Sleepy Notch to control System Events in Privacy & Security > Automation"
                    : "Couldn't change the appearance")
            }
        }
    }

    // MARK: - Mute

    func toggleMute() {
        guard SystemLevels.setMuted(!muted) else { return onProblem?("This output can't be muted") ?? () }
        muted.toggle()
    }
}
