import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusItem: StatusItemController?
    private var labMenu: FeatureLabMenu?
    private var signalSources: [DispatchSourceSignal] = []

    /// Quitting from the shell (kill, Ctrl-C) takes the same road as Quit, so
    /// a sleep timer's fade is undone first. Only a hard kill (SIGKILL) can't be.
    private func handleQuitSignals() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    /// A sleep timer's fade must not outlive the app with the volume down.
    func applicationWillTerminate(_ notification: Notification) {
        environment?.timers.cancelForQuit()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleQuitSignals()
        let environment = AppEnvironment()
        environment.wiring.start()
        environment.activities.start(
            playback: environment.playback,
            status: environment.status,
            timers: environment.timers,
            downloads: environment.downloads,
            agents: environment.agents,
            power: environment.power,
            preferences: environment.preferences
        )
        environment.welcome.start()
        // Both only show while Settings makes this a regular app (and the
        // icon in the About panel).
        NSApp.applicationIconImage = AppIcon.make()
        NSApp.mainMenu = MainMenu.make(
            settingsTarget: environment.settings,
            settingsAction: #selector(SettingsWindowController.show)
        )

        let statusItem = StatusItemController(
            playback: environment.playback,
            window: environment.window,
            settings: environment.settings,
            timers: environment.timers
        )

        let labMenu = FeatureLabMenu(
            wiring: environment.wiring,
            welcome: environment.welcome,
            lockScreen: environment.lockScreen
        )
        statusItem.addSubmenu(titled: "🧪 Feature Lab", labMenu.menu)
        self.labMenu = labMenu

        self.environment = environment
        self.statusItem = statusItem
    }
}
