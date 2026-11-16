import SwiftUI

/// The sections in the Settings sidebar, laid out like System Settings: a
/// coloured icon and a title, plus the words a search should find it by.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case nowPlaying
    case card
    case peeks
    case indicators
    case system
    case tools
    case agent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .nowPlaying: return "Now Playing"
        case .card: return "Card"
        case .peeks: return "Peeks"
        case .indicators: return "Indicators"
        case .system: return "System"
        case .tools: return "Shelf & Tools"
        case .agent: return "Agent"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .nowPlaying: return "music.note"
        case .card: return "rectangle.grid.1x2.fill"
        case .peeks: return "bell.badge.fill"
        case .indicators: return "menubar.rectangle"
        case .system: return "speaker.wave.2.fill"
        case .tools: return "tray.full.fill"
        case .agent: return "sparkles"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .nowPlaying: return .pink
        case .card: return .indigo
        case .peeks: return .red
        case .indicators: return .blue
        case .system: return .orange
        case .tools: return .teal
        case .agent: return .purple
        }
    }

    /// What's inside, for the sidebar's search field.
    private var keywords: [String] {
        switch self {
        case .general:
            return ["finish", "glass", "black", "idle", "empty card", "demo", "automation", "permission", "privacy", "music", "spotify"]
        case .nowPlaying:
            return ["album", "artwork", "cover", "animation", "colour", "color", "tint", "song", "track", "highlight", "accent", "theme", "floating", "mini", "queue", "playing next", "apple music", "lock screen", "animated", "musickit", "token"]
        case .card:
            return ["tabs", "buttons", "pages", "calendar", "events", "controls", "dark mode", "mute", "stay awake", "focus", "pomodoro", "toggles"]
        case .peeks:
            return ["keyboard", "caps lock", "input", "meeting", "reminder", "copy", "clipboard", "history", "bedtime", "wind down", "sleep", "eye break", "20-20-20", "charging", "plug", "power", "low battery", "headphones", "airpods", "bluetooth", "welcome", "hello", "colour", "rainbow"]
        case .indicators:
            return ["camera", "microphone", "mic", "privacy", "battery", "charging", "tray", "crowded", "bubbles", "activities", "menu bar", "icons", "voice waves"]
        case .system:
            return ["volume", "brightness", "keyboard backlight", "hud", "pop-up", "media keys", "stay awake", "timer", "downloads", "screen recording", "recording"]
        case .tools:
            return ["shelf", "files", "drag", "speech", "dictate", "dictation", "transcribe", "ocr", "capture text", "scan", "scripting", "script", "cli", "url"]
        case .agent:
            return ["agent", "hooks", "coding", "claude", "working", "needs input"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
