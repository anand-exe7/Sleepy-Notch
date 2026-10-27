import AppKit
import SwiftUI

/// The Settings window, kept around once opened so bringing it back doesn't
/// rebuild the view hierarchy. Shaped like System Settings: the sidebar runs
/// up under the traffic lights and the pane's name sits in a unified toolbar.
@MainActor
final class SettingsWindowController {
    private let preferences: HUDPreferences
    private let playback: PlaybackCoordinator
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(preferences: HUDPreferences, playback: PlaybackCoordinator) {
        self.preferences = preferences
        self.playback = playback
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(
            preferences: preferences,
            playback: playback,
            navigation: navigation
        ))
        // Let SwiftUI put the pane's title in the window's toolbar.
        if #available(macOS 14.0, *) {
            hosting.sceneBridgingOptions = [.title, .toolbars]
        }

        let window = NSWindow(contentViewController: hosting)
        window.title = "Sleepy Notch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.toolbar = NSToolbar(identifier: "SleepyNotchSettings")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SleepyNotchSettings")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
