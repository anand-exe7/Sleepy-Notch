import SwiftUI
import AppKit
import UniformTypeIdentifiers

public final class NotchInteractionState: ObservableObject {
    @Published public var isHovered: Bool = false
    @Published public var contentVisible: Bool = false
    /// A file is being dragged over the notch.
    @Published var isDropTargeted = false
    @Published var tab: CardTab = .music
    public var collapseWorkItem: DispatchWorkItem?

    public init() {}
}

struct NotchView: View {
    @ObservedObject var media: PlaybackCoordinator = PlaybackCoordinator.shared
    @ObservedObject private var windowController: NotchWindowController
    @ObservedObject private var peeks = PeekCenter.shared
    @ObservedObject private var shelf = ShelfStore.shared
    @ObservedObject private var lab = LabSettings.shared
    @StateObject private var interaction = NotchInteractionState()

    init(windowController: NotchWindowController) {
        self.windowController = windowController
    }

    private var geometry: DisplayGeometry { windowController.geometry }
    private var metrics: NotchMetrics { geometry.metrics }

    /// What the notch is showing. The card always wins over a peek: opening
    /// it holds peeks back (see `PeekCenter.setHeld`).
    private enum Mode: Equatable {
        case collapsed
        case peek
        case card
    }

    /// Open while the cursor is on it (or a file is dragged over it), and
    /// closed as soon as it leaves. There's deliberately no click-to-pin: a
    /// stray click inside the card used to pin it open, and it then ignored
    /// the cursor leaving.
    private var isExpanded: Bool {
        interaction.isHovered || interaction.isDropTargeted
    }

    private var mode: Mode {
        if isExpanded { return .card }
        if peeks.current != nil { return .peek }
        return .collapsed
    }

    private var isOpen: Bool { mode != .collapsed }

    private var peekSize: CGSize {
        let collapsed = geometry.collapsedSize
        return CGSize(
            width: min(metrics.panelWidth, max(collapsed.width, metrics.notchWidth + NotchMetrics.peekExtraWidth)),
            height: collapsed.height + (peeks.current?.content.contentHeight ?? 56)
        )
    }

    /// Wings beside the hardware notch while music plays (or the shelf holds
    /// files). A floating pill already has room, so it never needs them.
    private var showsWings: Bool {
        guard geometry.presence == .physical else { return false }
        let isPlaying = media.currentTrack.isPlaying && !media.currentTrack.isPlaceholder
        return isPlaying || !shelf.items.isEmpty
    }

    private var collapsedSize: CGSize {
        let base = geometry.collapsedSize
        guard showsWings else { return base }
        return CGSize(width: base.width + 2 * NotchMetrics.wingWidth, height: base.height)
    }

    private var currentSize: (width: CGFloat, height: CGFloat) {
        switch mode {
        case .card:
            let expanded = metrics.size(isExpanded: true)
            return (expanded.width, expanded.height)
        case .peek:
            return (peekSize.width, peekSize.height)
        case .collapsed:
            return (collapsedSize.width, collapsedSize.height)
        }
    }

    private var bottomCornerRadius: CGFloat {
        switch mode {
        case .card:
            return NotchMetrics.expandedBottomRadius
        case .peek:
            return NotchMetrics.peekBottomRadius
        case .collapsed:
            // A floating pill is fully rounded; a physical notch keeps the
            // small bottom-only radius that matches the hardware cutout.
            return geometry.roundsTopCorners
                ? geometry.collapsedSize.height / 2
                : NotchMetrics.collapsedBottomRadius
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // ── The notch body ──
                // Pure black whether collapsed or open, with nothing drawn over
                // it — no glow, no tinted edge — so it reads as one piece with
                // the hardware cutout in its top edge.
                NotchShape(bottomRadius: bottomCornerRadius, roundsTopCorners: geometry.roundsTopCorners)
                    .fill(Theme.notchFill)

                // ── Content ──
                switch mode {
                case .card:
                    if interaction.contentVisible {
                        // The card's rows run their own staggered entrance
                        // (see `RevealOnAppear`), so the container just fades.
                        cardContent
                            .padding(.top, metrics.notchHeight + 2)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.animation(.easeOut(duration: 0.15)),
                                    removal: .opacity.animation(.easeOut(duration: 0.12))
                                )
                            )

                        if showsTabBar {
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
                        .frame(width: peekSize.width, height: peek.content.contentHeight)
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
                        collapsedSize: collapsedSize,
                        notchWidth: metrics.notchWidth,
                        isPhysicalNotch: geometry.presence == .physical,
                        showsWings: showsWings,
                        artworkStyle: lab.artworkStyle,
                        accent: accentColor,
                        shelfCount: shelf.items.count
                    )
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
            }
            .frame(width: currentSize.width, height: currentSize.height)
            .clipShape(NotchShape(bottomRadius: bottomCornerRadius, roundsTopCorners: geometry.roundsTopCorners))
            // A soft, neutral shadow lifts the open card off light wallpapers.
            .shadow(
                color: isOpen ? Color.black.opacity(0.35) : .clear,
                radius: isOpen ? 14 : 0,
                y: isOpen ? 6 : 0
            )
            // ── ANIMATION: Multi-phase spring for organic stretch ──
            // The panel itself never resizes (see NotchMetrics), so these
            // springs are the only thing driving the expansion. Nothing can
            // clip the content mid-flight.
            .animation(
                .spring(response: 0.38, dampingFraction: 0.76, blendDuration: 0.08),
                value: currentSize.width
            )
            .animation(
                .spring(response: 0.42, dampingFraction: 0.74, blendDuration: 0.08),
                value: currentSize.height
            )
            .animation(
                .spring(response: 0.35, dampingFraction: 0.8),
                value: bottomCornerRadius
            )
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
            .onChange(of: showsWings) { wings in
                windowController.setCollapsedExtraWidth(wings ? 2 * NotchMetrics.wingWidth : 0)
            }
            .onAppear {
                windowController.setCollapsedExtraWidth(showsWings ? 2 * NotchMetrics.wingWidth : 0)
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

    // MARK: - Card

    @ViewBuilder private var cardContent: some View {
        if interaction.isDropTargeted {
            ShelfDropZone(existingCount: shelf.items.count)
                .frame(width: metrics.cardWidth, height: metrics.panelHeight - metrics.notchHeight - 2)
        } else if showsShelf {
            ShelfView(shelf: shelf, width: metrics.cardWidth)
        } else {
            ExpandedPlayerView(
                media: media,
                metrics: metrics,
                artworkStyle: lab.artworkStyle,
                accent: accentColor
            )
        }
    }

    private var showsShelf: Bool {
        interaction.tab == .shelf && !shelf.items.isEmpty
    }

    private var showsTabBar: Bool {
        !shelf.items.isEmpty && !interaction.isDropTargeted
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
        // Stagger: content fades in AFTER the shell finishes stretching —
        // unless the cursor already left in the meantime.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard interaction.isHovered else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                interaction.contentVisible = true
            }
        }
    }

    private func collapse() {
        withAnimation(.easeOut(duration: 0.1)) {
            interaction.contentVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
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
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    ShelfStore.shared.add([url])
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
