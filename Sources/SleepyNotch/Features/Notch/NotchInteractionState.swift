import Foundation

/// The notch's view-local interaction state: hover, the card's content
/// fade, an in-progress file drag, and which card tab is showing.
final class NotchInteractionState: ObservableObject {
    @Published var isHovered = false
    @Published var contentVisible = false
    /// A file is being dragged over the notch.
    @Published var isDropTargeted = false
    @Published var tab: CardTab = .music
    /// The pending collapse after the cursor leaves, cancelled if it returns.
    var collapseWorkItem: DispatchWorkItem?
}
