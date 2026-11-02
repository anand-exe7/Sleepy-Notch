import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The HUD: the black shape that grows out of the notch, and what's in it —
/// nothing while collapsed, a peek when something happens, or the card on
/// hover. Sizes come from `NotchLayout`; this view owns the interaction.
struct NotchView: View {
    @ObservedObject private var windowController: NotchWindowController
    @ObservedObject private var media: PlaybackCoordinator
    @ObservedObject private var peeks: PeekCenter
    @ObservedObject private var shelf: ShelfStore
    @ObservedObject private var preferences: HUDPreferences
    @ObservedObject private var status: NotchStatus
    private let power: PowerStateMonitor
    @StateObject private var interaction = NotchInteractionState()

    init(
        windowController: NotchWindowController,
        media: PlaybackCoordinator,
        peeks: PeekCenter,
        shelf: ShelfStore,
        preferences: HUDPreferences,
        status: NotchStatus,
        power: PowerStateMonitor
    ) {
        self.windowController = windowController
        self.media = media
        self.peeks = peeks
        self.shelf = shelf
        self.preferences = preferences
        self.status = status
        self.power = power
    }

    private var geometry: DisplayGeometry { windowController.geometry }
    private var metrics: NotchMetrics { geometry.metrics }

    /// Open while the cursor is on it (or a file is dragged over it), and
    /// closed as soon as it leaves. There's deliberately no click-to-pin: a
    /// stray click inside the card would pin it open, and it would then
    /// ignore the cursor leaving.
    private var isExpanded: Bool {
        interaction.isHovered || interaction.isDropTargeted
    }

    private var layout: NotchLayout {
        NotchLayout(
            geometry: geometry,
            isExpanded: isExpanded,
            peek: peeks.current?.content,
            indicators: indicators,
            nowPlaying: showsNowPlaying
        )
    }

    /// Cover and bars beside the closed notch while a song plays.
    private var showsNowPlaying: Bool {
        preferences.nowPlayingWings
            && geometry.presence == .physical
            && media.currentTrack.isPlaying
            && !media.currentTrack.isPlaceholder
    }

    /// The live status, with the Settings switches applied.
    private var indicators: NotchIndicators {
        NotchIndicators(
            micInUse: preferences.privacyDots && status.micInUse,
            cameraInUse: preferences.privacyDots && status.cameraInUse,
            chargingLevel: preferences.chargingWing ? status.chargingLevel : nil
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ── The notch body ──
            // Liquid Glass or solid black (Settings). With glass, only the
            // open card's lower third is glass; the top, peeks and the
            // closed notch stay pure black, one piece with the cutout.
            NotchSurface(
                shape: shape,
                size: layout.size,
                cardSize: cardLayout.size,
                finish: preferences.finish,
                coversGlass: layout.mode != .card
            )

            // ── Content ──
            // Laid out in the full, fixed-size panel and *clipped* by the
            // growing shape, rather than placed inside it. A view inserted
            // into a frame that's still widening is positioned from that
            // frame's left edge, so the card's contents slid in sideways and
            // swung past the middle before settling. Here nothing they're
            // positioned against ever moves.
            content
                .frame(width: geometry.panelSize.width, height: geometry.panelSize.height, alignment: .top)
                // A path clip, not a mask: a mask renders the whole card
                // again as an image on every frame of the spring. (The clip
                // once let content escape for its first frames, when the card
                // was inserted on each open; it's built once now.)
                .clipShape(NotchClip(shape: shape, size: layout.size))
        }
        .frame(width: geometry.panelSize.width, height: geometry.panelSize.height, alignment: .top)
        // ── ANIMATION ──
        // The panel itself never resizes (see NotchMetrics), so this spring
        // is the only thing driving the expansion. One curve for the shape,
        // its mask and their position keeps everything centred under the
        // notch the whole way. Opening pops with a little overshoot; closing
        // is quicker and doesn't bounce.
        .animation(motion, value: layout)
        .contentShape(Rectangle())
        // Clicking the collapsed notch opens it too, for when hover
        // doesn't (e.g. the cursor was already resting there). The panel
        // only takes clicks inside the shape (see `NotchHitView`).
        .onTapGesture {
            if !isExpanded && peeks.current?.content.isInteractive != true { expand() }
        }
        // The file shelf: dragging a file onto the notch opens it into a
        // drop zone. With the shelf off it accepts nothing.
        .onDrop(of: preferences.shelf ? [UTType.fileURL] : [], isTargeted: dropTargetBinding, perform: handleDrop)
        // Hover comes from the panel, which tracks the pointer against the
        // exact rectangle drawn — the same one it takes clicks in.
        .onChange(of: windowController.isPointerInside) { inside in
            handleHover(inside)
        }
        // Keep the panel's interactive region in step with what's actually
        // drawn, so the oversized transparent panel never eats menu bar
        // clicks while collapsed or peeking.
        .onAppear {
            interaction.hitSize = layout.size
            windowController.setInteractiveSize(layout.size)
        }
        .onChange(of: layout.size) { size in
            updateHitArea(size)
        }
        .onChange(of: isExpanded) { expanded in
            peeks.setHeld(expanded)
        }
        .onChange(of: shelf.items.isEmpty) { isEmpty in
            if isEmpty { interaction.tab = .music }
        }
        // Switching desktops doesn't always deliver a hover exit, which
        // could leave the card open on the new desktop.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            if isExpanded && !windowController.isCursorOverHUD() {
                collapse()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// What's drawn inside the shape: nothing while collapsed, a peek when
    /// something happens, or the card on hover. Each piece sits at the top
    /// centre of the panel.
    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .top) {
            // The card is built once and stays loaded, hidden while closed,
            // and fades in and out by animating `contentVisible` rather than
            // by being inserted and removed. Opening has nothing to build —
            // building it on each open held the first frames of the spring
            // back — and opening again mid-close just turns the same motion
            // around. While hidden, its moving parts hold still
            // (`notchCardActive`), so it costs nothing.
            card
                .modifier(NotchContentReveal(hidden: !interaction.contentVisible))
                .environment(\.notchCardActive, interaction.contentVisible || layout.mode == .card)
                .allowsHitTesting(layout.mode == .card)
                .accessibilityHidden(layout.mode != .card)
            modeContent
        }
    }

    private var card: some View {
        ZStack(alignment: .top) {
            NotchCardContent(
                interaction: interaction,
                shelf: shelf,
                media: media,
                power: power,
                metrics: metrics,
                artworkStyle: preferences.artworkStyle,
                accentColor: accentColor
            )
            .padding(.top, metrics.notchHeight + 6)

            // Music / Shelf switch, once the shelf has files.
            if !shelf.items.isEmpty && !interaction.isDropTargeted {
                CardTabBar(interaction: interaction, shelfCount: shelf.items.count)
                    .padding(.leading, 18)
                    .frame(width: metrics.cardWidth, height: metrics.notchHeight, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch layout.mode {
        case .card:
            EmptyView()
        case .peek:
            if let peek = peeks.current {
                PeekView(
                    peek: peek,
                    media: media,
                    artworkStyle: preferences.artworkStyle,
                    dismiss: { peeks.dismissCurrent() }
                )
                .frame(width: layout.contentWidth, height: peek.content.contentHeight)
                .padding(.top, geometry.collapsedSize.height)
                .id(peek.id)
                .transition(
                    .asymmetric(
                        insertion: .meltOutOfNotch
                            .animation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.08)),
                        removal: .tuckIntoNotch.animation(.easeIn(duration: 0.16))
                    )
                )
            }
        case .collapsed:
            if geometry.presence == .physical && (!indicators.isEmpty || showsNowPlaying) {
                StatusWingsView(
                    indicators: indicators,
                    nowPlaying: showsNowPlaying,
                    media: media,
                    artworkStyle: preferences.artworkStyle,
                    accent: accentColor,
                    power: power,
                    notchWidth: metrics.notchWidth,
                    height: geometry.collapsedSize.height
                )
                // They arrive once the card has tucked away, and leave at once
                // when it opens, so they never sit over the card's header.
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
                    removal: .opacity.animation(.easeOut(duration: 0.06))
                ))
            }
            CompactNotchView(
                media: media,
                collapsedSize: layout.size,
                isPhysicalNotch: geometry.presence == .physical,
                artworkStyle: preferences.artworkStyle,
                accent: accentColor,
                shelfCount: shelf.items.count,
                indicators: indicators
            )
            .transition(.opacity.animation(.easeOut(duration: 0.15)))
        }
    }

    private var shape: NotchShape {
        layout.shape(roundsTopCorners: geometry.roundsTopCorners)
    }

    /// The open card, whatever is showing now: the glass is drawn at this
    /// size (see `NotchSurface`).
    private var cardLayout: NotchLayout {
        NotchLayout(geometry: geometry, isExpanded: true, peek: nil)
    }

    /// The spring for the shell, picked by direction: `layout.isOpen` is
    /// already the new state when SwiftUI asks for the animation. Both ways
    /// bounce, like the Dynamic Island: opening stretches past its size and
    /// settles back; closing tucks in with a softer bounce. Under the
    /// hardware notch the closing overshoot is out of sight.
    private var motion: Animation {
        guard layout.isOpen else { return Self.closeMotion }
        return interaction.reopening ? Self.reopenMotion : Self.openMotion
    }

    /// Turning a close around: stiffer, so it overcomes the shape's motion
    /// toward closed quickly instead of drifting back open.
    /// The content tucking away as the card closes: quick, no bounce.
    static let contentHideMotion = Animation.spring(response: 0.2, dampingFraction: 1)

    static let contentReturnMotion = Animation.spring(response: 0.42, dampingFraction: 0.9)

    static let reopenMotion = Animation.spring(response: 0.38, dampingFraction: 0.7, blendDuration: 0.05)

    static let openMotion = Animation.spring(response: 0.44, dampingFraction: 0.6, blendDuration: 0.1)
    static let closeMotion = Animation.spring(response: 0.44, dampingFraction: 0.76, blendDuration: 0.08)

    // MARK: - Colour

    /// The accent for the controls (scrubber, waveform, progress ring).
    /// White by default, like the system's own Now Playing; Settings can
    /// tint it with the album's colour instead.
    private var accentColor: Color {
        guard preferences.albumTint,
              let artwork = media.currentTrack.artworkImage,
              let color = ArtworkPalette.tint(for: artwork)
        else { return Theme.controlTint }
        return Color(nsColor: color)
    }
    
    // MARK: - Interaction Handling

    /// How long the pointer has to rest on the notch before it opens, so a
    /// cursor passing by on its way to the menu bar doesn't pop the card.
    /// Short enough not to feel like a wait; clicking opens it at once.
    private static let openDelay: TimeInterval = 0.04
    /// A short grace after the pointer leaves, so brushing past the edge
    /// doesn't snap it shut, without feeling slow to close.
    private static let closeDelay: TimeInterval = 0.12
    /// How long the close takes to look finished (see `closeMotion`).
    private static let closeDuration: TimeInterval = 0.5

    private func expand() {
        // The card is still on screen, on its way closed: the pointer came
        // back for it. Bring it all back at once — shape and content in one
        // stiff motion, with no waits. The usual staggered open lagged here:
        // the shrinking shape had to stop and turn around first, so the
        // bottom row (the play controls) came back well after the rest.
        let catchingClose = !interaction.contentVisible
            && (interaction.isClosing || interaction.isHovered)
        interaction.cancelPendingStep()
        if !interaction.isHovered {
            media.resyncPosition()
        }
        if catchingClose {
            interaction.reopening = true
            // Shape and content spring back together, picking up from
            // wherever the close has got to. Both run on springs, so they
            // reverse smoothly: a fixed-time fade-out couldn't be turned
            // around — animating against it left the card see-through,
            // and cutting it short showed full-size content cropped by the
            // still-small shape.
            withAnimation(Self.reopenMotion) {
                interaction.isHovered = true
            }
            // A touch softer than the shape, so the content trails it out of
            // the notch as in a fresh open, rather than the top row arriving
            // before there's room for the rest.
            withAnimation(Self.contentReturnMotion) {
                interaction.contentVisible = true
            }
            return
        }
        interaction.reopening = false
        withAnimation(Self.openMotion) {
            interaction.isHovered = true
        }
        guard !interaction.contentVisible else { return }
        // Stagger: content arrives while the shell is still stretching, so
        // the two read as one motion. Leaving before then cancels it.
        interaction.schedule(after: 0.07) {
            guard interaction.isHovered else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                interaction.contentVisible = true
            }
        }
    }

    /// One motion: the content tucks up into the notch (see
    /// `tuckIntoNotch`) while the shell closes around it a beat behind.
    private func collapse() {
        interaction.cancelPendingStep()
        // Decide before hiding anything: if the pointer is still on the card
        // (a hover change that didn't hold up), stay open with the content
        // untouched, rather than fading it out and bringing it back.
        if interaction.isDropTargeted || windowController.isCursorOverHUD() {
            return
        }
        // A spring rather than a fixed-time fade, so a quick return can
        // reverse it smoothly (see `expand`).
        withAnimation(Self.contentHideMotion) {
            interaction.contentVisible = false
        }
        interaction.schedule(after: 0.04) {
            // The pointer came back in the meantime: stay open. Without this
            // the card shut under the pointer, then reopened on the next move.
            if interaction.isDropTargeted || windowController.isCursorOverHUD() {
                expand()
                return
            }
            withAnimation(Self.closeMotion) {
                interaction.isHovered = false
            }
            interaction.closingUntil = Date().addingTimeInterval(Self.closeDuration)
        }
    }

    private func handleHover(_ hovering: Bool) {
        // A peek with a button holds still under the pointer rather than
        // giving way to the card, so the button can be clicked.
        if !isExpanded, peeks.current?.content.isInteractive == true {
            interaction.cancelPendingStep()
            peeks.setPointerOver(hovering)
            return
        }

        switch (hovering, isExpanded) {
        case (true, true):
            // Back on the card during the close grace: stay open, and bring
            // the content back if it had started to tuck away.
            interaction.cancelPendingStep()
            if !interaction.contentVisible { expand() }
        case (true, false):
            if interaction.isClosing {
                // Catching the card while it's still closing (the hover area
                // stays as big as what's drawn until it's shut): no "is it
                // resting here?" wait — it's plainly wanted back.
                expand()
            } else {
                interaction.schedule(after: Self.openDelay) {
                    if windowController.isPointerInside { expand() }
                }
            }
        case (false, true):
            interaction.schedule(after: Self.closeDelay) {
                collapse()
            }
        case (false, false):
            // Passed by before it opened.
            interaction.cancelPendingStep()
        }
    }

    /// Keeps the panel's hover and click area matching what's drawn.
    /// Growing takes effect at once. Shrinking waits until the shape has
    /// visibly finished closing: until then the pointer can move back onto
    /// the card it can still see and catch it, instead of finding a dead
    /// area that's already notch-sized.
    private func updateHitArea(_ size: CGSize) {
        interaction.hitShrinkWorkItem?.cancel()
        let current = interaction.hitSize
        let covering = CGSize(width: max(current.width, size.width), height: max(current.height, size.height))
        if covering != current {
            interaction.hitSize = covering
            windowController.setInteractiveSize(covering)
        }
        guard covering != size else { return }
        let shrink = DispatchWorkItem {
            interaction.hitSize = size
            windowController.setInteractiveSize(size)
        }
        interaction.hitShrinkWorkItem = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDuration, execute: shrink)
    }

    // MARK: - File Drop

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { interaction.isDropTargeted },
            set: { setDropTargeted($0) }
        )
    }

    private func setDropTargeted(_ targeted: Bool) {
        guard targeted != interaction.isDropTargeted else { return }
        interaction.cancelPendingStep()
        if targeted {
            withAnimation(Self.openMotion) {
                interaction.isDropTargeted = true
                interaction.contentVisible = true
            }
        } else {
            // The drag left or dropped. Hover events don't arrive during a
            // drag, so treat the card as hovered and let one check decide
            // whether the cursor is actually still on it.
            interaction.isHovered = true
            interaction.isDropTargeted = false
            collapseIfCursorLeft(after: 0.3)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        let shelf = shelf
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    shelf.add([url])
                }
            }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            interaction.tab = .shelf
        }
        return true
    }

    /// One check, not a loop: hover tracking takes over once the cursor moves.
    private func collapseIfCursorLeft(after delay: TimeInterval) {
        interaction.schedule(after: delay) {
            if !windowController.isCursorOverHUD() {
                collapse()
            }
        }
    }
}

