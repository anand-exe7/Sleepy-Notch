import SwiftUI

/// What the open card shows: the drop zone while a file is dragged over it,
/// the shelf tab, or the music player.
struct NotchCardContent: View {
    @ObservedObject var interaction: NotchInteractionState
    @ObservedObject var shelf: ShelfStore
    let media: PlaybackCoordinator
    let power: PowerStateMonitor
    let metrics: NotchMetrics
    let accentColor: Color

    var body: some View {
        if interaction.isDropTargeted {
            ShelfDropZone(existingCount: shelf.items.count)
                .frame(width: metrics.cardWidth, height: NotchMetrics.cardBodyHeight - 6)
                .padding(.top, metrics.notchHeight + 2)
        } else if interaction.tab == .shelf && !shelf.items.isEmpty {
            ShelfView(shelf: shelf, width: metrics.cardWidth)
                .padding(.top, metrics.notchHeight + 4)
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
        }
    }
}
