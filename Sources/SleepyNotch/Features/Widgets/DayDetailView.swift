import SwiftUI

/// The right side of the Calendar page: the picked day, big, and its
/// events as simple rows (calendar colour, title, time). A new day slides
/// its rows in; nothing else moves.
struct DayDetailView: View {
    @ObservedObject var glance: CalendarGlance

    /// Rows that fit beside the month.
    private static let maxRows = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            events
                .id(glance.selectedDate)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity
                ))
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: glance.selectedDate)
        .animation(.easeOut(duration: 0.2), value: glance.dayEvents)
    }

    // MARK: - The day

    private var header: some View {
        let date = glance.selectedDate ?? Date()
        return VStack(alignment: .leading, spacing: 0) {
            Text(weekday(date))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.Text.secondary)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.primary)
                Text(month(date))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.Text.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func weekday(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }

    private func month(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }

    // MARK: - Events

    @ViewBuilder
    private var events: some View {
        if !glance.canReadEvents {
            Button { Task { await glance.requestAccess() } } label: {
                Text("Show my events")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(PressScaleButtonStyle())
            .help("Allow calendar access")
        } else if glance.dayEvents.isEmpty {
            Text("No events")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Text.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(glance.dayEvents.prefix(Self.maxRows)) { event in
                    row(event)
                }
                if glance.dayEvents.count > Self.maxRows {
                    Text("+\(glance.dayEvents.count - Self.maxRows) more")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.Text.tertiary)
                        .padding(.leading, 11)
                }
            }
        }
    }

    private func row(_ event: CalendarGlance.DayEvent) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(event.color.map { Color(cgColor: $0) } ?? Theme.Text.secondary)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.Text.primary)
                    .lineLimit(1)
                Text(event.time)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.Text.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
