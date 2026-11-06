import AppKit

/// The menu bar icon and its menu: show or hide the HUD, demo mode, playback
/// shortcuts, and the way to fix Automation access.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let playback: PlaybackCoordinator
    private let window: NotchWindowController
    private let settings: SettingsWindowController
    private let timers: TimerService
    private var automationItem: NSMenuItem?

    init(
        playback: PlaybackCoordinator,
        window: NotchWindowController,
        settings: SettingsWindowController,
        timers: TimerService
    ) {
        self.playback = playback
        self.window = window
        self.settings = settings
        self.timers = timers
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform.badge.magnifyingglass",
            accessibilityDescription: "Sleepy Notch"
        ) ?? NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "Sleepy Notch"
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

        let timerItem = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu(title: "Timer")
        for minutes in [1, 5, 10, 25, 45, 60] {
            let item = NSMenuItem(title: "\(minutes) minute\(minutes == 1 ? "" : "s")", action: #selector(startTimer(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            timerMenu.addItem(item)
        }
        timerMenu.addItem(.separator())
        let cancel = NSMenuItem(title: "Cancel Timer", action: #selector(cancelTimer), keyEquivalent: "")
        cancel.target = self
        timerMenu.addItem(cancel)
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)
        menu.addItem(.separator())

        addItem("Settings…", #selector(openSettings), key: ",")
        // Automation access is required to control Music/Spotify at all. When
        // it's denied, this is the discoverable way to fix it — the HUD itself
        // only shows a small badge while expanded.
        automationItem = addItem("Automation Access…", #selector(openAutomationSettings), key: "")
        menu.addItem(.separator())

        addItem("Quit Sleepy Notch", #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        timers.start(minutes: Double(sender.tag))
    }

    @objc private func cancelTimer() {
        timers.cancel()
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
        SystemSettings.openAutomation()
    }

    @objc private func openSettings() {
        settings.show()
    }
}
