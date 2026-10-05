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
    let lab: LabSettings
    let powerSource: PowerSourceMonitor
    let audioDevices: AudioDeviceMonitor
    let window: NotchWindowController

    #if DEBUG
    let featureLab: FeatureLab
    #endif

    init() {
        let power = PowerStateMonitor()
        let playback = PlaybackCoordinator(
            appleMusic: AppleMusicSource(),
            spotify: SpotifySource(),
            demo: DemoSource()
        )
        let peeks = PeekCenter(power: power)
        let shelf = ShelfStore()
        let lab = LabSettings()
        let powerSource = PowerSourceMonitor()
        let audioDevices = AudioDeviceMonitor()

        self.power = power
        self.playback = playback
        self.peeks = peeks
        self.shelf = shelf
        self.lab = lab
        self.powerSource = powerSource
        self.audioDevices = audioDevices

        // The window hosts the HUD but doesn't know what's in it.
        self.window = NotchWindowController(power: power) { controller in
            NotchView(
                windowController: controller,
                media: playback,
                peeks: peeks,
                shelf: shelf,
                lab: lab,
                power: power
            )
        }

        #if DEBUG
        self.featureLab = FeatureLab(
            playback: playback,
            peeks: peeks,
            shelf: shelf,
            lab: lab,
            powerSource: powerSource,
            audioDevices: audioDevices
        )
        #endif
    }
}
