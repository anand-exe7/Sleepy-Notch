import SwiftUI

/// The month on the big Widgets page: large enough to click a day. Today is
/// a white circle, the picked day a soft one, and days with events carry a
/// dot. Read once per open, month change or click; nothing ticks.
struct CalendarMonthView: View {
    @ObservedObject var glance: CalendarGlance
    /// The soft circle glides to the clicked day.
    @Namespace private var selection

    static let cellWidth: CGFloat = 31
    static let cellHeight: CGFloat = 24
    static var width: CGFloat { cellWidth * 7 }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Button(action: glance.showToday) {
                    Text(glance.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Text.primary)
                }
                .buttonStyle(.plain)
                .help("Back to today")
                Spacer(minLength: 0)
                arrow("chevron.left", label: "Previous month") { glance.step(-1) }
                arrow("chevron.right", label: "Next month") { glance.step(1) }
            }
            .frame(height: 24)

            HStack(spacing: 0) {
                ForEach(Array(glance.weekdayInitials.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.Text.tertiary)
                        .frame(width: Self.cellWidth, height: 15)
                }
            }

            ForEach(Array(glance.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cell(day)
                    }
                }
            }
        }
        .frame(width: Self.width)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: glance.selectedDay)
    }

    @ViewBuilder
    private func cell(_ day: Int?) -> some View {
        if let day {
            let isToday = day == glance.today
            let isSelected = day == glance.selectedDay
            Button { glance.select(day) } label: {
                ZStack {
                    if isToday {
                        Circle().fill(Color.white).frame(width: 21, height: 21)
                    } else if isSelected {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 21, height: 21)
                            .matchedGeometryEffect(id: "selected", in: selection)
                    }
                    Text("\(day)")
                        .font(.system(size: 11.5, weight: isToday || isSelected ? .bold : .medium))
                        .monospacedDigit()
                        .foregroundColor(isToday ? .black : (isSelected ? Theme.Text.primary : Theme.Text.secondary))
                    if glance.eventDays.contains(day) && !isToday {
                        Circle()
                            .fill(Theme.Text.primary)
                            .frame(width: 3, height: 3)
                            .offset(y: 9)
                    }
                }
                .frame(width: Self.cellWidth, height: Self.cellHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel("\(day)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Color.clear.frame(width: Self.cellWidth, height: Self.cellHeight)
        }
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.Text.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }
}
