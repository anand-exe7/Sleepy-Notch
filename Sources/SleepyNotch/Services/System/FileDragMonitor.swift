import AppKit

/// Knows when a file is being dragged, anywhere on the Mac, so the notch can
/// offer a place to drop it that isn't the very top edge of the screen (where
/// macOS opens Mission Control).
///
/// A global monitor for the mouse being dragged and released: those events
/// only exist while a button is down, so it is event-driven and does nothing
/// the rest of the time. On the first drag events of a press it looks once at
/// the system's drag pasteboard to see whether files were picked up.
@MainActor
final class FileDragMonitor: ObservableObject {
    /// Files are being dragged right now.
    @Published private(set) var isDraggingFiles = false

    private var monitor: Any?
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var changeAtPress = 0
    /// Drag events looked at for this press; a file drag starts a moment
    /// after the button goes down.
    private var looks = 0
    private static let maxLooks = 12

    func setRunning(_ on: Bool) {
        if on {
            guard monitor == nil else { return }
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event.type) }
            }
        } else {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            looks = 0
            if isDraggingFiles { isDraggingFiles = false }
        }
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            changeAtPress = dragPasteboard.changeCount
            looks = 0
        case .leftMouseDragged:
            guard !isDraggingFiles, looks < Self.maxLooks else { return }
            looks += 1
            // A drag put something new on the drag pasteboard.
            guard dragPasteboard.changeCount != changeAtPress,
                  dragPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
            isDraggingFiles = true
        case .leftMouseUp:
            looks = Self.maxLooks
            if isDraggingFiles { isDraggingFiles = false }
        default:
            break
        }
    }
}
