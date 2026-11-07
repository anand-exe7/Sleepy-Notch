import AppKit

/// Builds the app's long-lived objects once, at launch, and connects them.
///
/// This is the only place concrete types meet. Everything else is handed
/// what it uses rather than reaching for a shared instance, which keeps the
/// layers honest (services never build views) and lets tests construct any
/// piece on its own.
@MainActor
final class AppEnvironment {
    let power: PowerStateMonitor
    let playback: PlaybackCoordinator
    let peeks: PeekCenter
    let shelf: ShelfStore
    let preferences: HUDPreferences
    let powerSource: PowerSourceMonitor
    let audioDevices: AudioDeviceMonitor
    let status: NotchStatus
    let privacy: PrivacyIndicatorMonitor
    let keyboard: KeyboardMonitor
    let calendar: CalendarMonitor
    let clipboard: ClipboardMonitor
    let window: NotchWindowController
    let settings: SettingsWindowController
    let wiring: AppWiring
    let activities: ActivityManager
    let timers: TimerService
    let downloads: DownloadsMonitor
    let agents: AgentStatusService
    let windDown: WindDownScheduler
    let eyeBreak: EyeBreakScheduler
    let stayAwake: StayAwakeService
    let accessibility: AccessibilityAccess
    let crowding: MenuBarCrowding
    let mediaKeys: MediaKeyInterceptor
    let recording: ScreenRecordingMonitor
    let weather: WeatherService
    let stats: SystemStatsSampler
    let calendarGlance: CalendarGlance
    let pomodoro: PomodoroService
    let lyrics: LyricsService
    let upNext: UpNextService
    let clipboardHistory: ClipboardHistory
    let fileDrag: FileDragMonitor
    let floating: FloatingPlayerController
    let hud: SystemHUDMonitor
    let bridge: LocalBridge
    let agentInstaller: AgentHookInstaller
    let welcome: WelcomeCoordinator
    let lockScreen: LockScreenController
    let library: LibraryController

    init() {
        let power = PowerStateMonitor()
        let playback = PlaybackCoordinator(
            appleMusic: AppleMusicSource(),
            spotify: SpotifySource(),
            demo: DemoSource()
        )
        let peeks = PeekCenter(power: power)
        let shelf = ShelfStore()
        let preferences = HUDPreferences()
        let powerSource = PowerSourceMonitor()
        let audioDevices = AudioDeviceMonitor()
        let status = NotchStatus()
        let activities = ActivityManager(peeks: peeks)

        self.power = power
        self.playback = playback
        self.peeks = peeks
        self.shelf = shelf
        self.preferences = preferences
        self.powerSource = powerSource
        self.audioDevices = audioDevices
        self.status = status
        self.activities = activities
        let timers = TimerService()
        self.timers = timers
        let downloads = DownloadsMonitor()
        self.downloads = downloads
        let socketPath = AgentHookInstaller.defaultSocketPath
        let agents = AgentStatusService(socketPath: socketPath)
        self.agents = agents
        let windDown = WindDownScheduler()
        self.windDown = windDown
        let eyeBreak = EyeBreakScheduler()
        self.eyeBreak = eyeBreak
        self.stayAwake = StayAwakeService()
        self.accessibility = AccessibilityAccess()
        self.crowding = MenuBarCrowding()
        self.mediaKeys = MediaKeyInterceptor()
        self.recording = ScreenRecordingMonitor()
        let weather = WeatherService()
        self.weather = weather
        let stats = SystemStatsSampler()
        self.stats = stats
        let calendarGlance = CalendarGlance()
        self.calendarGlance = calendarGlance
        let pomodoro = PomodoroService(timers: timers)
        self.pomodoro = pomodoro
        let lyrics = LyricsService()
        self.lyrics = lyrics
        let upNext = UpNextService()
        self.upNext = upNext
        let clipboardHistory = ClipboardHistory()
        self.clipboardHistory = clipboardHistory
        let fileDrag = FileDragMonitor()
        self.fileDrag = fileDrag
        let hud = SystemHUDMonitor()
        self.hud = hud
        let bridge = LocalBridge(socketPath: LocalBridge.defaultSocketPath)
        self.bridge = bridge
        self.agentInstaller = AgentHookInstaller(
            settingsPath: AgentHookInstaller.defaultSettingsPath,
            socketPath: socketPath
        )
        self.privacy = PrivacyIndicatorMonitor()
        self.keyboard = KeyboardMonitor()
        self.calendar = CalendarMonitor()
        self.clipboard = ClipboardMonitor()

        // The window is built before Settings, so the HUD reaches it through
        // this, filled in below.
        var settingsController: SettingsWindowController?

        let library = LibraryController(media: playback)
        self.library = library
        self.floating = FloatingPlayerController(media: playback, power: power, library: library, lyrics: lyrics, upNext: upNext, preferences: preferences)

        // The window hosts the HUD but doesn't know what's in it.
        self.window = NotchWindowController(power: power) { controller in
            NotchView(
                windowController: controller,
                media: playback,
                peeks: peeks,
                shelf: shelf,
                preferences: preferences,
                status: status,
                activities: activities,
                power: power,
                library: library,
                openSettings: { settingsController?.show() }
            )
            .environmentObject(downloads)
            .environmentObject(agents)
            .environmentObject(weather)
            .environmentObject(stats)
            .environmentObject(calendarGlance)
            .environmentObject(pomodoro)
            .environmentObject(lyrics)
            .environmentObject(upNext)
            .environmentObject(clipboardHistory)
            .environmentObject(timers)
        }

        let welcome = WelcomeCoordinator(
            peeks: peeks,
            power: power,
            preferences: preferences,
            window: window
        )
        self.welcome = welcome
        self.lockScreen = LockScreenController(media: playback, power: power, preferences: preferences)

        self.settings = SettingsWindowController(
            preferences: preferences,
            playback: playback,
            keyboard: keyboard,
            calendar: calendar,
            accessibility: accessibility,
            weather: weather,
            glance: calendarGlance,
            floating: floating,
            clipboardHistory: clipboardHistory,
            agentInstaller: agentInstaller,
            previewWelcome: { welcome.preview() }
        )
        settingsController = settings

        self.wiring = AppWiring(
            playback: playback,
            peeks: peeks,
            shelf: shelf,
            preferences: preferences,
            powerSource: powerSource,
            audioDevices: audioDevices,
            power: power,
            status: status,
            privacy: privacy,
            keyboard: keyboard,
            calendar: calendar,
            clipboard: clipboard,
            downloads: downloads,
            agents: agents,
            windDown: windDown,
            eyeBreak: eyeBreak,
            bridge: bridge,
            timers: timers,
            hud: hud,
            accessibility: accessibility,
            crowding: crowding,
            mediaKeys: mediaKeys,
            recording: recording,
            pomodoro: pomodoro,
            clipboardHistory: clipboardHistory,
            fileDrag: fileDrag
        )
    }
}
