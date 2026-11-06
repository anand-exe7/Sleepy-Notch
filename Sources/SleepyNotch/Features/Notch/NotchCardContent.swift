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
        } else if media.currentTrack.isPlaceholder {
            IdleCardView(metrics: metrics, startDemo: startDemo, openSettings: openSettings)
                .transition(.page(from: .leading))
        } else {
            ExpandedPlayerView(
                media: media,
                power: power,
                metrics: metrics,
                accent: accentColor
            )
            // The cover rises beside the camera, like Droppy's, so the card
            // stays compact; the title starts just below the notch.
            .padding(.top, metrics.notchHeight - ExpandedPlayerView.coverRise)
            .transition(.page(from: .leading))
        }
    }
}

extension AnyTransition {
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
