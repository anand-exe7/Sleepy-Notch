import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var statusItem: StatusItemController?
    private var labMenu: FeatureLabMenu?
    private var signalSources: [DispatchSourceSignal] = []

    /// Quitting from the shell (kill, Ctrl-C) takes the same road as Quit, so
    /// a sleep timer's fade is undone first. Only a hard kill (SIGKILL) can't be.
    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        environment?.bridge.handle(url: url)
    }

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
        // The log stream is a separate process: it must not outlive the app.
        environment?.recording.setRunning(false)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleQuitSignals()
        let environment = AppEnvironment()
        // `sleepynotch://` links (they reach the app once it runs as an .app,
        // since a bare executable can't register a URL scheme).
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        environment.wiring.start()
        environment.activities.start(
            playback: environment.playback,
            status: environment.status,
            timers: environment.timers,
            downloads: environment.downloads,
            agents: environment.agents,
            stayAwake: environment.stayAwake,
            recording: environment.recording,
            crowding: environment.crowding,
            power: environment.power,
            preferences: environment.preferences
        )
        // The first launch opens with the setup; the hello, and calendar's
        // permission prompt, wait until it ends.
        let onboarding = environment.onboarding
        onboarding.onFinish = { [weak environment] in
            guard let environment else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                environment.welcome.preview()
            }
            if environment.preferences.widgets {
                DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak environment] in
                    environment?.calendarGlance.connect()
                }
            }
        }
        let firstLaunch = onboarding.isNeeded
        if firstLaunch {
            onboarding.show()
        } else {
            environment.welcome.start()
        }
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
            timers: environment.timers,
            stayAwake: environment.stayAwake,
            activities: environment.activities,
            floating: environment.floating,
            captureText: { [wiring = environment.wiring] in wiring.captureText() },
            toggleDictation: { [wiring = environment.wiring] in wiring.toggleDictation() },
            dictation: environment.dictation,
            textCaptureEnabled: { [preferences = environment.preferences] in preferences.textCapture },
            speechEnabled: { [preferences = environment.preferences] in preferences.speechToText },
            stayAwakeEnabled: { [preferences = environment.preferences] in preferences.stayAwake }
        )

        // The Feature Lab (simulated notices and activities) is for working
        // on the app: shown in development builds, hidden in releases unless
        // a tester turns it on (see `FeatureLabMenu.isShown`).
        if FeatureLabMenu.isShown {
            let labMenu = FeatureLabMenu(
                wiring: environment.wiring,
                welcome: environment.welcome,
                onboarding: environment.onboarding,
                lockScreen: environment.lockScreen
            )
            statusItem.addSubmenu(titled: "🧪 Feature Lab", labMenu.menu)
            self.labMenu = labMenu
        }

        self.environment = environment
        self.statusItem = statusItem
        Bench.start(window: environment.window, playback: environment.playback, lockScreen: environment.lockScreen, shelf: environment.shelf, agents: environment.agents, activities: environment.activities, wiring: environment.wiring, welcome: environment.welcome, recording: environment.recording, preferences: environment.preferences)
        // The Calendar page connects to the Mac's calendars at launch (a
        // beat after, so the panel is up first), so it has events the
        // first time it opens.
        if environment.preferences.widgets && !firstLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak environment] in
                environment?.calendarGlance.connect()
            }
        }
    }
}
