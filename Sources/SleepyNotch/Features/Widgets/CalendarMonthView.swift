import SwiftUI

/// The month tile of the Calendar page.
///
/// Always six rows (the neighbouring months' days fill the ends, dimmed,
/// and take you there when clicked), so the tile never changes height.
/// Today is a red circle, as in Calendar; the picked day a soft one that
/// glides to each click; weekends are a shade dimmer; a day with events
/// carries a dot in each of its calendars' colours (up to three). Turning
/// the month slides the grid the way you went. Nothing ticks.
///
/// Smoothness: the grid and names are worked out once per month (see
/// `CalendarGlance`), each day is an `Equatable` view so a click redraws
/// only the two days whose look changed, and the sliding grid is flattened
/// into one layer while it moves instead of fading 42 cells one by one.
struct CalendarMonthView: View {
    @ObservedObject var glance: CalendarGlance
    /// The soft circle glides to the clicked day.
    @Namespace private var selection

    static let cellWidth: CGFloat = 38
    static let cellHeight: CGFloat = 29
    static var width: CGFloat { cellWidth * 7 }
    static let dot: CGFloat = 25

    static let slideMotion = Animation.spring(response: 0.42, dampingFraction: 0.9)
    static let selectMotion = Animation.spring(response: 0.34, dampingFraction: 0.82)

    var body: some View {
        let weekend = glance.weekendColumns
        VStack(spacing: 2) {
            header
                .frame(height: 26)
                .padding(.bottom, 2)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { column in
                    Text(glance.weekdayInitials[column])
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(Theme.Text.tertiary.opacity(weekend.contains(column) ? 0.75 : 1))
                        .frame(width: Self.cellWidth, height: 16)
                }
            }

            ZStack {
                grid(weekend: weekend)
                    .id(glance.monthOffset)
                    .transition(slide)
            }
            .frame(height: 6 * Self.cellHeight + 5 * 2)
        }
        .frame(width: Self.width)
        .clipped()
        .animation(Self.slideMotion, value: glance.monthOffset)
        .animation(Self.selectMotion, value: glance.selectedDay)
    }

    /// The new month comes in from the side you went towards.
    private var slide: AnyTransition {
        let shift: CGFloat = glance.lastStep >= 0 ? 40 : -40
        return .asymmetric(
            insertion: .offset(x: shift).combined(with: .opacity),
            removal: .offset(x: -shift).combined(with: .opacity)
        )
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: glance.showToday) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(glance.monthName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Theme.Text.primary)
                    Text(glance.yearText)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Theme.Text.tertiary)
                }
                .lineLimit(1)
                .id(glance.monthOffset)
                .transition(.opacity)
            }
            .buttonStyle(.plain)
            .help("Back to today")
            .padding(.leading, 6)
            Spacer(minLength: 4)
            arrow("chevron.left", label: "Previous month") { glance.step(-1) }
            arrow("chevron.right", label: "Next month") { glance.step(1) }
        }
    }

    private func grid(weekend: Set<Int>) -> some View {
        let today = glance.today
        let selected = glance.selectedDay
        return VStack(spacing: 2) {
            ForEach(0..<glance.weeks.count, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let cell = glance.weeks[row][column]
                        let inMonth = cell.month == 0
                        CalendarDayCell(
                            cell: cell,
                            isToday: inMonth && cell.day == today,
                            isSelected: inMonth && cell.day == selected,
                            isWeekend: weekend.contains(column),
                            colors: inMonth ? glance.eventColors[cell.day] ?? [] : [],
                            selection: selection,
                            action: { [glance] in glance.select(cell) }
                        )
                        .equatable()
                    }
                }
            }
        }
        // One layer while it slides and fades, not 42.
        .compositingGroup()
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.Text.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .padding(.leading, 5)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// One day of the month grid. Equatable on what it shows, so SwiftUI skips
/// the days whose look didn't change.
private struct CalendarDayCell: View, Equatable {
    let cell: CalendarGlance.Cell
    let isToday: Bool
    let isSelected: Bool
    let isWeekend: Bool
    let colors: [CGColor]
    let selection: Namespace.ID
    let action: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cell == rhs.cell && lhs.isToday == rhs.isToday && lhs.isSelected == rhs.isSelected
            && lhs.isWeekend == rhs.isWeekend && lhs.colors == rhs.colors && lhs.selection == rhs.selection
    }

    var body: some View {
        let inMonth = cell.month == 0
        let dot = CalendarMonthView.dot
        Button(action: action) {
            ZStack {
                if isSelected && !isToday {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: dot, height: dot)
                        .matchedGeometryEffect(id: "selected", in: selection)
                }
                if isToday {
                    Circle()
                        .fill(Color(nsColor: .systemRed))
                        .frame(width: dot, height: dot)
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
                    .font(.system(size: 13, weight: isToday || isSelected ? .semibold : .medium))
                    .monospacedDigit()
                    .foregroundColor(textColor(inMonth: inMonth))
                if !colors.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(0..<colors.count, id: \.self) { index in
                            Circle()
                                .fill(isToday ? Color.white.opacity(0.95) : Color(cgColor: colors[index]))
                                .frame(width: 3.5, height: 3.5)
                        }
                    }
                    .offset(y: isToday ? 8 : 11.5)
                    .transition(.opacity)
                }
            }
            .frame(width: CalendarMonthView.cellWidth, height: CalendarMonthView.cellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("\(cell.day)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func textColor(inMonth: Bool) -> Color {
        if !inMonth { return Color.white.opacity(0.22) }
        if isToday || isSelected { return Theme.Text.primary }
        return isWeekend ? Theme.Text.tertiary : Theme.Text.secondary
    }
}
