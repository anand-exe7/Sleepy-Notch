import Foundation

enum TimeFormatting {
    /// A playback time as "m:ss", e.g. 83 → "1:23". Fractions are dropped,
    /// matching how Music and Spotify count, and negatives read as 0.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
