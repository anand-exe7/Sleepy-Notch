import SwiftUI

/// The sections in the Settings sidebar, laid out like System Settings: each
/// one has a coloured icon, a title, and a line saying what's inside.
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

    var summary: String {
        switch self {
        case .general:
            return "Control access to your music apps and try the notch with a sample track."
        case .nowPlaying:
            return "Choose how the player looks and moves when a song plays or changes."
        case .peeks:
            return "Short alerts that drop out of the notch and tuck away on their own."
        case .indicators:
            return "Small signals that sit beside the notch while something is happening."
        }
    }
}
