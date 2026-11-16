import SwiftUI
import EventKit

/// The calendar page's month, its days' events, and the picked day.
///
/// The days are plain date arithmetic. Events come from EventKit, read once
/// when the page opens, the month changes or a day is clicked, and only if
/// the user has already allowed calendar access: the page never asks by
/// itself (the page's Show Events button and Settings do). Nothing ticks:
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
    struct Cell: Equatable {
        let day: Int
        /// -1 the month before, 0 the shown month, 1 the month after.
        let month: Int
    }

    private let store = EKEventStore()
    private let calendar = Calendar.current

    var canReadEvents: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, *) { return status == .fullAccess }
        return status == .authorized
    }

    func requestAccess() async {
        if #available(macOS 14, *) {
            _ = try? await store.requestFullAccessToEvents()
        } else {
            _ = try? await store.requestAccess(to: .event)
        }
        refresh()
    }

    // MARK: - The month

    var shownMonth: Date {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }

    var monthName: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: shownMonth)
    }

    var yearText: String {
        String(calendar.component(.year, from: shownMonth))
    }

    /// Whether the shown month and picked day are already today's.
    var isOnToday: Bool { monthOffset == 0 && selectedDay == today }

    /// The weekday initials, starting from the locale's first weekday.
    var weekdayInitials: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    /// Which columns fall on a weekend, in the locale's week order.
    var weekendColumns: Set<Int> {
        var columns = Set<Int>()
        for column in 0..<7 {
            let weekday = (calendar.firstWeekday - 1 + column) % 7 + 1
            if weekday == 1 || weekday == 7 { columns.insert(column) }
        }
        return columns
    }

    /// Six rows of seven, the neighbouring months' days filling the ends.
    var weeks: [[Cell]] {
        guard let days = calendar.range(of: .day, in: .month, for: shownMonth)?.count,
              let previous = calendar.date(byAdding: .month, value: -1, to: shownMonth),
              let previousDays = calendar.range(of: .day, in: .month, for: previous)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: shownMonth)
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

    /// Today's number, when the shown month is this one.
    var today: Int? {
        monthOffset == 0 ? calendar.component(.day, from: Date()) : nil
    }

    func step(_ months: Int) {
        lastStep = months > 0 ? 1 : -1
        monthOffset += months
        selectedDay = monthOffset == 0 ? today : 1
        refresh()
    }

    func showToday() {
        guard !isOnToday else { return }
        lastStep = monthOffset > 0 ? -1 : 1
        monthOffset = 0
        selectedDay = today
        refresh()
    }

    /// Picks a day; one from a neighbouring month turns to that month.
    func select(_ cell: Cell) {
        if cell.month != 0 {
            lastStep = cell.month
            monthOffset += cell.month
            selectedDay = cell.day
            refresh()
            return
        }
        guard selectedDay != cell.day else { return }
        selectedDay = cell.day
        loadDayEvents()
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

    func refresh() {
        guard canReadEvents,
              let end = calendar.date(byAdding: .month, value: 1, to: shownMonth) else {
            if !eventColors.isEmpty { eventColors = [:] }
            if selectedDay == nil { selectedDay = today ?? 1 }
            if !dayEvents.isEmpty { dayEvents = [] }
            if nextEvent != nil { nextEvent = nil }
            return
        }
        let predicate = store.predicateForEvents(withStart: shownMonth, end: end, calendars: nil)
        var colors: [Int: [CGColor]] = [:]
        for event in store.events(matching: predicate) {
            guard let start = event.startDate, let finish = event.endDate else { continue }
            let color = event.calendar?.cgColor ?? NSColor.white.cgColor
            // An event covering several days marks each of them.
            var day = max(start, shownMonth)
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
        if colors != eventColors { eventColors = colors }
        if selectedDay == nil { selectedDay = today ?? 1 }
        loadDayEvents()
    }

    private func loadDayEvents() {
        guard canReadEvents, let start = selectedDate,
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else {
            if !dayEvents.isEmpty { dayEvents = [] }
            if nextEvent != nil { nextEvent = nil }
            return
        }
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
                        status = .soon(Self.soonText(from.timeIntervalSince(now)))
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
        if events != dayEvents { dayEvents = events }
        let upcoming = events.isEmpty ? findNextEvent(after: end) : nil
        if upcoming != nextEvent { nextEvent = upcoming }
    }

    /// "in 5 min", "in 1 hr 20 min".
    private static func soonText(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "in \(hours) hr" : "in \(hours) hr \(rest) min"
    }

    /// The first event in the four weeks after the picked day.
    private func findNextEvent(after start: Date) -> UpcomingEvent? {
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
}
