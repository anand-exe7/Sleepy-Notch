import SwiftUI

/// The colour of the playing bars, the progress line and the scrubber.
/// White by default, like the system's own Now Playing; the others are the
/// system's colours, in the shade macOS uses on dark surfaces. (The cover's
/// own colour is a separate switch, "Match album colour".)
enum HighlightColour: String, CaseIterable, Identifiable {
    case white
    case blue
    case purple
    case pink
    case orange
    case yellow
    case green
    case teal

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .white: return Theme.controlTint
        case .blue: return Color(nsColor: .systemBlue)
        case .purple: return Color(nsColor: .systemPurple)
        case .pink: return Color(nsColor: .systemPink)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green: return Color(nsColor: .systemGreen)
        case .teal: return Color(nsColor: .systemTeal)
        }
    }
}
