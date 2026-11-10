import SwiftUI
import EventKit

/// The calendar widget's month, and which of its days have events.
///
/// The days are plain date arithmetic. The event dots come from EventKit,
/// read once when the widget opens or the month changes, and only if the
/// user has already allowed calendar access: the widget never asks by
/// itself (Settings has the switch that does).
@MainActor
final class CalendarGlance: ObservableObject {
    /// Months away from this one.
    @Published private(set) var monthOffset = 0
    /// Days of the shown month that have an event.
    @Published private(set) var eventDays: Set<Int> = []

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

    var title: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: shownMonth)
    }

    /// The weekday initials, starting from the locale's first weekday.
    var weekdayInitials: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    /// Rows of seven: nil for the empty cells before the 1st and after the end.
    var weeks: [[Int?]] {
        guard let days = calendar.range(of: .day, in: .month, for: shownMonth)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: shownMonth)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead) + (1...days).map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Today's number, when the shown month is this one.
    var today: Int? {
        monthOffset == 0 ? calendar.component(.day, from: Date()) : nil
    }

    func step(_ months: Int) {
        monthOffset += months
        refresh()
    }

    func showToday() {
        guard monthOffset != 0 else { return }
        monthOffset = 0
        refresh()
    }

    // MARK: - Events

    func refresh() {
        guard canReadEvents,
              let end = calendar.date(byAdding: .month, value: 1, to: shownMonth) else {
            if !eventDays.isEmpty { eventDays = [] }
            return
        }
        let predicate = store.predicateForEvents(withStart: shownMonth, end: end, calendars: nil)
        var days = Set<Int>()
        for event in store.events(matching: predicate) {
            guard let start = event.startDate, let finish = event.endDate else { continue }
            // An event covering several days marks each of them.
            var day = max(start, shownMonth)
            let last = min(finish, end)
            while day < last {
                days.insert(calendar.component(.day, from: day))
                guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { break }
                day = next
            }
        }
        if days != eventDays { eventDays = days }
    }
}
