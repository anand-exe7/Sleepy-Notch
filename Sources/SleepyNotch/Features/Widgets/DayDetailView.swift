import AppKit
import SwiftUI

/// The day tile of the Calendar page: the picked day, large; its events as
/// rows (calendar colour, title, time and place) that open in Calendar when
/// clicked, today's marked "Now" or "in 25 min" and the finished ones
/// dimmed; when the day is free, the next thing coming. A new day slides
/// its rows in; nothing else moves, and nothing ticks.
struct DayDetailView: View {
    @ObservedObject var glance: CalendarGlance


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.top, 8)
                .padding(.bottom, 8)
            // Keyed on the day the rows were read for, not the picked day:
            // the header changes at once, the rows swap when they arrive.
            // All the day's events, scrolling inside the tile when there are
            // more than fit; the tile itself never grows past its frame.
            ScrollView(.vertical, showsIndicators: true) {
                events
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(glance.eventsDate)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity
                    ))
                    .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            footer
                .padding(.top, 6)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: glance.eventsDate)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: glance.selectedDate)
    }

    // MARK: - The day

    private var header: some View {
        let date = glance.selectedDate ?? Date()
        let isToday = Calendar.current.isDateInToday(date)
        return HStack(alignment: .center, spacing: 10) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 36, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(isToday ? Color(nsColor: .systemRed) : Theme.Text.primary)
                .contentTransition(.numericText())
            VStack(alignment: .leading, spacing: 1) {
                Text(CalendarGlance.weekdayFormatter.string(from: date))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                Text(subtitle(date))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Text.tertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Today · November", "Tomorrow · November", "November 2026".
    private func subtitle(_ date: Date) -> String {
        let month = CalendarGlance.dayMonthFormatter.string(from: date)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today · \(month)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow · \(month)" }
        if calendar.isDateInYesterday(date) { return "Yesterday · \(month)" }
        return "\(month) \(calendar.component(.year, from: date))"
    }

    // MARK: - Events

    @ViewBuilder
    private var events: some View {
        if glance.accessDenied || glance.promptBlocked {
            VStack(alignment: .leading, spacing: 8) {
                Text(glance.promptBlocked
                     ? "macOS didn't ask for calendar access. Turn on Sleepy Notch in Privacy & Security → Calendars to see your events here."
                     : "Calendar access is off. Turn on Sleepy Notch in Privacy & Security to see your events here.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { glance.openPrivacySettings() } label: {
                    Text("Open Settings")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.92)))
                }
                .buttonStyle(PressScaleButtonStyle())
                .help("Privacy & Security, Calendars")
            }
        } else if !glance.canReadEvents {
            VStack(alignment: .leading, spacing: 8) {
                Text("See each day's events and what's coming up.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await glance.requestAccess() } } label: {
                    Text("Show Events")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white.opacity(0.92)))
                }
                .buttonStyle(PressScaleButtonStyle())
                .help("Allow calendar access")
            }
        } else if glance.dayEvents.isEmpty {
            freeDay
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(glance.dayEvents) { event in
                    row(event)
                }
            }
        }
    }

    /// Nothing on the picked day: say so, and show what's next.
    private var freeDay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 12, weight: .medium))
                Text("Nothing scheduled")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(Theme.Text.tertiary)
            if let next = glance.nextEvent {
                Button { glance.open(next.identifier) } label: {
                    HStack(spacing: 8) {
                        bar(next.color, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Next: \(next.title)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Theme.Text.secondary)
                            Text(next.when)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Theme.Text.tertiary)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleButtonStyle())
                .help("Open in Calendar")
            }
        }
    }

    private func row(_ event: CalendarGlance.DayEvent) -> some View {
        let past = event.status == .past
        return Button { glance.open(event.identifier) } label: {
            HStack(spacing: 8) {
                bar(event.color, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Text.primary)
                    Text(event.location.map { "\(event.time) · \($0)" } ?? event.time)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(Theme.Text.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                statusChip(event.status)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                if event.status == .now {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                }
            }
            .opacity(past ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .help("Open in Calendar")
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusChip(_ status: CalendarGlance.DayEvent.Status) -> some View {
        switch status {
        case .now:
            chip("Now", color: Color(nsColor: .systemRed))
        case .soon(let text):
            chip(text, color: Theme.Text.secondary)
        case .plain, .past:
            EmptyView()
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(color.opacity(0.16)))
            .fixedSize()
    }

    private func bar(_ color: CGColor?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(color.map { Color(cgColor: $0) } ?? Theme.Text.secondary)
            .frame(width: 3, height: height)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if !glance.isOnToday {
                pill("Today", symbol: "arrow.uturn.backward", help: "Back to today", action: glance.showToday)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Spacer(minLength: 0)
            pill("Calendar", symbol: "arrow.up.right", help: "Open Calendar", action: glance.openCalendar)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: glance.isOnToday)
    }

    private func pill(_ title: String, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: symbol).font(.system(size: 8.5, weight: .bold))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(Theme.Text.secondary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(PressScaleButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}
