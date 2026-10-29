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
