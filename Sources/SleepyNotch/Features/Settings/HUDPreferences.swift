import Foundation

/// The choices made in the Settings window, remembered between launches.
///
/// The defaults keys keep their old `lab.` prefix from when these lived in
/// the Feature Lab, so choices made back then carry over.
@MainActor
final class HUDPreferences: ObservableObject {
    @Published var artworkStyle: ArtworkTransitionStyle {
        didSet { defaults.set(artworkStyle.rawValue, forKey: Key.artworkStyle) }
    }
    @Published var songChangePeek: Bool {
        didSet { defaults.set(songChangePeek, forKey: Key.songChangePeek) }
    }
    /// Tint the controls with the album's colour instead of white.
    @Published var albumTint: Bool {
        didSet { defaults.set(albumTint, forKey: Key.albumTint) }
    }

    /// Green and orange dots beside the notch while the camera or mic is on.
    @Published var privacyDots: Bool {
        didSet { defaults.set(privacyDots, forKey: Key.privacyDots) }
    }
    /// The album cover and playing bars beside the closed notch.
    @Published var nowPlayingWings: Bool {
        didSet { defaults.set(nowPlayingWings, forKey: Key.nowPlayingWings) }
    }
    /// The battery level beside the notch while charging.
    @Published var chargingWing: Bool {
        didSet { defaults.set(chargingWing, forKey: Key.chargingWing) }
    }
    /// A peek for Caps Lock and keyboard layout changes.
    @Published var keyboardPeek: Bool {
        didSet { defaults.set(keyboardPeek, forKey: Key.keyboardPeek) }
    }
    /// A peek five minutes before a meeting, with its Join link.
    @Published var meetingReminders: Bool {
        didSet { defaults.set(meetingReminders, forKey: Key.meetingReminders) }
    }
    /// A "Copied" peek when something's copied.
    @Published var copyPeek: Bool {
        didSet { defaults.set(copyPeek, forKey: Key.copyPeek) }
    }
    /// "Hello" from the notch each time the app opens, before anything else.
    @Published var welcomeAtStartup: Bool {
        didSet { defaults.set(welcomeAtStartup, forKey: Key.welcomeAtStartup) }
    }
    /// Dragging files onto the notch keeps them on a shelf in the card.
    @Published var shelf: Bool {
        didSet { defaults.set(shelf, forKey: Key.shelf) }
    }

    /// The Now Playing card above the lock screen.
    @Published var lockScreenCard: Bool {
        didSet { defaults.set(lockScreenCard, forKey: Key.lockScreenCard) }
    }

    /// The mic's bars follow your voice while an app uses the mic (asks for
    /// microphone access; nothing is recorded).
    @Published var voiceWaves: Bool {
        didSet { defaults.set(voiceWaves, forKey: Key.voiceWaves) }
    }

    /// How the camera, mic and charge show beside the closed notch: their
    /// own bubbles, or inside the notch's wings.
    @Published var statusStyle: StatusStyle {
        didSet { defaults.set(statusStyle.rawValue, forKey: Key.statusStyle) }
    }

    /// Countdown timers from the menu bar, shown beside the notch.
    @Published var timers: Bool {
        didSet { defaults.set(timers, forKey: Key.timers) }
    }

    /// Download progress beside the notch, from the Downloads folder.
    @Published var downloads: Bool {
        didSet { defaults.set(downloads, forKey: Key.downloads) }
    }

    /// What the notch's body is made of: Liquid Glass or solid black.
    @Published var finish: NotchFinish {
        didSet { defaults.set(finish.rawValue, forKey: Key.finish) }
    }

    private let defaults = UserDefaults.standard

    private enum Key {
        static let artworkStyle = "lab.artworkStyle"
        static let songChangePeek = "lab.songChangePeek"
        static let albumTint = "lab.albumTint"
        static let privacyDots = "lab.privacyDots"
        static let chargingWing = "lab.chargingWing"
        static let keyboardPeek = "lab.keyboardPeek"
        static let meetingReminders = "lab.meetingReminders"
        static let copyPeek = "lab.copyPeek"
        static let shelf = "settings.shelf"
        static let finish = "settings.finish"
        static let nowPlayingWings = "settings.nowPlayingWings"
        static let welcomeAtStartup = "settings.welcomeAtStartup"
        static let lockScreenCard = "settings.lockScreenCard"
        static let timers = "settings.timers"
        static let downloads = "settings.downloads"
        static let statusStyle = "settings.statusStyle"
        static let voiceWaves = "settings.voiceWaves"
    }

    /// Defaults are the Phase 2 picks: blur-morph covers, and the
    /// song-change peek on. Meeting reminders start off, because turning
    /// them on asks for calendar access — that should happen when someone
    /// chooses it, not the first time the app opens.
    init() {
        artworkStyle = defaults.string(forKey: Key.artworkStyle)
            .flatMap(ArtworkTransitionStyle.init(rawValue:)) ?? .blurMorph
        songChangePeek = defaults.object(forKey: Key.songChangePeek) as? Bool ?? true
        albumTint = defaults.object(forKey: Key.albumTint) as? Bool ?? false
        privacyDots = defaults.object(forKey: Key.privacyDots) as? Bool ?? true
        chargingWing = defaults.object(forKey: Key.chargingWing) as? Bool ?? true
        nowPlayingWings = defaults.object(forKey: Key.nowPlayingWings) as? Bool ?? true
        keyboardPeek = defaults.object(forKey: Key.keyboardPeek) as? Bool ?? true
        meetingReminders = defaults.object(forKey: Key.meetingReminders) as? Bool ?? false
        copyPeek = defaults.object(forKey: Key.copyPeek) as? Bool ?? true
        welcomeAtStartup = defaults.object(forKey: Key.welcomeAtStartup) as? Bool ?? true
        lockScreenCard = defaults.object(forKey: Key.lockScreenCard) as? Bool ?? true
        timers = defaults.object(forKey: Key.timers) as? Bool ?? true
        downloads = defaults.object(forKey: Key.downloads) as? Bool ?? true
        shelf = defaults.object(forKey: Key.shelf) as? Bool ?? true
        voiceWaves = defaults.object(forKey: Key.voiceWaves) as? Bool ?? true
        statusStyle = defaults.string(forKey: Key.statusStyle).flatMap(StatusStyle.init(rawValue:)) ?? .bubbles
        let savedFinish = defaults.string(forKey: Key.finish).flatMap(NotchFinish.init(rawValue:))
        finish = [savedFinish, .glass].compactMap { $0 }.first { $0.isAvailable } ?? .black
    }
}

/// How the camera, mic and charge show beside the closed notch.
enum StatusStyle: String, CaseIterable {
    /// Like the Dynamic Island: each gets a bubble that splits off the
    /// notch, announced by a short notice, and opens when clicked.
    case bubbles
    /// Small dots and the battery level inside the notch's own wings,
    /// taking that side's place from the cover or the bars.
    case inNotch

    var title: String {
        switch self {
        case .bubbles: "Bubbles"
        case .inNotch: "In the notch"
        }
    }

    var summary: String {
        switch self {
        case .bubbles: "The camera, mic and charge split off into their own bubbles, like the Dynamic Island. Click one to open it."
        case .inNotch: "Small dots and the battery level sit inside the notch, in place of the cover or the bars."
        }
    }
}
