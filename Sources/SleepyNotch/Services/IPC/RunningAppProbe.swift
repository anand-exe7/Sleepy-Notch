import AppKit
import Foundation

/// Answers "which music apps are actually running?" without touching the UI.
///
/// `NSRunningApplication.runningApplications(withBundleIdentifier:)` walks the
/// workspace's running-app list, which is not free. Keeping it in one place
/// means the startup probe and any future display-selection logic ask the same
/// question the same way.
enum RunningAppProbe {
    private static let bundleIdentifiers: [MusicSource: String] = [
        .appleMusic: "com.apple.Music",
        .spotify: "com.spotify.client"
    ]

    /// Sources that have a live process, in declaration order.
    static func runningMusicApps() -> [MusicSource] {
        bundleIdentifiers.compactMap { source, identifier in
            isRunning(source) ? source : nil
        }
    }

    static func isRunning(_ source: MusicSource) -> Bool {
        guard let identifier = bundleIdentifiers[source] else { return false }
        return !NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier)
            .isEmpty
    }

    /// The AppleScript application name for a source.
    static func applicationName(for source: MusicSource) -> String {
        switch source {
        case .appleMusic: return "Music"
        case .spotify: return "Spotify"
        case .demo: return "Music"
        }
    }
}
