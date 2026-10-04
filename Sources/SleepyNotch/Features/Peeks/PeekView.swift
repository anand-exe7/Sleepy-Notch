import SwiftUI

/// The row that drops below the notch during a peek.
struct PeekView: View {
    let peek: Peek
    @ObservedObject var media: PlaybackCoordinator
    let artworkStyle: ArtworkTransitionStyle
    let chargingStyle: ChargingPeekStyle

    var body: some View {
        switch peek.content {
        case .track(let change):
            TrackPeekView(change: change, media: media, style: artworkStyle)
        case .power(let event):
            ChargingPeekView(event: event, style: chargingStyle)
        case .headphones(let event):
            HeadphonePeekView(event: event)
        }
    }
}
