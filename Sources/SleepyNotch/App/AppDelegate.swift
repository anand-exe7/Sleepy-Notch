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
        let statusItem = StatusItemController(playback: environment.playback, window: environment.window)

        #if DEBUG
        // Trial features, in development builds only.
        environment.featureLab.start()
        let labMenu = FeatureLabMenu(featureLab: environment.featureLab)
        statusItem.addSubmenu(titled: "🧪 Feature Lab", labMenu.menu)
        self.labMenu = labMenu
        #endif

        self.environment = environment
        self.statusItem = statusItem
    }
}
