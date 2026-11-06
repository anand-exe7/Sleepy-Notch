import Foundation

/// What a system HUD is about.
enum HUDKind: Equatable {
    case volume
    case brightness
    case keyboardBacklight
}

/// One reading for a system HUD: how loud, how bright, how lit.
struct HUDReading: Equatable {
    var kind: HUDKind
    /// 0...1.
    var level: Double
    /// Volume only: muted.
    var muted = false
}
