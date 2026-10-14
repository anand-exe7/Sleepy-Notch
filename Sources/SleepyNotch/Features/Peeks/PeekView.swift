import SwiftUI

/// The row that drops below the notch during a peek.
struct PeekView: View {
    let peek: Peek
    @ObservedObject var media: PlaybackCoordinator
    let artworkStyle: ArtworkTransitionStyle
    let chargingStyle: ChargingPeekStyle
    /// Folds the peek up, for a peek with a button.
    let dismiss: () -> Void

    var body: some View {
        switch peek.content {
        case .track(let change):
            TrackPeekView(change: change, media: media, style: artworkStyle)
        case .power(let event):
            ChargingPeekView(event: event, style: chargingStyle)
        case .headphones(let event):
            HeadphonePeekView(event: event)
        case .keyboard(let event):
            KeyboardPeekView(event: event)
        case .meeting(let meeting):
            MeetingPeekView(meeting: meeting, dismiss: dismiss)
        case .copied(let preview):
            CopyPeekView(preview: preview)
        }
    }
}
