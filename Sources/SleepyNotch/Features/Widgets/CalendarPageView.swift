import SwiftUI

/// The Calendar button's page, opened big: the month on the left, and the
/// picked day on the right with its events. Read once when it opens and on
/// each click; nothing ticks.
struct CalendarPageView: View {
    @EnvironmentObject private var glance: CalendarGlance
    @Environment(\.notchCardActive) private var cardActive
    let width: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            CalendarMonthView(glance: glance)
            DayDetailView(glance: glance)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 26)
        .frame(width: width, height: Self.contentHeight, alignment: .top)
        .onAppear { if cardActive { glance.refresh() } }
        .onChange(of: cardActive) { active in
            if active { glance.refresh() }
        }
    }

    /// Room for the page below the notch.
    static let contentHeight: CGFloat = NotchMetrics.widgetsBodyHeight - 10
}
