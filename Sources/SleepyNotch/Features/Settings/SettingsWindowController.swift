import AppKit
import SwiftUI

/// The Settings window, kept around once opened so bringing it back doesn't
/// rebuild the view hierarchy. Floats above the HUD so you can see your
/// toggles take effect right away.
@MainActor
final class SettingsWindowController {
    private let settings: LabSettings
    private var window: NSWindow?

    init(settings: LabSettings) {
        self.settings = settings
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sleepy Notch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("SleepyNotchSettings")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
