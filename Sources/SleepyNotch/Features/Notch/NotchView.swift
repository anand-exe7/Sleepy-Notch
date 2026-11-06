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
    @ObservedObject private var activities: ActivityManager
    private let power: PowerStateMonitor
    private let library: LibraryController
    private let openSettings: () -> Void
    @StateObject private var interaction = NotchInteractionState()

    init(
        windowController: NotchWindowController,
        media: PlaybackCoordinator,
        peeks: PeekCenter,
        shelf: ShelfStore,
        preferences: HUDPreferences,
        status: NotchStatus,
        activities: ActivityManager,
        power: PowerStateMonitor,
        library: LibraryController,
        openSettings: @escaping () -> Void
    ) {
        self.windowController = windowController
        self.media = media
        self.peeks = peeks
        self.shelf = shelf
        self.preferences = preferences
        self.status = status
        self.activities = activities
        self.power = power
        self.library = library
        self.openSettings = openSettings
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
            arrangement: arrangement,
            bubbleFaces: interaction.bubbleFaces,
            showsWings: !interaction.wingsHeld,
            showsBubbles: !interaction.bubblesHeld,
            peekSize: activityPeekSize
        )
    }

    /// An opened activity's size, fitted to what it shows (see
    /// `ActivityDetailView.size`). Other peeks keep their set sizes.
    private var activityPeekSize: CGSize? {
        if case .track(let change)? = peeks.current?.content {
            return CGSize(
                width: TrackPeekView.width(for: change, notchWidth: metrics.notchWidth),
                height: TrackPeekView.contentHeight
            )
        }
        guard case .activity(let kind)? = peeks.current?.content else { return nil }
        return ActivityDetailView.size(
            for: kind,
            activity: activities.activity(kind),
            riding: ActivityDetailView.riding(on: kind, in: activities)
        )
    }

    /// What the notch shows in its wings and its bubbles, from the activity
    /// manager. Beside a physical notch only; a pill shows status inside.
    private var arrangement: IslandArrangement {
        geometry.presence == .physical ? activities.arrangement : .empty
    }

    /// Cover and bars beside the closed notch whenever there's a song,
    /// playing or paused (paused, the bars hold still). Nothing at all when
    /// no song is loaded.
    private var showsNowPlaying: Bool {
        arrangement.primary == .music
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
            // Glass or solid black (Settings). With glass, the card and peeks
            // are black on top and glass along the bottom; the closed notch
            // stays pure black, one piece with the cutout.
            NotchSurface(
                shape: shape,
                size: layout.size,
                minHeight: geometry.collapsedSize.height,
                panelSize: geometry.panelSize,
                finish: preferences.finish,
                coversGlass: layout.mode == .collapsed,
                glassFrom: layout.mode == .peek && peeks.current?.content == .welcome
                    ? WelcomePeekView.glassFrom
                    : NotchSurface.blendStart,
                forcesGlass: interaction.welcomeGlass
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
                .clipShape(NotchClip(shape: shape, size: layout.size, minHeight: geometry.collapsedSize.height))
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
            guard !isExpanded, peeks.current?.content.isInteractive != true else { return }
            // No song: the notch's own activity (the charge, the mic) opens
            // instead of the music card.
            if let kind = arrangement.primary, kind != .music, media.currentTrack.isPlaceholder, shelf.items.isEmpty {
                activities.expand(kind)
            } else {
                expand()
            }
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
            // A peek folding away closes like the card: into the notch, then
            // the wings split back out.
            peeks.willDismiss = { [interaction] in
                Self.holdWingsThenSplit(interaction)
            }
            rememberBubbleFaces(arrangement)
            if peeks.welcomePending { welcomeGateChanged(true) }
            windowController.setBubbleRects(layout.bubbleRects(panelWidth: geometry.panelSize.width))
            // The welcome is always glass. With the Black finish the glass is
            // switched on first, while the notch is still closed and black
            // either way, so the notch then springs open in glass from the start.
            peeks.willShow = { [interaction, preferences, peeks] content in
                guard content == .welcome, preferences.finish != .glass else { return 0 }
                interaction.welcomeGlassOff?.cancel()
                interaction.welcomeGlass = true
                // If something else took the notch instead, switch it back.
                Self.welcomeGlassOff(interaction, after: 1.5) {
                    peeks.current?.content != .welcome
                }
                return Self.welcomeGlassLead
            }
        }
        .onChange(of: arrangement) { rememberBubbleFaces($0) }
        .onChange(of: layout.mode) { interaction.lastLayoutMode = $0 }
        .onChange(of: layout.bubbleRects(panelWidth: geometry.panelSize.width)) { rects in
            windowController.setBubbleRects(rects)
        }
        .onChange(of: layout.size) { size in
            updateHitArea(size)
        }
        .onChange(of: isExpanded) { expanded in
            peeks.setHeld(expanded)
        }
        .onChange(of: peeks.current?.content == .welcome) { showing in
            setWelcomeGlass(showing)
        }
        .onChange(of: media.currentTrack.isPlaceholder) { placeholder in
            if !placeholder { interaction.idleCard = false }
        }
        .onChange(of: shelf.items.isEmpty) { isEmpty in
            if isEmpty { interaction.tab = .music }
        }
        // The welcome goes first: until it has played, the wings and bubbles
        // wait inside the notch. It closing splits them out as usual; if it
        // never came, they split out once the wait is given up.
        .onChange(of: peeks.welcomePending) { welcomeGateChanged($0) }
        // Locked, asleep or switched away: the wings tuck into the notch
        // out of sight. Back again, they split out left and right, the same
        // entrance as after a close, instead of snapping into place.
        .onReceive(power.$isNotchVisible.removeDuplicates().dropFirst()) { visible in
            if visible {
                Self.holdWingsThenSplit(interaction, after: Self.unlockRevealDelay, holdingBubbles: true)
            } else {
                var hide = Transaction()
                hide.disablesAnimations = true
                withTransaction(hide) {
                    interaction.wingsReturnWorkItem?.cancel()
                    interaction.bubblesReturnWorkItem?.cancel()
                    interaction.wingsReturning = false
                    interaction.wingsHeld = true
                    interaction.bubblesHeld = true
                }
            }
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
            sharedNowPlaying
            if geometry.presence == .physical {
                bubbles
            }
        }
    }

    // MARK: - Bubbles

    /// The camera and mic, and the charge, in bubbles split off the notch
    /// while something else has it (see `NotchBubble`). Always in place, so
    /// the bubbles ride the shape's spring in and out.
    private var bubbles: some View {
        let width = geometry.panelSize.width
        return StatusBubbles(
            leading: layout.leadingBubble,
            trailing: layout.trailingBubble,
            leadingEdge: layout.bubbleAnchor(.leading, panelWidth: width),
            trailingEdge: layout.bubbleAnchor(.trailing, panelWidth: width),
            faces: interaction.bubbleFaces,
            showsVoiceWaves: preferences.voiceWaves && preferences.privacyDots,
            animates: power.allowsDecorativeMotion && power.isNotchVisible,
            onTap: { side in
                if let kind = arrangement.bubble(side)?.kind {
                    activities.expand(kind)
                }
            }
        )
        .frame(width: geometry.panelSize.width, height: geometry.panelSize.height, alignment: .topLeading)
    }

    /// Shut and settled with no song: the wings are (or are becoming) the
    /// charge or the privacy dots.
    private var handingOverWings: Bool {
        layout.mode == .collapsed && !interaction.wingsHeld && !interaction.isClosing
            && (!showsNowPlaying || arrangement.leadingStatus || arrangement.trailingStatus)
    }

    /// The welcome goes first: until it has played, the wings and bubbles
    /// wait inside the notch. It closing splits them out as usual (see
    /// `peeks.willDismiss`); if it never came, they split out once the wait
    /// is given up.
    private func welcomeGateChanged(_ pending: Bool) {
        if pending {
            guard !interaction.wingsHeld || !interaction.bubblesHeld else { return }
            var hide = Transaction()
            hide.disablesAnimations = true
            withTransaction(hide) {
                interaction.wingsReturnWorkItem?.cancel()
                interaction.bubblesReturnWorkItem?.cancel()
                interaction.wingsHeld = true
                interaction.bubblesHeld = true
            }
        } else if peeks.current?.content != .welcome {
            Self.holdWingsThenSplit(interaction, after: 0.1, holdingBubbles: true)
        }
    }

    /// Remembers what each bubble shows, so it keeps it while melting back.
    private func rememberBubbleFaces(_ arrangement: IslandArrangement) {
        for side in [NotchSide.leading, .trailing] {
            if let face = arrangement.bubble(side)?.face, interaction.bubbleFaces[side] != face {
                interaction.bubbleFaces[side] = face
            }
        }
    }

    // MARK: - Cover and bars, shared by the card and the wings

    /// The album cover and the playing bars, drawn once for both the open
    /// card and the closed notch's wings. Their place comes from `layout`,
    /// so the shell's spring carries them: closing, the cover shrinks into
    /// the left wing and the bars slide into the right one, like the Dynamic
    /// Island; opening, they fly back out. Where there's nowhere for them to
    /// land (no wings, a peek, the shelf tab) they fade on the way.
    private var sharedNowPlaying: some View {
        let panel = geometry.panelSize
        let midX = panel.width / 2
        let open = layout.mode == .card
        let showingMusic = open
            && !interaction.idleCard
            && !interaction.isDropTargeted
            && !(interaction.tab == .shelf && !shelf.items.isEmpty)
        let closedHeight = geometry.collapsedSize.height

        // The cover: full size in the card, small in the left wing.
        let coverSize = ExpandedPlayerView.coverSize
        let wingCover = StatusWingsView.coverSize(forHeight: closedHeight)
        let headerTop = metrics.notchHeight - ExpandedPlayerView.coverRise
        let coverInWing = layout.mode == .collapsed && showsNowPlaying && !interaction.wingsHeld && !arrangement.leadingStatus
        // Closed with no wing to land in (or before the wings grow back),
        // the cover tucks just inside the notch's edge, under the camera's
        // cutout where nothing shows, and slides out from there.
        let coverOrigin = open
            ? CGPoint(x: midX - metrics.cardWidth / 2 + ExpandedPlayerView.sideInset, y: headerTop)
            : CGPoint(
                x: coverInWing
                    ? midX - metrics.notchWidth / 2 - StatusWingsView.inset - wingCover
                    : midX - metrics.notchWidth / 2 + 4,
                y: (closedHeight - wingCover) / 2
            )
        let coverShown = open ? showingMusic : coverInWing

        // The bars: beside the title in the card, in the right wing closed.
        let bars = StatusWingsView.barsSize
        let barsInWing = layout.mode == .collapsed && showsNowPlaying && !interaction.wingsHeld && !arrangement.trailingStatus
        let barsOrigin = open
            ? CGPoint(
                x: midX + metrics.cardWidth / 2 - ExpandedPlayerView.sideInset - bars.width,
                y: headerTop + ExpandedPlayerView.titleMidY - bars.height / 2
            )
            : CGPoint(
                x: barsInWing
                    ? midX + metrics.notchWidth / 2 + StatusWingsView.inset + 2
                    : midX + metrics.notchWidth / 2 - bars.width - 4,
                y: (closedHeight - bars.height) / 2
            )
        let barsShown = open ? showingMusic && media.lastError == nil : barsInWing

        let track = media.currentTrack
        let playing = track.isPlaying && !track.isPlaceholder
        // On the shelf page they slide away with the music, to the left.
        let pageSlide: CGFloat = open && !showingMusic && !interaction.isDropTargeted ? -44 : 0

        return ZStack(alignment: .topLeading) {
            ArtworkTransitionContainer(
                key: track.identityKey,
                style: preferences.artworkStyle,
                size: coverSize,
                cornerRadius: ExpandedPlayerView.coverRadius
            ) {
                CoverArtView(
                    image: track.artworkImage,
                    size: coverSize,
                    cornerRadius: ExpandedPlayerView.coverRadius,
                    placeholderIcon: track.source.iconName
                )
            }
            // Sits back a little while paused, like Music's own player.
            .scaleEffect(playing || track.isPlaceholder || !open ? 1 : 0.88)
            .animation(.spring(response: 0.45, dampingFraction: 0.62), value: playing)
            .scaleEffect(open ? 1 : wingCover / coverSize, anchor: .topLeading)
            // Down and across as two separate moves, so when the wings'
            // bouncy spring takes over mid-close (only sideways), the cover
            // keeps the close's calm vertical motion instead of picking up
            // its upward speed and overshooting above the notch.
            .offset(y: coverOrigin.y)
            .offset(x: coverOrigin.x + pageSlide)
            .opacity(coverShown ? (playing || track.isPlaceholder || !open ? 1 : 0.8) : 0)

            EqualizerBars(
                isPlaying: playing,
                animates: power.allowsDecorativeMotion && power.isNotchVisible && barsShown,
                color: accentColor,
                framesPerSecond: open ? 30 : 20
            )
            .frame(width: bars.width, height: bars.height)
            .offset(y: barsOrigin.y)
            .offset(x: barsOrigin.x + pageSlide)
            .opacity(barsShown ? 1 : 0)
        }
        // The song went away while the notch sat shut: cover and bars leave
        // quickly, so the charge can take their place without overlapping.
        .transaction { transaction in
            if handingOverWings { transaction.animation = .easeOut(duration: 0.1) }
        }
        .frame(width: panel.width, height: panel.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var card: some View {
        ZStack(alignment: .top) {
            NotchCardContent(
                interaction: interaction,
                shelf: shelf,
                media: media,
                power: power,
                library: library,
                metrics: metrics,
                accentColor: accentColor,
                startDemo: { media.toggleDemoMode() },
                openSettings: openSettings
            )

            // Music / Shelf switch, once the shelf has files: in the strip
            // right of the camera, since the cover sits to its left.
            if !shelf.items.isEmpty && !interaction.isDropTargeted {
                CardTabBar(interaction: interaction, shelfCount: shelf.items.count)
                    .padding(.trailing, 12)
                    .frame(width: metrics.cardWidth, height: metrics.notchHeight, alignment: .trailing)
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
                    activities: activities,
                    artworkStyle: preferences.artworkStyle,
                    dismiss: { peeks.dismissCurrent() }
                )
                .frame(width: layout.contentWidth, height: activityPeekSize?.height ?? peek.content.contentHeight)
                .padding(.top, geometry.collapsedSize.height)
                .id(peek.id)
                .transition(
                    .asymmetric(
                        // The welcome and the headphone card bring their own
                        // pieces in (see `HelloLettering`, `HeadphoneReveal`);
                        // a blur on the way in would soften them.
                        insertion: peek.content.revealsItself
                            ? .identity
                            : .meltOutOfNotch
                                .animation(.spring(response: 0.4, dampingFraction: 0.85).delay(0.08)),
                        // Fades where it is, without tucking upward: when the
                        // card takes over, the card's content drops into place
                        // and the peek moving up against it read as a bounce.
                        // Quick, so it's gone before the card's own cover
                        // and title arrive in nearly the same place.
                        removal: peekRemoval(peek.content)
                    )
                )
            }
        case .collapsed:
            if geometry.presence == .physical && !interaction.wingsHeld && arrangement.primary != nil {
                StatusWingsView(
                    indicators: indicators,
                    arrangement: arrangement,
                    animates: power.allowsDecorativeMotion && power.isNotchVisible,
                    media: media,
                    notchWidth: metrics.notchWidth,
                    height: geometry.collapsedSize.height
                )
                // Status arrives as the wings grow back out, and leaves at once
                // when the card opens, so it never sits over the card's header.
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.08)),
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

    /// How a peek leaves. One about an activity with a bubble shrinks
    /// toward that bubble's side as the notch closes into it, so the
    /// notification reads as becoming the bubble.
    private func peekRemoval(_ content: PeekContent) -> AnyTransition {
        let side = activities.style == .bubbles
            ? content.announces.flatMap { kind -> ActivitySlot? in
                let slot = activities.activity(kind)?.slot
                // Riding on the charge: it shrinks toward the charge.
                return slot == .attached ? activities.activity(.charging)?.slot : slot
            }
            : nil
        switch side {
        case .leading?, .trailing?:
            let anchor: UnitPoint = side == .leading ? .topLeading : .topTrailing
            return .opacity.combined(with: .scale(scale: 0.4, anchor: anchor))
                .animation(.easeOut(duration: 0.16))
        default:
            return .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                .animation(.easeOut(duration: 0.09))
        }
    }

    private var shape: NotchShape {
        layout.shape(roundsTopCorners: geometry.roundsTopCorners)
    }

    /// The spring for the shell, picked by direction: `layout.isOpen` is
    /// already the new state when SwiftUI asks for the animation. Like Droppy
    /// and the Dynamic Island: opening grows out of the notch, stretches past
    /// its size down and to the sides, and settles back smoothly; closing
    /// snaps quickly into the bare notch, then the wings pop back out with a
    /// bounce (see `collapse`).
    private var motion: Animation {
        if interaction.wingsReturning && !layout.isOpen { return Self.wingsMotion }
        // Neither opening nor closing: a bubble splitting off or melting
        // back, or the wings handing over.
        if layout.mode == interaction.lastLayoutMode && !interaction.isClosing { return Self.splitMotion }
        guard layout.isOpen else { return Self.closeMotion }
        return interaction.reopening ? Self.reopenMotion : Self.openMotion
    }

    /// The wings splitting back out of the notch after a close, left and
    /// right at once, like the Dynamic Island, with a lively bounce.
    static let wingsMotion = Animation.spring(response: 0.46, dampingFraction: 0.66, blendDuration: 0.08)
    /// A bubble splitting off the closed notch or melting back into it:
    /// unhurried enough to see the neck stretch and let go, with a soft
    /// bounce as the bubble lands.
    static let splitMotion = Animation.spring(response: 0.52, dampingFraction: 0.8, blendDuration: 0.08)
    /// After the wings are back out, the bubbles wait this long, then split
    /// off: a second, separate beat, like the Dynamic Island.
    private static let bubblesReturnDelay: TimeInterval = 0.32
    /// How long after the card starts closing the wings split out: just as
    /// the card reaches the notch, so the width turns around mid-motion — in
    /// to the middle, then straight back out to both sides — while the height
    /// finishes closing. One continuous move, with no pause in the notch.
    private static let wingsReturnDelay: TimeInterval = 0.2
    /// After unlocking (or the display waking), the wings wait for macOS's
    /// own unlock animation to finish, then split out of the bare notch.
    private static let unlockRevealDelay: TimeInterval = 0.5

    static let openMotion = Animation.spring(response: 0.55, dampingFraction: 0.64, blendDuration: 0.08)
    /// Unhurried and nearly bounce-free: the bounce comes as the wings split
    /// out.
    static let closeMotion = Animation.spring(response: 0.44, dampingFraction: 0.86, blendDuration: 0.08)
    /// Turning a close around: stiffer, so it overcomes the shape's motion
    /// toward closed quickly instead of drifting back open.
    static let reopenMotion = Animation.spring(response: 0.42, dampingFraction: 0.74, blendDuration: 0.08)

    /// The content coming out of the notch, alongside the shape.
    static let contentShowMotion = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// The content tucking away as the card closes: a touch quicker than the
    /// shape, so it's gone before the shape cuts into it.
    static let contentHideMotion = Animation.spring(response: 0.26, dampingFraction: 1)
    static let contentReturnMotion = Animation.spring(response: 0.4, dampingFraction: 0.84)

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
    private static let openDelay: TimeInterval = 0.1
    /// A short grace after the pointer leaves, so brushing past the edge
    /// doesn't snap it shut, without feeling slow to close.
    private static let closeDelay: TimeInterval = 0.12
    /// How long the close takes to look finished (see `closeMotion`).
    private static let closeDuration: TimeInterval = 0.45

    /// With no song and an empty shelf, the notch's own activity (Stay
    /// Awake, a timer, the charge, the mic) is what it's showing, and a
    /// click on it opens that activity. Hovering must not open the idle card
    /// over it, or the activity can never be reached.
    private var showsOpenableActivity: Bool {
        guard media.currentTrack.isPlaceholder, shelf.items.isEmpty,
              let kind = arrangement.primary else { return false }
        return kind != .music
    }

    private func expand() {
        if showsOpenableActivity { return }
        // No music anywhere: open on the shelf if it has files, otherwise on
        // the small idle card (see `IdleCardView`).
        if media.currentTrack.isPlaceholder && !shelf.items.isEmpty {
            interaction.tab = .shelf
        }
        if !interaction.isHovered {
            interaction.idleCard = media.currentTrack.isPlaceholder && shelf.items.isEmpty
        }
        // The card is still on screen, on its way closed: the pointer came
        // back for it. Bring it all back at once — shape and content in one
        // stiff motion, with no waits. The usual staggered open lagged here:
        // the shrinking shape had to stop and turn around first, so the
        // bottom row (the play controls) came back well after the rest.
        let catchingClose = !interaction.contentVisible
            && (interaction.isClosing || interaction.isHovered)
        interaction.cancelPendingStep()
        interaction.wingsReturnWorkItem?.cancel()
        interaction.bubblesReturnWorkItem?.cancel()
        interaction.wingsReturning = false
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
        // Shape and content in one motion: the content grows out of the
        // notch as the shape opens, rather than a beat behind it.
        withAnimation(Self.contentShowMotion) {
            interaction.contentVisible = true
        }
    }

    /// One motion: the content tucks up into the notch while the shape
    /// closes around it, straight into the bare notch. Then, as a second
    /// beat, the wings (cover and bars, or status) grow back out of it, left
    /// and right at once, like the Dynamic Island.
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
        Self.holdWingsThenSplit(interaction)
        withAnimation(Self.closeMotion) {
            interaction.isHovered = false
        }
        interaction.closingUntil = Date().addingTimeInterval(Self.closeDuration)
    }

    /// The second beat of every close — the card's and a peek's alike: the
    /// wings are held back so the shape closes into the bare notch, then
    /// split back out of it, left and right at once.
    static func holdWingsThenSplit(
        _ interaction: NotchInteractionState,
        after delay: TimeInterval = wingsReturnDelay,
        holdingBubbles: Bool = false
    ) {
        interaction.wingsReturnWorkItem?.cancel()
        interaction.bubblesReturnWorkItem?.cancel()
        interaction.wingsReturning = false
        interaction.wingsHeld = true
        // The bubbles stay out through a close, riding the notch's sides;
        // only after the notch was hidden (locked, asleep) do they wait.
        if holdingBubbles { interaction.bubblesHeld = true }
        let returnWings = DispatchWorkItem { [interaction] in
            guard !interaction.isHovered, !interaction.isDropTargeted else { return }
            interaction.wingsReturning = true
            withAnimation(Self.wingsMotion) {
                interaction.wingsHeld = false
            }
            // Then any held bubbles split off the settled notch, on their
            // own spring.
            let returnBubbles = DispatchWorkItem { [interaction] in
                interaction.wingsReturning = false
                guard interaction.bubblesHeld else { return }
                withAnimation(Self.splitMotion) {
                    interaction.bubblesHeld = false
                }
            }
            interaction.bubblesReturnWorkItem = returnBubbles
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.bubblesReturnDelay, execute: returnBubbles)
        }
        interaction.wingsReturnWorkItem = returnWings
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: returnWings)
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

    /// Keeps the panel's hover and click area matching what's drawn, both
    /// ways at once. (Shrinking used to wait for the close to finish, so the
    /// card could be caught on its way shut — but then a pointer heading
    /// back anywhere near the notch landed in the still card-sized area and
    /// reopened it.) The card is caught only by coming back onto the notch
    /// itself.
    private func updateHitArea(_ size: CGSize) {
        interaction.hitShrinkWorkItem?.cancel()
        interaction.hitShrinkWorkItem = nil
        guard size != interaction.hitSize else { return }
        interaction.hitSize = size
        windowController.setInteractiveSize(size)
    }

    /// How long the glass gets to appear before the welcome opens.
    private static let welcomeGlassLead: TimeInterval = 0.08

    /// The welcome closed: back to the chosen finish once the close has
    /// finished and the notch is solid black again.
    private func setWelcomeGlass(_ showing: Bool) {
        guard !showing else { return }
        Self.welcomeGlassOff(interaction, after: Self.closeDuration + 0.3) { true }
    }

    private static func welcomeGlassOff(
        _ interaction: NotchInteractionState,
        after delay: TimeInterval,
        if condition: @escaping () -> Bool
    ) {
        interaction.welcomeGlassOff?.cancel()
        let off = DispatchWorkItem { [interaction] in
            if condition() { interaction.welcomeGlass = false }
        }
        interaction.welcomeGlassOff = off
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: off)
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
        withAnimation(CardTabBar.motion) {
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

