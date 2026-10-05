import SwiftUI

/// What the open card shows: the drop zone while a file is dragged over it,
/// the shelf tab, or the music player.
struct NotchCardContent: View {
    @ObservedObject var interaction: NotchInteractionState
    @ObservedObject var shelf: ShelfStore
    let media: PlaybackCoordinator
    let power: PowerStateMonitor
    let metrics: NotchMetrics
    let artworkStyle: ArtworkTransitionStyle
    let accentColor: Color

    var body: some View {
        if interaction.isDropTargeted {
            ShelfDropZone(existingCount: shelf.items.count)
                .frame(width: metrics.cardWidth, height: metrics.panelHeight - metrics.notchHeight - 2)
        } else if interaction.tab == .shelf && !shelf.items.isEmpty {
            ShelfView(shelf: shelf, width: metrics.cardWidth)
        } else {
            ExpandedPlayerView(
                media: media,
                power: power,
                metrics: metrics,
                artworkStyle: artworkStyle,
                accent: accentColor
            )
        }
    }
}
