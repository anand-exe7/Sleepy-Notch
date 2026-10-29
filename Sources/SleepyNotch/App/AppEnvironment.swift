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

        self.power = power
        self.playback = playback
        self.peeks = peeks
        self.shelf = shelf
        self.preferences = preferences
        self.powerSource = powerSource
        self.audioDevices = audioDevices
        self.status = status
        self.privacy = PrivacyIndicatorMonitor()
        self.keyboard = KeyboardMonitor()
        self.calendar = CalendarMonitor()
        self.clipboard = ClipboardMonitor()

        // The window hosts the HUD but doesn't know what's in it.
        self.window = NotchWindowController(power: power) { controller in
            NotchView(
                windowController: controller,
                media: playback,
                peeks: peeks,
                shelf: shelf,
                preferences: preferences,
                status: status,
                power: power
            )
        }

        self.settings = SettingsWindowController(
            preferences: preferences,
            playback: playback,
            keyboard: keyboard,
            calendar: calendar
        )

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
            clipboard: clipboard
        )
    }
}
