import AppKit

/// Live status the closed notch shows in small wings either side of the
/// camera (see `StatusWingsView`): the privacy dots on the left, the battery
/// while charging on the right.
@MainActor
final class NotchStatus: ObservableObject {
    @Published var micInUse = false
    @Published var cameraInUse = false
    /// The battery level while it's charging; `nil` otherwise.
    @Published var chargingLevel: Int?
}

/// What the wings show right now, with the Settings switches applied. A value,
/// so layout can compare it.
struct NotchIndicators: Equatable {
    var micInUse = false
    var cameraInUse = false
    var chargingLevel: Int?

    static let none = NotchIndicators()

    var hasLeading: Bool { micInUse || cameraInUse }
    var hasTrailing: Bool { chargingLevel != nil }
    var isEmpty: Bool { !hasLeading && !hasTrailing }

    /// What the closed notch shows in its own wings, like the Dynamic
    /// Island's main activity: the song first, then the charge, then the
    /// camera and mic. Everything else gets a bubble beside it.
    enum Primary: Equatable {
        case none
        case music
        case charging
        case privacy
    }

    func primary(nowPlaying: Bool) -> Primary {
        if nowPlaying { return .music }
        if hasTrailing { return .charging }
        if hasLeading { return .privacy }
        return .none
    }

    /// The camera and mic in a bubble left of the notch, when something
    /// else has the notch.
    func hasLeadingBubble(nowPlaying: Bool) -> Bool {
        hasLeading && primary(nowPlaying: nowPlaying) != .privacy
    }

    /// The charge in a bubble right of the notch, while a song has it.
    func hasTrailingBubble(nowPlaying: Bool) -> Bool {
        hasTrailing && primary(nowPlaying: nowPlaying) == .music
    }
}

/// Caps Lock flipping, or the keyboard layout changing.
enum KeyboardEvent: Equatable {
    case capsLock(isOn: Bool)
    case inputSource(name: String)
}

/// A calendar event about to start.
struct MeetingReminder: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let calendarColor: NSColor
    /// A Zoom, Meet, Teams, FaceTime… link found in the event, if any.
    let joinURL: URL?
}

/// What was just copied, reduced to what the copy peek shows.
struct ClipboardPreview: Equatable {
    enum Kind {
        case text(String)
        case link(URL)
        case image(NSImage)
        case files([URL])
    }

    let id = UUID()
    let kind: Kind

    static func == (lhs: ClipboardPreview, rhs: ClipboardPreview) -> Bool {
        lhs.id == rhs.id
    }
}
