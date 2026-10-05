import Foundation

/// A change in how the Mac is powered, worth a brief peek.
struct PowerEvent: Equatable {
    enum Kind: Equatable {
        case pluggedIn
        case unplugged
        case fullyCharged
        case low
    }

    let kind: Kind
    /// Battery percentage, 0–100.
    let level: Int
    let isCharging: Bool
}
