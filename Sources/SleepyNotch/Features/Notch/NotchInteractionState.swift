import Foundation
import CoreGraphics

/// The notch's view-local interaction state: hover, the card's content
/// fade, an in-progress file drag, and which card tab is showing.
///
/// View-local state across the app lives in small `ObservableObject`s like
/// this rather than `@State`, which this toolchain resolves to a macro whose
/// plugin ships only with Xcode.
final class NotchInteractionState: ObservableObject {
    @Published var isHovered = false
    @Published var contentVisible = false
    /// Until when the card is still visibly closing: coming back before
    /// then catches it (see `NotchView.expand`).
    var closingUntil = Date.distantPast
    var isClosing: Bool { Date() < closingUntil }
    /// The current open is catching a close mid-way; picks the stiffer
    /// spring. Not published: it's read when the open itself re-renders.
    var reopening = false
    /// Right after the card closes, the wings are held back so it closes
    /// straight into the bare notch; then they grow out of it (see
    /// `NotchView.collapse`).
    @Published var wingsHeld = false
    /// The wings are growing back out after a close; picks their spring.
    var wingsReturning = false
    var wingsReturnWorkItem: DispatchWorkItem?
    /// The bubbles beside the notch wait a beat longer than the wings, so
    /// they split off a notch that has already settled.
    @Published var bubblesHeld = false
    var bubblesReturnWorkItem: DispatchWorkItem?
    /// What each bubble showed last, kept so a bubble still shows it while
    /// it melts back into the notch.
    @Published var bubbleFaces: [NotchSide: BubbleFace] = [:]
    /// The layout mode at the last change, so the next one can tell a
    /// bubble or wing change (same mode) from opening or closing.
    var lastLayoutMode: NotchLayout.Mode = .collapsed
    /// The welcome is on screen (or just closed): the notch is drawn in
    /// glass whatever the finish (see `NotchSurface.forcesGlass`).
    @Published var welcomeGlass = false
    var welcomeGlassOff: DispatchWorkItem?
    /// A file is being dragged over the notch.
    @Published var isDropTargeted = false
    @Published var tab: CardTab = .music
    /// The card opened with nothing to show (no track, empty shelf), so it
    /// shows the idle card. Decided when it opens and cleared when a song
    /// arrives, so a song change that briefly reads as "no track" doesn't
    /// flash the idle card mid-skip.
    @Published var idleCard = false

    /// The one pending hover step: opening once the pointer has settled,
    /// showing the content, or closing after it leaves. Scheduling a step
    /// cancels the one before, so fast moves can't run steps out of order —
    /// content appearing in a closing card, or the card shutting under the
    /// pointer.
    private var pendingStep: DispatchWorkItem?

    func schedule(after delay: TimeInterval, _ step: @escaping () -> Void) {
        pendingStep?.cancel()
        let work = DispatchWorkItem(block: step)
        pendingStep = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelPendingStep() {
        pendingStep?.cancel()
        pendingStep = nil
    }

    /// The size the panel takes hover and clicks in, and a pending shrink of
    /// it (see `NotchView.updateHitArea`).
    var hitSize: CGSize = .zero
    /// The card shrank under the pointer (a page switch to a smaller page):
    /// the hover area keeps the larger size until the pointer leaves it, so
    /// switching pages never closes the card by itself.
    var hitHeldLarge = false
    var hitShrinkWorkItem: DispatchWorkItem?
}

import SwiftUI

extension EnvironmentValues {
    /// Whether the card is showing. The card stays loaded while closed, so
    /// opening has nothing to build; its moving parts (scrolling title,
    /// bars, progress) read this and hold still while it's hidden.
    var notchCardActive: Bool {
        get { self[NotchCardActiveKey.self] }
        set { self[NotchCardActiveKey.self] = newValue }
    }
}

private struct NotchCardActiveKey: EnvironmentKey {
    static let defaultValue = true
}
