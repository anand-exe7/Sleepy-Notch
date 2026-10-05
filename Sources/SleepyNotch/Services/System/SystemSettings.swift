import AppKit

/// Deep links into System Settings.
enum SystemSettings {
    /// Privacy & Security › Automation, where a denied permission to control
    /// Music or Spotify is granted. A no-op without an app bundle (plain
    /// `swift run`), but harmless.
    @MainActor
    static func openAutomation() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
