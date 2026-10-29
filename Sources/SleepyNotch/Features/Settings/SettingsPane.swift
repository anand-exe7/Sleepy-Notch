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
            return ["automation", "permission", "privacy", "music", "spotify", "shelf", "files", "drag", "demo"]
        case .nowPlaying:
            return ["album", "artwork", "cover", "animation", "colour", "color", "tint", "song", "track"]
        case .peeks:
            return ["keyboard", "caps lock", "input", "meeting", "calendar", "reminder", "copy", "clipboard", "accessibility"]
        case .indicators:
            return ["camera", "microphone", "mic", "privacy", "battery", "charging"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title] + keywords).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
