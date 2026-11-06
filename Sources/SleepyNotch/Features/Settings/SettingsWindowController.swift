import AppKit
import SwiftUI

/// The Settings window, kept around once opened so bringing it back doesn't
/// rebuild the view hierarchy. Shaped like System Settings: the sidebar runs
/// up under the traffic lights and the pane's name sits in a unified toolbar.
///
/// While it's open the app is a regular app, with a Dock icon and a menu
/// bar. A menu-bar-only app never quite becomes active, so its windows draw
/// in their inactive look — grey traffic lights, a flat sidebar, no accent —
/// and keyboard shortcuts like ⌘W have no menu to go through. Closing the
/// window puts the app back in the menu bar.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: HUDPreferences
    private let playback: PlaybackCoordinator
    private let keyboard: KeyboardMonitor
    private let calendar: CalendarMonitor
    private let accessibility: AccessibilityAccess
    private let weather: WeatherService
    private let glance: CalendarGlance
    private let floating: FloatingPlayerController
    private let clipboardHistory: ClipboardHistory
    private let agentInstaller: AgentHookInstaller
    private let previewWelcome: () -> Void
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(
        preferences: HUDPreferences,
        playback: PlaybackCoordinator,
        keyboard: KeyboardMonitor,
        calendar: CalendarMonitor,
        accessibility: AccessibilityAccess,
        weather: WeatherService,
        glance: CalendarGlance,
        floating: FloatingPlayerController,
        clipboardHistory: ClipboardHistory,
        agentInstaller: AgentHookInstaller,
        previewWelcome: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.playback = playback
        self.keyboard = keyboard
        self.calendar = calendar
        self.accessibility = accessibility
        self.weather = weather
        self.glance = glance
        self.floating = floating
        self.clipboardHistory = clipboardHistory
        self.agentInstaller = agentInstaller
        self.previewWelcome = previewWelcome
    }

    @objc func show() {
        NSApp.setActivationPolicy(.regular)
        let window = self.window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(
            preferences: preferences,
            playback: playback,
            keyboard: keyboard,
            calendar: calendar,
            navigation: navigation,
            accessibility: accessibility,
            weather: weather,
            glance: glance,
            floating: floating,
            clipboardHistory: clipboardHistory,
            agentInstaller: agentInstaller,
            previewWelcome: previewWelcome
        ))
        // Let SwiftUI put the pane's title and the search field in the
        // window's toolbar, and keep the window within the view's limits.
        if #available(macOS 14.0, *) {
            hosting.sceneBridgingOptions = [.title, .toolbars]
        }
        hosting.sizingOptions = [.minSize, .maxSize]

        let window = NSWindow(contentViewController: hosting)
        window.title = "Sleepy Notch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbar = NSToolbar(identifier: "SleepyNotchSettings")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 715, height: 540))
        window.center()
        window.setFrameAutosaveName("SleepyNotchSettings")
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        navigation.query = ""
        // Back to the menu bar. Deferred a turn so the window finishes
        // closing first; otherwise the next app doesn't become active.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
