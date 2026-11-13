import SwiftUI

/// What the open card shows: the drop zone while a file is dragged over it,
/// the shelf tab, the music player, or a small card when there's nothing
/// to show yet.
struct NotchCardContent: View {
    @ObservedObject var interaction: NotchInteractionState
    @ObservedObject var shelf: ShelfStore
    let media: PlaybackCoordinator
    let power: PowerStateMonitor
    let metrics: NotchMetrics
    let accentColor: Color
    /// The Widgets tab is switched on.
    let widgetsEnabled: Bool
    /// The Clipboard tab is switched on.
    let clipboardEnabled: Bool
    /// The Controls tab is switched on.
    let controlsEnabled: Bool
    @EnvironmentObject private var controlsService: ControlsService
    @EnvironmentObject private var stayAwake: StayAwakeService
    @EnvironmentObject private var pomodoro: PomodoroService
    @EnvironmentObject private var timers: TimerService
    @EnvironmentObject private var clipboardHistory: ClipboardHistory
    let startDemo: () -> Void
    let openSettings: () -> Void

    var body: some View {
        if interaction.isDropTargeted {
            ShelfDropZone(existingCount: shelf.items.count)
                .frame(width: metrics.cardWidth, height: NotchMetrics.cardBodyHeight - 6)
                .padding(.top, metrics.notchHeight + 2)
        } else if interaction.tab == .shelf && !shelf.items.isEmpty {
            ShelfView(shelf: shelf, width: metrics.cardWidth)
                .padding(.top, metrics.notchHeight + 4)
                .transition(.page(from: .trailing))
        } else if interaction.tab == .widgets && widgetsEnabled {
            CalendarPageView(width: metrics.widgetsWidth)
                .padding(.top, metrics.notchHeight + 6)
                // It arrives as the card finishes widening.
                .transition(.calendarGrow)
        } else if interaction.tab == .controls && controlsEnabled {
            ControlsView(controls: controlsService, stayAwake: stayAwake, pomodoro: pomodoro, timers: timers, width: metrics.cardWidth)
                .padding(.top, metrics.notchHeight + 2)
                .transition(.page(from: .trailing))
        } else if interaction.tab == .clipboard && clipboardEnabled {
            ClipboardHistoryView(history: clipboardHistory, width: metrics.cardWidth)
                .padding(.top, metrics.notchHeight + 6)
                .transition(.page(from: .trailing))
        } else if interaction.idleCard {
            IdleCardView(metrics: metrics, startDemo: startDemo, openSettings: openSettings)
                .transition(.page(from: .leading))
        } else {
            ExpandedPlayerView(
                media: media,
                power: power,
                metrics: metrics,
                accent: accentColor
            )
            // The cover and title sit clear below the notch.
            .padding(.top, metrics.notchHeight + ExpandedPlayerView.headerGap)
            .transition(.page(from: .leading))
        }
    }
}

extension AnyTransition {
    /// The big Widgets page: it comes in a beat after the card starts to
    /// widen, and goes at once when another page is picked.
    static var calendarGrow: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .top)
                .combined(with: .opacity)
                .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(0.14)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }


    /// Music and Shelf as two pages side by side: the shelf comes in from
    /// the right and the music slides away to the left, and back again. The
    /// page leaving fades out quickly and the new one follows a beat later,
    /// so the two never sit on top of each other.
    static func page(from edge: HorizontalEdge) -> AnyTransition {
        let shift: CGFloat = edge == .trailing ? 44 : -44
        let slide = AnyTransition.offset(x: shift).combined(with: .opacity)
        return .asymmetric(
            insertion: slide.animation(.spring(response: 0.42, dampingFraction: 0.88).delay(0.08)),
            removal: slide.animation(.easeOut(duration: 0.16))
        )
    }
}
