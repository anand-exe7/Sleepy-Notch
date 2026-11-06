import SwiftUI

/// The sections in the Settings sidebar, laid out like System Settings: a
/// coloured icon and a title, plus the words a search should find it by.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case nowPlaying
    case peeks
    case indicators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .nowPlaying: return "Now Playing"
        case .peeks: return "Peeks"
        case .indicators: return "Indicators"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .nowPlaying: return "music.note"
        case .peeks: return "bell.badge.fill"
        case .indicators: return "menubar.rectangle"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .nowPlaying: return .pink
        case .peeks: return .red
        case .indicators: return .blue
        }
    }

    /// What's inside, for the sidebar's search field.
    private var keywords: [String] {
        switch self {
        case .general:
            return ["automation", "permission", "privacy", "music", "spotify", "shelf", "files", "drag", "demo", "scripting", "script", "cli", "url", "widgets", "weather", "pomodoro", "calendar", "stats", "cpu", "memory", "volume", "brightness", "keyboard backlight", "hud", "stay awake", "pop-up", "media keys", "screen recording", "recording"]
        case .nowPlaying:
            return ["album", "artwork", "cover", "animation", "colour", "color", "tint", "song", "track", "lyrics", "karaoke", "words", "floating", "mini", "queue", "playing next"]
        case .peeks:
            return ["keyboard", "caps lock", "input", "meeting", "calendar", "reminder", "copy", "clipboard", "accessibility", "bedtime", "wind down", "sleep", "reminder", "eye break", "20-20-20"]
        case .indicators:
            return ["camera", "microphone", "mic", "privacy", "battery", "charging", "agent", "hooks", "coding", "timer", "downloads", "tray", "crowded", "bubbles", "activities", "menu bar", "accessibility", "icons"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
