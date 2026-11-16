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
    /// The dragged files are close to the notch: the notch opens its big
    /// drop zone before the pointer gets near the top edge.
    @Published private(set) var isNear = false
    /// The first few dragged files (for the drop zone's preview) and how
    /// many there are. Read once, when the drag is recognised.
    @Published private(set) var draggedFiles: [URL] = []
    @Published private(set) var draggedCount = 0
    /// Whether a point (screen coordinates) counts as near the notch. The
    /// second argument is whether it was near already, so the zone can be
    /// larger once open (it then covers the open drop zone) and the edge
    /// never flickers. Set by the app, which knows where the notch is.
    var nearTest: ((NSPoint, Bool) -> Bool)?

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
                // A global event's location is in screen coordinates.
                let location = event.locationInWindow
                MainActor.assumeIsolated { self?.handle(event.type, at: location) }
            }
        } else {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            looks = 0
            endDrag()
        }
    }

    /// Development only (see `Bench`): stands in for a real drag.
    func benchSet(files: [URL], near: Bool) {
        draggedFiles = Array(files.prefix(3))
        draggedCount = files.count
        isDraggingFiles = near
        isNear = near
    }

    private func endDrag() {
        if isNear { isNear = false }
        if isDraggingFiles { isDraggingFiles = false }
    }

    private func handle(_ type: NSEvent.EventType, at location: NSPoint) {
        switch type {
        case .leftMouseDown:
            changeAtPress = dragPasteboard.changeCount
            looks = 0
        case .leftMouseDragged:
            if isDraggingFiles {
                // One rectangle test per drag event; published only on change.
                let near = nearTest?(location, isNear) ?? false
                if near != isNear { isNear = near }
                return
            }
            guard looks < Self.maxLooks else { return }
            looks += 1
            // A drag put something new on the drag pasteboard.
            guard dragPasteboard.changeCount != changeAtPress,
                  let urls = dragPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty else { return }
            draggedCount = urls.count
            draggedFiles = Array(urls.prefix(3))
            isDraggingFiles = true
        case .leftMouseUp:
            looks = Self.maxLooks
            endDrag()
        default:
            break
        }
    }
}
