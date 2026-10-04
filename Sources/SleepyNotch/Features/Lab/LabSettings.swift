import Foundation

/// Choices made in the Feature Lab menu, remembered between launches so a
/// style you're comparing doesn't reset every `swift run`.
@MainActor
final class LabSettings: ObservableObject {
    static let shared = LabSettings()

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

    private let defaults = UserDefaults.standard

    private enum Key {
        static let artworkStyle = "lab.artworkStyle"
        static let songChangePeek = "lab.songChangePeek"
        static let albumTint = "lab.albumTint"
        static let chargingStyle = "lab.chargingStyle"
    }

    private init() {
        artworkStyle = defaults.string(forKey: Key.artworkStyle)
            .flatMap(ArtworkTransitionStyle.init(rawValue:)) ?? .flip
        songChangePeek = defaults.object(forKey: Key.songChangePeek) as? Bool ?? true
        albumTint = defaults.object(forKey: Key.albumTint) as? Bool ?? false
        chargingStyle = defaults.string(forKey: Key.chargingStyle)
            .flatMap(ChargingPeekStyle.init(rawValue:)) ?? .ring
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
