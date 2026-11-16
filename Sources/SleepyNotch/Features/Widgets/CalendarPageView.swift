import SwiftUI

/// The Calendar button's page, opened big: two tiles side by side, like
/// the system's own widgets. The month on the left; the picked day on the
/// right with its events. Read once when it opens and on each click;
/// nothing ticks.
struct CalendarPageView: View {
    @EnvironmentObject private var glance: CalendarGlance
    @Environment(\.notchCardActive) private var cardActive
    let width: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            CalendarMonthView(glance: glance)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(CalendarTile())
            DayDetailView(glance: glance)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(CalendarTile())
        }
        .frame(height: Self.tileHeight)
        .padding(.horizontal, Self.sideInset)
        .frame(width: width, height: Self.contentHeight, alignment: .top)
        .onAppear { if cardActive { glance.connect() } }
        .onChange(of: cardActive) { active in
            if active { glance.connect() }
        }
    }

    /// Room for the page below the notch.
    static let contentHeight: CGFloat = NotchMetrics.widgetsBodyHeight - 10
    /// The tiles end clear of the card's rounded bottom corners.
    static let tileHeight: CGFloat = contentHeight - 14
    private static let sideInset: CGFloat = 22
    private static let gap: CGFloat = 10
}

/// A widget's soft rounded plate on the black card.
struct CalendarTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
    }
}
