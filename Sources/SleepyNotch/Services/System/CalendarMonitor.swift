import AppKit
import EventKit

/// Reminds you of meetings a few minutes before they start, with the
/// meeting's video link when it has one.
///
/// Asks for calendar access the first time it starts. One one-shot timer,
/// set for the next reminder; it's re-planned when the calendar changes or
/// the Mac wakes. Nothing is polled.
@MainActor
final class CalendarMonitor: ObservableObject {
    var onReminder: ((MeetingReminder) -> Void)?

    enum Access {
        case notDetermined, granted, denied
    }

    /// Whether the app may read the calendar, for the Settings window to
    /// say when reminders can't work.
    @Published private(set) var access = CalendarMonitor.currentAccess()

    /// How long before the start the reminder shows.
    static let leadTime: TimeInterval = 5 * 60
    /// How far ahead to look for the next event.
    private static let horizon: TimeInterval = 12 * 3600

    private let store = EKEventStore()
    private var next: DispatchWorkItem?
    /// Reminders already shown, by event and start, so a re-plan doesn't
    /// repeat one.
    private var shown: Set<String> = []
    private var isStarted = false
    private var isObserving = false
    private(set) var isAuthorized = false

    init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        requestAccess { [weak self] granted in
            guard let self else { return }
            self.access = granted ? .granted : .denied
            guard granted else { return }
            self.isAuthorized = true
            self.observe()
            self.plan()
        }
    }

    func stop() {
        next?.cancel()
        next = nil
        // So turning reminders back on asks again, or picks up access
        // granted in System Settings since.
        isStarted = false
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        default: return .granted
        }
    }

    private func requestAccess(_ done: @escaping @MainActor (Bool) -> Void) {
        let finish: @Sendable (Bool, Error?) -> Void = { granted, _ in
            Task { @MainActor in done(granted) }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: finish)
        } else {
            store.requestAccess(to: .event, completion: finish)
        }
    }

    private func observe() {
        guard !isObserving else { return }
        isObserving = true
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.plan() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.plan() }
        }
    }

    // MARK: - Planning

    /// Shows a reminder that's due now, if any, and sets the timer for the
    /// next one — or for a re-check later, when nothing is coming up.
    private func plan() {
        next?.cancel()
        // Turned off: calendar changes and waking up plan nothing.
        guard isStarted, isAuthorized else { return }
        let now = Date()

        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-60), end: now.addingTimeInterval(Self.horizon), calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !Self.declined($0) && $0.startDate > now.addingTimeInterval(-60) }
            .sorted { $0.startDate < $1.startDate }

        var wakeAt = now.addingTimeInterval(Self.horizon / 2)
        var postedNow = false
        for event in events {
            let key = Self.key(event)
            guard !shown.contains(key) else { continue }
            let due = event.startDate.addingTimeInterval(-Self.leadTime)
            if due <= now {
                // One at a time; the next waits for the following plan.
                guard !postedNow else { wakeAt = now.addingTimeInterval(8); break }
                shown.insert(key)
                postedNow = true
                onReminder?(Self.reminder(for: event))
            } else {
                wakeAt = min(wakeAt, due)
                break
            }
        }

        let work = DispatchWorkItem { [weak self] in self?.plan() }
        next = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, wakeAt.timeIntervalSinceNow), execute: work)
    }

    private static func key(_ event: EKEvent) -> String {
        "\(event.eventIdentifier ?? event.title ?? "")@\(event.startDate.timeIntervalSince1970)"
    }

    private static func declined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
    }

    private static func reminder(for event: EKEvent) -> MeetingReminder {
        MeetingReminder(
            id: key(event),
            title: event.title?.isEmpty == false ? event.title : "Event",
            start: event.startDate,
            end: event.endDate,
            calendarColor: event.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemBlue } ?? .systemBlue,
            joinURL: joinURL(for: event)
        )
    }

    // MARK: - Video links

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "facetime.apple.com", "whereby.com", "meet.jit.si", "chime.aws",
    ]

    /// The first video-call link in the event's URL, location or notes.
    static func joinURL(for event: EKEvent) -> URL? {
        var candidates: [URL] = event.url.map { [$0] } ?? []
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        if !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            candidates += detector.matches(in: text, range: range).compactMap(\.url)
        }
        return candidates.first { url in
            guard let host = url.host?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
}
