import Foundation

/// The notch's view-local interaction state: hover, the card's content
/// fade, an in-progress file drag, and which card tab is showing.
///
/// View-local state across the app lives in small `ObservableObject`s like
/// this rather than `@State`, which this toolchain resolves to a macro whose
/// plugin ships only with Xcode.
final class NotchInteractionState: ObservableObject {
    @Published var isHovered = false
    @Published var contentVisible = false
    /// A file is being dragged over the notch.
    @Published var isDropTargeted = false
    @Published var tab: CardTab = .music
    /// The pending collapse after the cursor leaves, cancelled if it returns.
    var collapseWorkItem: DispatchWorkItem?
}
