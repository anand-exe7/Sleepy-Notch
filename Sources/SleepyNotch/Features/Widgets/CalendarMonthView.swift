import SwiftUI

/// The month tile of the Calendar page.
///
/// Always six rows (the neighbouring months' days fill the ends, dimmed,
/// and take you there when clicked), so the tile never changes height.
/// Today is a red circle, as in Calendar; the picked day a soft one that
/// glides to each click; weekends are a shade dimmer; a day with events
/// carries a dot in each of its calendars' colours (up to three). Turning
/// the month slides the grid the way you went. Nothing ticks.
struct CalendarMonthView: View {
    @ObservedObject var glance: CalendarGlance
    /// The soft circle glides to the clicked day.
    @Namespace private var selection

    static let cellWidth: CGFloat = 31
    static let cellHeight: CGFloat = 20
    static var width: CGFloat { cellWidth * 7 }
    private static let dot: CGFloat = 19

    var body: some View {
        let weekend = glance.weekendColumns
        VStack(spacing: 2) {
            header
                .frame(height: 22)
                .padding(.bottom, 2)

            HStack(spacing: 0) {
                ForEach(Array(glance.weekdayInitials.enumerated()), id: \.offset) { column, letter in
                    Text(letter)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Theme.Text.tertiary.opacity(weekend.contains(column) ? 0.75 : 1))
                        .frame(width: Self.cellWidth, height: 14)
                }
            }

            grid(weekend: weekend)
                .id(glance.monthOffset)
                .transition(slide)
        }
        .frame(width: Self.width)
        .clipped()
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: glance.monthOffset)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: glance.selectedDay)
    }

    /// The new month comes in from the side you went towards.
    private var slide: AnyTransition {
        let shift: CGFloat = glance.lastStep >= 0 ? 28 : -28
        return .asymmetric(
            insertion: .offset(x: shift).combined(with: .opacity),
            removal: .offset(x: -shift).combined(with: .opacity)
        )
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: glance.showToday) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(glance.monthName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.Text.primary)
                    Text(glance.yearText)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Theme.Text.tertiary)
                }
                .lineLimit(1)
                .id(glance.monthOffset)
                .transition(.opacity)
            }
            .buttonStyle(.plain)
            .help("Back to today")
            .padding(.leading, 5)
            Spacer(minLength: 4)
            arrow("chevron.left", label: "Previous month") { glance.step(-1) }
            arrow("chevron.right", label: "Next month") { glance.step(1) }
        }
    }

    private func grid(weekend: Set<Int>) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(glance.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { column, cell in
                        dayCell(cell, weekend: weekend.contains(column))
                    }
                }
            }
        }
    }

    private func dayCell(_ cell: CalendarGlance.Cell, weekend: Bool) -> some View {
        let inMonth = cell.month == 0
        let isToday = inMonth && cell.day == glance.today
        let isSelected = inMonth && cell.day == glance.selectedDay
        let colors = inMonth ? glance.eventColors[cell.day] ?? [] : []
        return Button { glance.select(cell) } label: {
            ZStack {
                if isSelected && !isToday {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: Self.dot, height: Self.dot)
                        .matchedGeometryEffect(id: "selected", in: selection)
                }
                if isToday {
                    Circle()
                        .fill(Color(nsColor: .systemRed))
                        .frame(width: Self.dot, height: Self.dot)
                        .overlay {
                            // The soft circle glides here too when today is picked.
                            if isSelected {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                                    .padding(-2.5)
                                    .matchedGeometryEffect(id: "selected", in: selection)
                            }
                        }
                }
                Text("\(cell.day)")
                    .font(.system(size: 11, weight: isToday || isSelected ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundColor(color(inMonth: inMonth, isToday: isToday, isSelected: isSelected, weekend: weekend))
                if !colors.isEmpty {
                    HStack(spacing: 1.5) {
                        ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                            Circle()
                                .fill(isToday ? Color.white.opacity(0.95) : Color(cgColor: color))
                                .frame(width: 3, height: 3)
                        }
                    }
                    .offset(y: isToday ? 6 : 8.5)
                }
            }
            .frame(width: Self.cellWidth, height: Self.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("\(cell.day)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func color(inMonth: Bool, isToday: Bool, isSelected: Bool, weekend: Bool) -> Color {
        if !inMonth { return Color.white.opacity(0.22) }
        if isToday || isSelected { return Theme.Text.primary }
        return weekend ? Theme.Text.tertiary : Theme.Text.secondary
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.Text.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .padding(.leading, 4)
        .help(label)
        .accessibilityLabel(label)
    }
}
