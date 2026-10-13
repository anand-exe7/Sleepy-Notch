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
    @ObservedObject private var lab: LabSettings
    private let power: PowerStateMonitor
    @StateObject private var interaction = NotchInteractionState()

    init(
        windowController: NotchWindowController,
        media: PlaybackCoordinator,
        peeks: PeekCenter,
        shelf: ShelfStore,
        lab: LabSettings,
        power: PowerStateMonitor
    ) {
        self.windowController = windowController
        self.media = media
        self.peeks = peeks
        self.shelf = shelf
        self.lab = lab
        self.power = power
    }

    private var geometry: DisplayGeometry { windowController.geometry }
    private var metrics: NotchMetrics { geometry.metrics }

    /// Open while the cursor is on it (or a file is dragged over it), and
    /// closed as soon as it leaves. There's deliberately no click-to-pin: a
    /// stray click inside the card used to pin it open, and it then ignored
    /// the cursor leaving.
    private var isExpanded: Bool {
        interaction.isHovered || interaction.isDropTargeted
    }

    private var layout: NotchLayout {
        NotchLayout(geometry: geometry, isExpanded: isExpanded, peek: peeks.current?.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // ── The notch body ──
                // Pure black whether collapsed or open, with nothing drawn over
                // it — no glow, no tinted edge — so it reads as one piece with
                // the hardware cutout in its top edge.
                shape.fill(Theme.notchFill)

                // ── Content ──
                switch layout.mode {
                case .card:
                    if interaction.contentVisible {
                        // The card's rows run their own staggered entrance
                        // (see `RevealOnAppear`); the container settles in
                        // from slightly smaller, hanging from the notch.
                        NotchCardContent(
                            interaction: interaction,
                            shelf: shelf,
                            media: media,
                            power: power,
                            metrics: metrics,
                            artworkStyle: lab.artworkStyle,
                            accentColor: accentColor
                        )
                        .padding(.top, metrics.notchHeight + 6)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(scale: 0.92, anchor: .top))
                                    .animation(.spring(response: 0.42, dampingFraction: 0.8)),
                                removal: .opacity
                                    .combined(with: .scale(scale: 0.96, anchor: .top))
                                    .animation(.easeOut(duration: 0.1))
                            )
                        )

                        // Music / Shelf switch, once the shelf has files.
                        if !shelf.items.isEmpty && !interaction.isDropTargeted {
                            CardTabBar(interaction: interaction, shelfCount: shelf.items.count)
                                .padding(.leading, 18)
                                .frame(width: metrics.cardWidth, height: metrics.notchHeight, alignment: .leading)
                                .transition(.opacity)
                        }
                    }
                case .peek:
                    if let peek = peeks.current {
                        PeekView(
                            peek: peek,
                            media: media,
                            artworkStyle: lab.artworkStyle,
                            chargingStyle: lab.chargingStyle
                        )
                        .frame(width: layout.contentWidth, height: peek.content.contentHeight)
                        .padding(.top, geometry.collapsedSize.height)
                        .id(peek.id)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(scale: 0.94, anchor: .top))
                                    .animation(.easeOut(duration: 0.22).delay(0.1)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            )
                        )
                    }
                case .collapsed:
                    CompactNotchView(
                        media: media,
                        collapsedSize: layout.size,
                        isPhysicalNotch: geometry.presence == .physical,
                        artworkStyle: lab.artworkStyle,
                        accent: accentColor,
                        shelfCount: shelf.items.count
                    )
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .clipShape(shape)
            // ── ANIMATION: Multi-phase spring for organic stretch ──
            // The panel itself never resizes (see NotchMetrics), so these
            // springs are the only thing driving the expansion. Nothing can
            // clip the content mid-flight. Opening, the width leads and the
            // height follows with a little overshoot, so the card pops out of
            // the notch; closing is quicker and doesn't bounce.
            .animation(motion.width, value: layout.size.width)
            .animation(motion.height, value: layout.size.height)
            .animation(motion.corners, value: layout.bottomRadius)
            .animation(motion.corners, value: layout.topFlare)
            .onHover { hovering in
                handleHover(hovering)
            }
            // Clicking the collapsed notch opens it too, for when hover
            // doesn't (e.g. the cursor was already resting there).
            .onTapGesture {
                if !isExpanded { expand() }
            }
            #if DEBUG
            // Feature Lab: the file shelf. Dragging a file onto the notch
            // opens it into a drop zone.
            .onDrop(of: [UTType.fileURL], isTargeted: dropTargetBinding, perform: handleDrop)
            #endif
            // Keep the panel's interactive region in step with what's actually
            // drawn, so the oversized transparent panel never eats menu bar
            // clicks while collapsed or peeking.
            .onChange(of: isExpanded) { expanded in
                windowController.setCollapsed(!expanded)
                peeks.setHeld(expanded)
            }
            .onChange(of: shelf.items.isEmpty) { isEmpty in
                if isEmpty { interaction.tab = .music }
            }
            // Switching desktops doesn't always deliver a hover exit, which
            // could leave the card open on the new desktop.
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
                if isExpanded && !windowController.isCursorOverPanel() {
                    collapse()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var shape: NotchShape {
        NotchShape(
            bottomRadius: layout.bottomRadius,
            topFlare: layout.topFlare,
            roundsTopCorners: geometry.roundsTopCorners
        )
    }

    /// The springs for the shell, picked by direction: `layout.isOpen` is
    /// already the new state when SwiftUI asks for the animation.
    private var motion: (width: Animation, height: Animation, corners: Animation) {
        if layout.isOpen {
            return (
                .spring(response: 0.4, dampingFraction: 0.78, blendDuration: 0.08),
                .spring(response: 0.46, dampingFraction: 0.7, blendDuration: 0.08),
                .spring(response: 0.42, dampingFraction: 0.75)
            )
        }
        return (
            .spring(response: 0.32, dampingFraction: 0.92),
            .spring(response: 0.28, dampingFraction: 0.95),
            .spring(response: 0.26, dampingFraction: 0.95)
        )
    }

    // MARK: - Colour

    /// The accent for the controls (scrubber, waveform, progress ring).
    /// White by default, like the system's own Now Playing; the Lab can tint
    /// it with the album's colour instead.
    private var accentColor: Color {
        guard lab.albumTint,
              let artwork = media.currentTrack.artworkImage,
              let color = ArtworkPalette.tint(for: artwork)
        else { return Theme.controlTint }
        return Color(nsColor: color)
    }
    
    // MARK: - Interaction Handling

    private func expand() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
            interaction.isHovered = true
        }
        // Stagger: content arrives while the shell is still stretching, so
        // the two read as one motion — unless the cursor already left.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard interaction.isHovered else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                interaction.contentVisible = true
            }
        }
    }

    /// Quick and clean: the content goes first so nothing is seen shrinking
    /// with the shell, then the shell tucks back into the notch.
    private func collapse() {
        withAnimation(.easeOut(duration: 0.07)) {
            interaction.contentVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                interaction.isHovered = false
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        interaction.collapseWorkItem?.cancel()

        if hovering {
            expand()
        } else {
            let workItem = DispatchWorkItem {
                self.collapse()
            }
            interaction.collapseWorkItem = workItem
            // A short grace period so brushing past the edge doesn't snap
            // it shut, without feeling slow to close.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }
    }

    // MARK: - File Drop (Feature Lab)

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { interaction.isDropTargeted },
            set: { setDropTargeted($0) }
        )
    }

    private func setDropTargeted(_ targeted: Bool) {
        guard targeted != interaction.isDropTargeted else { return }
        interaction.collapseWorkItem?.cancel()
        if targeted {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
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
        let workItem = DispatchWorkItem {
            if !self.windowController.isCursorOverPanel() {
                self.collapse()
            }
        }
        interaction.collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
