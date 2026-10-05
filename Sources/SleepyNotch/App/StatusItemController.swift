import AppKit

/// The menu bar icon and its menu: show or hide the HUD, demo mode, playback
/// shortcuts, and the way to fix Automation access.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let playback: PlaybackCoordinator
    private let window: NotchWindowController
    private var automationItem: NSMenuItem?

    init(playback: PlaybackCoordinator, window: NotchWindowController) {
        self.playback = playback
        self.window = window
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform.badge.magnifyingglass",
            accessibilityDescription: "Notch Music"
        ) ?? NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "Notch Music"
        )
        buildMenu()
        statusItem.menu = menu
    }

    /// Adds a submenu just above "Automation Access…". Used for the Feature
    /// Lab in development builds.
    func addSubmenu(titled title: String, _ submenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        let index = automationItem.map { menu.index(of: $0) } ?? menu.numberOfItems
        menu.insertItem(item, at: index)
        menu.insertItem(.separator(), at: index + 1)
    }

    private func buildMenu() {
        addItem("Toggle Notch HUD", #selector(toggleHUD), key: "n")
        addItem("Toggle Demo Mode", #selector(toggleDemo), key: "d")
        menu.addItem(.separator())

        addItem("Play / Pause", #selector(playPause), key: " ")
        addItem("Next Track", #selector(nextTrack), key: "]")
        addItem("Previous Track", #selector(previousTrack), key: "[")
        menu.addItem(.separator())

        // Automation access is required to control Music/Spotify at all. When
        // it's denied, this is the discoverable way to fix it — the HUD itself
        // only shows a small badge while expanded.
        automationItem = addItem("Automation Access…", #selector(openAutomationSettings), key: "")
        menu.addItem(.separator())

        addItem("Quit Notch Music", #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func toggleHUD() {
        window.toggleVisibility()
    }

    @objc private func toggleDemo() {
        playback.toggleDemoMode()
    }

    @objc private func playPause() {
        playback.togglePlayPause()
    }

    @objc private func nextTrack() {
        playback.nextTrack()
    }

    @objc private func previousTrack() {
        playback.previousTrack()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
