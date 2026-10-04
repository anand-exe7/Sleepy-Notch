import SwiftUI

/// The row that drops below the notch during a peek.
struct PeekView: View {
    let peek: Peek
    @ObservedObject var media: PlaybackCoordinator
    let artworkStyle: ArtworkTransitionStyle
    let chargingStyle: ChargingPeekStyle
    /// Glow colour picked from the current album art, if enabled.
    let albumColor: Color?

    var body: some View {
        switch peek.content {
        case .track(let change):
            TrackPeekView(
                change: change,
                media: media,
                style: artworkStyle,
                tint: Self.tint(for: peek.content, albumColor: albumColor)
            )
        case .power(let event):
            ChargingPeekView(event: event, style: chargingStyle)
        case .headphones(let event):
            HeadphonePeekView(event: event)
        }
    }

    /// The colour the notch glows while this peek is showing.
    static func tint(for content: PeekContent, albumColor: Color?) -> Color {
        switch content {
        case .track(let change):
            return albumColor ?? Theme.accent(for: change.current.source)
        case .power(let event):
            return ChargingPeekView.tint(for: event)
        case .headphones:
            return HeadphonePeekView.tint
        }
    }
}
