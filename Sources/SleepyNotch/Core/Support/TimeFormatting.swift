import Foundation

enum TimeFormatting {
    /// A playback time as "m:ss", e.g. 83 → "1:23", or "h:mm:ss" from an
    /// hour up, like Music shows long mixes and podcasts. Fractions are
    /// dropped, matching how Music and Spotify count; negatives and values
    /// that aren't a real number read as 0 (`Int(_:)` would crash on them).
    static func clock(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(min(seconds, 359_999))) : 0
        let hours = total / 3600
        let minutes = total / 60 % 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
