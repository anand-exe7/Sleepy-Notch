import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusItem: StatusItemController?
    #if DEBUG
    private var labMenu: FeatureLabMenu?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        environment.wiring.start()

        let statusItem = StatusItemController(
            playback: environment.playback,
            window: environment.window,
            settings: environment.settings
        )

        #if DEBUG
        let labMenu = FeatureLabMenu(wiring: environment.wiring)
        statusItem.addSubmenu(titled: "🧪 Feature Lab", labMenu.menu)
        self.labMenu = labMenu
        #endif

        self.environment = environment
        self.statusItem = statusItem
    }
}
