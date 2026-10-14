import Foundation

/// Choices made in the Feature Lab menu, remembered between launches so a
/// style you're comparing doesn't reset every `swift run`.
@MainActor
final class LabSettings: ObservableObject {
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
    @Published var chargingStyle: ChargingPeekStyle {
        didSet { defaults.set(chargingStyle.rawValue, forKey: Key.chargingStyle) }
    }

    /// Green and orange dots beside the notch while the camera or mic is on.
    @Published var privacyDots: Bool {
        didSet { defaults.set(privacyDots, forKey: Key.privacyDots) }
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

    private let defaults = UserDefaults.standard

    private enum Key {
        static let artworkStyle = "lab.artworkStyle"
        static let songChangePeek = "lab.songChangePeek"
        static let albumTint = "lab.albumTint"
        static let chargingStyle = "lab.chargingStyle"
        static let privacyDots = "lab.privacyDots"
        static let chargingWing = "lab.chargingWing"
        static let keyboardPeek = "lab.keyboardPeek"
        static let meetingReminders = "lab.meetingReminders"
        static let copyPeek = "lab.copyPeek"
    }

    /// Defaults are the styles picked in the Phase 2 review: blur-morph
    /// covers, the liquid charging battery, and the song-change peek on.
    init() {
        artworkStyle = defaults.string(forKey: Key.artworkStyle)
            .flatMap(ArtworkTransitionStyle.init(rawValue:)) ?? .blurMorph
        songChangePeek = defaults.object(forKey: Key.songChangePeek) as? Bool ?? true
        albumTint = defaults.object(forKey: Key.albumTint) as? Bool ?? false
        chargingStyle = defaults.string(forKey: Key.chargingStyle)
            .flatMap(ChargingPeekStyle.init(rawValue:)) ?? .liquid
        privacyDots = defaults.object(forKey: Key.privacyDots) as? Bool ?? true
        chargingWing = defaults.object(forKey: Key.chargingWing) as? Bool ?? true
        keyboardPeek = defaults.object(forKey: Key.keyboardPeek) as? Bool ?? true
        meetingReminders = defaults.object(forKey: Key.meetingReminders) as? Bool ?? true
        copyPeek = defaults.object(forKey: Key.copyPeek) as? Bool ?? true
    }
}

/// The two charging looks being compared.
enum ChargingPeekStyle: String, CaseIterable {
    /// iPhone-style ring that fills around a bolt.
    case ring
    /// A battery that fills with a gently moving liquid.
    case liquid

    var title: String {
        switch self {
        case .ring: return "Ring"
        case .liquid: return "Liquid battery"
        }
    }
}
