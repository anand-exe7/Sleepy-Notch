import AppKit

/// Deep links into System Settings.
enum SystemSettings {
    /// Privacy & Security › Automation, where a denied permission to control
    /// Music or Spotify is granted. A no-op without an app bundle (plain
    /// `swift run`), but harmless.
    @MainActor
    static func openAutomation() {
        openPrivacy("Privacy_Automation")
    }

    /// Privacy & Security › Calendars, for meeting reminders.
    @MainActor
    static func openCalendars() {
        openPrivacy("Privacy_Calendars")
    }

    @MainActor
    private static func openPrivacy(_ anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
