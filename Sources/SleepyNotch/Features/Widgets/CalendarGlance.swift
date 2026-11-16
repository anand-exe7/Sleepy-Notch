import SwiftUI
import EventKit

/// The calendar page's month, its days' events, and the picked day.
///
/// The days are plain date arithmetic, worked out once per month change and
/// kept (not on every redraw). Events come from EventKit, read when the page
/// opens, the month changes or a day is clicked, and only if the user has
/// already allowed calendar access: the page never asks by itself (the
/// page's Show Events button and Settings do).
///
/// Smoothness: EventKit reads run on their own serial queue, never on the
/// main thread, so a click or a month turn animates at once and the dots
/// and rows arrive a moment later. Each read carries a ticket; an answer
/// for a month or day that's no longer shown is dropped. Nothing ticks:
/// "now" and "in 20 min" are worked out at each read.
@MainActor
final class CalendarGlance: ObservableObject {
    /// Months away from this one.
    @Published private(set) var monthOffset = 0
    /// Which way the month last moved (-1 back, 1 forward), so the grid
    /// slides the right way.
    @Published private(set) var lastStep = 0
    /// Up to three calendar colours for each day of the shown month that
    /// has events.
    @Published private(set) var eventColors: [Int: [CGColor]] = [:]
    /// The day picked (today unless another is clicked).
    @Published private(set) var selectedDay: Int?
    /// That day's events, read once when it's picked.
    @Published private(set) var dayEvents: [DayEvent] = []
    /// When the picked day has nothing: the next event after it.
    @Published private(set) var nextEvent: UpcomingEvent?
    /// The day `dayEvents` belong to. The rows swap (with their slide) when
    /// this changes, so a new day never shows the old day's rows under its
    /// header while its own are still being read.
    @Published private(set) var eventsDate: Date?

    // Worked out once per month (see `rebuildMonth`), read by every redraw.
    private(set) var weeks: [[Cell]] = []
    private(set) var monthName = ""
    private(set) var yearText = ""
    private(set) var shownMonth = Date()
    let weekdayInitials: [String]
    let weekendColumns: Set<Int>

    struct DayEvent: Identifiable, Equatable {
        let id: String
        let identifier: String?
        let title: String
        /// "All day", or when it runs ("9:30 – 10:30 AM").
        let time: String
        let location: String?
        let color: CGColor?
        let status: Status

        enum Status: Equatable {
            /// Not today, or later today than the next couple of hours.
            case plain
            case past
            case now
            /// Starts within two hours: "in 25 min".
            case soon(String)
        }
    }

    struct UpcomingEvent: Equatable {
        let identifier: String?
        let title: String
        /// "Tomorrow, 9:30 AM", "Mon 17 Nov, All day".
        let when: String
        let color: CGColor?
    }

    /// One square of the month grid. Days of the months either side fill
    /// the first and last rows, dimmed, so the grid is always six rows.
    struct Cell: Equatable, Hashable {
        let day: Int
        /// -1 the month before, 0 the shown month, 1 the month after.
        let month: Int
    }

    private let store = EKEventStore()
    private let calendar = Calendar.current
    /// Every EventKit read happens here, in order, off the main thread.
    private let queue = DispatchQueue(label: "SleepyNotch.calendar", qos: .userInitiated)
    private var monthTicket = 0
    private var dayTicket = 0

    init() {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        weekdayInitials = (0..<7).map { symbols[(first + $0) % 7] }
        var columns = Set<Int>()
        for column in 0..<7 {
            let weekday = (calendar.firstWeekday - 1 + column) % 7 + 1
            if weekday == 1 || weekday == 7 { columns.insert(column) }
        }
        weekendColumns = columns
        rebuildMonth()
        selectedDay = today
    }

    var canReadEvents: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, *) { return status == .fullAccess }
        return status == .authorized
    }

    /// The user said no (or a profile blocks it): asking again shows
    /// nothing, so the page offers System Settings instead.
    var accessDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, *) { return status == .denied || status == .restricted || status == .writeOnly }
        return status == .denied || status == .restricted
    }

    func requestAccess() async {
        if #available(macOS 14, *) {
            _ = try? await store.requestFullAccessToEvents()
        } else {
            _ = try? await store.requestAccess(to: .event)
        }
        // Asked, yet still undecided: macOS refused to show its prompt
        // (it does when it holds an old answer for a differently signed
        // copy of the app). Say so, rather than sit on "Show Events".
        let undecided = EKEventStore.authorizationStatus(for: .event) == .notDetermined
        if undecided != promptBlocked { promptBlocked = undecided }
        objectWillChange.send()
        refresh()
    }

    /// The last request came back without macOS asking the user; the page
    /// then points to System Settings instead.
    @Published private(set) var promptBlocked = false

    /// Connects to the Mac's calendars at launch, so the page has events
    /// the first time it opens: asks once if macOS hasn't asked yet, and
    /// from then on follows Calendar's own change notice (an event added,
    /// moved or deleted anywhere, iCloud included) instead of re-reading
    /// on a timer. Only while the Calendar page is switched on.
    func connect() {
        if changeObserver == nil {
            changeObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            Task { await requestAccess() }
        } else {
            refresh()
        }
    }

    private var changeObserver: Any?

    /// Privacy & Security -> Calendars, to turn access back on.
    func openPrivacySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    // MARK: - The month

    /// Whether the shown month and picked day are already today's.
    var isOnToday: Bool { monthOffset == 0 && selectedDay == today }

    /// Today's number, when the shown month is this one.
    var today: Int? {
        monthOffset == 0 ? calendar.component(.day, from: Date()) : nil
    }

    /// The month's grid and names, once per month change. A new day (the
    /// page opened after midnight on the 1st) moves "this month" too.
    private func rebuildMonth() {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let month = calendar.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
        shownMonth = month
        monthName = Self.monthFormatter.string(from: month)
        yearText = String(calendar.component(.year, from: month))
        weeks = Self.grid(for: month, calendar: calendar)
    }

    /// Six rows of seven, the neighbouring months' days filling the ends.
    private static func grid(for month: Date, calendar: Calendar) -> [[Cell]] {
        guard let days = calendar.range(of: .day, in: .month, for: month)?.count,
              let previous = calendar.date(byAdding: .month, value: -1, to: month),
              let previousDays = calendar.range(of: .day, in: .month, for: previous)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells = (0..<lead).map { Cell(day: previousDays - lead + 1 + $0, month: -1) }
        cells += (1...days).map { Cell(day: $0, month: 0) }
        var next = 1
        while cells.count < 42 {
            cells.append(Cell(day: next, month: 1))
            next += 1
        }
        return stride(from: 0, to: 42, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    func step(_ months: Int) {
        lastStep = months > 0 ? 1 : -1
        moveMonth(by: months, selecting: nil)
    }

    func showToday() {
        guard !isOnToday else { return }
        lastStep = monthOffset > 0 ? -1 : 1
        moveMonth(by: -monthOffset, selecting: nil)
    }

    /// Picks a day; one from a neighbouring month turns to that month.
    func select(_ cell: Cell) {
        if cell.month != 0 {
            lastStep = cell.month
            moveMonth(by: cell.month, selecting: cell.day)
            return
        }
        guard selectedDay != cell.day else { return }
        selectedDay = cell.day
        loadDayEvents()
    }

    private func moveMonth(by months: Int, selecting day: Int?) {
        monthOffset += months
        rebuildMonth()
        // The old month's dots don't belong on the new grid.
        if !eventColors.isEmpty { eventColors = [:] }
        selectedDay = day ?? (monthOffset == 0 ? today : 1)
        refresh()
    }

    /// The picked day, as a date.
    var selectedDate: Date? {
        guard let day = selectedDay else { return nil }
        return calendar.date(byAdding: .day, value: day - 1, to: shownMonth)
    }

    // MARK: - Opening Calendar

    /// Shows the event in Calendar, or just opens Calendar.
    func open(_ identifier: String?) {
        if let identifier,
           let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        openCalendar()
    }

    func openCalendar() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    // MARK: - Events

    /// Re-reads the shown month's dots and the picked day's events. The
    /// month is rebuilt first only when the shown month went stale (the
    /// page reopened in a new month).
    func refresh() {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        if calendar.date(byAdding: .month, value: monthOffset, to: thisMonth) != shownMonth { rebuildMonth() }
        if selectedDay == nil { selectedDay = today ?? 1 }
        guard canReadEvents,
              let end = calendar.date(byAdding: .month, value: 1, to: shownMonth) else {
            if !eventColors.isEmpty { eventColors = [:] }
            clearDay()
            return
        }
        monthTicket += 1
        let ticket = monthTicket
        let start = shownMonth
        let store = store
        let calendar = calendar
        queue.async { [weak self] in
            let colors = Self.readColors(store: store, calendar: calendar, from: start, to: end)
            DispatchQueue.main.async {
                guard let self, self.monthTicket == ticket else { return }
                if colors.value != self.eventColors { self.eventColors = colors.value }
            }
        }
        loadDayEvents()
    }

    private func clearDay() {
        if !dayEvents.isEmpty { dayEvents = [] }
        if nextEvent != nil { nextEvent = nil }
        let date = selectedDate
        if eventsDate != date { eventsDate = date }
    }

    private func loadDayEvents() {
        guard canReadEvents, let start = selectedDate,
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return clearDay() }
        dayTicket += 1
        let ticket = dayTicket
        let store = store
        let calendar = calendar
        queue.async { [weak self] in
            let read = Self.readDay(store: store, calendar: calendar, from: start, to: end)
            DispatchQueue.main.async {
                guard let self, self.dayTicket == ticket else { return }
                // One change, one redraw: the rows, the "next" line and the
                // day they belong to arrive together.
                if read.value.events != self.dayEvents { self.dayEvents = read.value.events }
                if read.value.next != self.nextEvent { self.nextEvent = read.value.next }
                if self.eventsDate != start { self.eventsDate = start }
            }
        }
    }

    // MARK: - Reading (on `queue`)

    /// Carries plain values (CGColors among them) back to the main thread.
    private struct Box<T>: @unchecked Sendable { let value: T }

    nonisolated private static func readColors(store: EKEventStore, calendar: Calendar, from start: Date, to end: Date) -> Box<[Int: [CGColor]]> {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var colors: [Int: [CGColor]] = [:]
        for event in store.events(matching: predicate) {
            guard let from = event.startDate, let finish = event.endDate else { continue }
            let color = event.calendar?.cgColor ?? NSColor.white.cgColor
            // An event covering several days marks each of them.
            var day = max(from, start)
            let last = min(finish, end)
            while day < last {
                let number = calendar.component(.day, from: day)
                var list = colors[number] ?? []
                if list.count < 3, !list.contains(where: { $0 == color }) { list.append(color) }
                colors[number] = list
                guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { break }
                day = next
            }
        }
        return Box(value: colors)
    }

    nonisolated private static func readDay(store: EKEventStore, calendar: Calendar, from start: Date, to end: Date) -> Box<(events: [DayEvent], next: UpcomingEvent?)> {
        let now = Date()
        let isToday = calendar.isDateInToday(start)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let range = DateIntervalFormatter()
        range.timeStyle = .short
        range.dateStyle = .none
        let events = store.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate ?? start) < ($1.isAllDay ? 0 : 1, $1.startDate ?? start) }
            .map { event -> DayEvent in
                let from = event.startDate ?? start
                let to = event.endDate ?? end
                var status = DayEvent.Status.plain
                if isToday && !event.isAllDay {
                    if to <= now {
                        status = .past
                    } else if from <= now {
                        status = .now
                    } else if from.timeIntervalSince(now) < 2 * 3600 {
                        status = .soon(soonText(from.timeIntervalSince(now)))
                    }
                }
                return DayEvent(
                    id: (event.eventIdentifier ?? UUID().uuidString) + "\(from.timeIntervalSince1970)",
                    identifier: event.eventIdentifier,
                    title: event.title ?? "Untitled",
                    time: event.isAllDay ? "All day" : range.string(from: max(from, start), to: min(to, end)),
                    location: event.location.flatMap { $0.isEmpty ? nil : $0.components(separatedBy: .newlines).first },
                    color: event.calendar?.cgColor,
                    status: status
                )
            }
        // The same event in two calendars (a holiday in both "Holidays in
        // India" and a subscribed one) shows once.
        var seen = Set<String>()
        let unique = events.filter { seen.insert("\($0.title)|\($0.time)").inserted }
        let next = unique.isEmpty ? findNextEvent(store: store, calendar: calendar, after: end) : nil
        return Box(value: (unique, next))
    }

    /// "in 5 min", "in 1 hr 20 min".
    nonisolated private static func soonText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "in \(hours) hr" : "in \(hours) hr \(rest) min"
    }

    /// The first event in the four weeks after the picked day.
    nonisolated private static func findNextEvent(store: EKEventStore, calendar: Calendar, after start: Date) -> UpcomingEvent? {
        guard let end = calendar.date(byAdding: .day, value: 28, to: start) else { return nil }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        guard let event = store.events(matching: predicate)
            .filter({ ($0.startDate ?? .distantPast) >= start })
            .min(by: { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }),
            let date = event.startDate
        else { return nil }
        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
            day = formatter.string(from: date)
        }
        let time: String
        if event.isAllDay {
            time = "All day"
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            time = formatter.string(from: date)
        }
        return UpcomingEvent(identifier: event.eventIdentifier, title: event.title ?? "Untitled", when: "\(day), \(time)", color: event.calendar?.cgColor)
    }

    // MARK: - Formatters (made once; a DateFormatter is costly to build)

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    static let dayMonthFormatter: DateFormatter = monthFormatter
}
