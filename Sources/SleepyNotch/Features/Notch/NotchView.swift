import SwiftUI
import AppKit

public final class NotchInteractionState: ObservableObject {
    @Published public var isHovered: Bool = false
    @Published public var isPinned: Bool = false
    @Published public var contentVisible: Bool = false
    public var collapseWorkItem: DispatchWorkItem?
    
    public init() {}
}

struct NotchView: View {
    @ObservedObject var media: PlaybackCoordinator = PlaybackCoordinator.shared
    @ObservedObject private var windowController: NotchWindowController
    @StateObject private var interaction = NotchInteractionState()

    init(windowController: NotchWindowController = .shared) {
        self.windowController = windowController
    }

    private var geometry: DisplayGeometry { windowController.geometry }
    private var metrics: NotchMetrics { geometry.metrics }

    private var isExpanded: Bool {
        interaction.isHovered || interaction.isPinned || media.isExpanded
    }

    private var currentSize: (width: CGFloat, height: CGFloat) {
        let expanded = metrics.size(isExpanded: true)
        let collapsed = geometry.collapsedSize
        return isExpanded
            ? (expanded.width, expanded.height)
            : (collapsed.width, collapsed.height)
    }

    private var bottomCornerRadius: CGFloat {
        // A floating pill is fully rounded; a physical notch keeps the small
        // bottom-only radius that matches the hardware cutout.
        isExpanded
            ? NotchMetrics.expandedBottomRadius
            : geometry.roundsTopCorners
                ? geometry.collapsedSize.height / 2
                : NotchMetrics.collapsedBottomRadius
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // ── Layer 1: The notch body ──
                // True black, so the overlay is indistinguishable from the
                // display cutout it covers. Lifts slightly only once expanded.
                NotchShape(bottomRadius: bottomCornerRadius, roundsTopCorners: geometry.roundsTopCorners)
                    .fill(Theme.fill(isExpanded: isExpanded))
                    .animation(.easeInOut(duration: 0.22), value: isExpanded)
                
                // ── Layer 2: Ambient color glow behind the shape (expanded only) ──
                if isExpanded {
                    NotchShape(bottomRadius: bottomCornerRadius, roundsTopCorners: geometry.roundsTopCorners)
                        .fill(
                            RadialGradient(
                                colors: [accentColor.opacity(0.06), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 160
                            )
                        )
                        .transition(.opacity.animation(.easeIn(duration: 0.2)))
                }
                
                // ── Layer 3: Specular edge highlight (expanded only) ──
                if isExpanded {
                    NotchShape(bottomRadius: bottomCornerRadius, roundsTopCorners: geometry.roundsTopCorners)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .clear, location: 0.05),
                                    .init(color: accentColor.opacity(0.12), location: 0.25),
                                    .init(color: .white.opacity(0.06), location: 0.5),
                                    .init(color: accentColor.opacity(0.10), location: 0.75),
                                    .init(color: .white.opacity(0.08), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                        .transition(.opacity.animation(.easeIn(duration: 0.25).delay(0.1)))
                }
                
                // ── Layer 4: Content ──
                if isExpanded && interaction.contentVisible {
                    ExpandedPlayerView(media: media, metrics: metrics)
                        .padding(.top, metrics.notchHeight + 2)
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .combined(with: .scale(scale: 0.92, anchor: .top))
                                    .combined(with: .offset(y: -6)),
                                removal: .opacity.animation(.easeOut(duration: 0.12))
                            )
                        )
                } else if !isExpanded {
                    CompactNotchView(
                        media: media,
                        collapsedSize: geometry.collapsedSize,
                        isPhysicalNotch: geometry.presence == .physical
                    )
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
            }
            .frame(width: currentSize.width, height: currentSize.height)
            .clipShape(NotchShape(bottomRadius: bottomCornerRadius, roundsTopCorners: geometry.roundsTopCorners))
            // Shadow: only when expanded, with source-tinted color
            .shadow(
                color: isExpanded ? accentColor.opacity(0.15) : .clear,
                radius: isExpanded ? 25 : 0,
                y: isExpanded ? 8 : 0
            )
            .shadow(
                color: isExpanded ? Color.black.opacity(0.5) : .clear,
                radius: isExpanded ? 20 : 0,
                y: isExpanded ? 10 : 0
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
            .onTapGesture {
                togglePin()
            }
            // Keep the panel's interactive region in step with what's actually
            // drawn, so the oversized transparent panel never eats menu bar
            // clicks while collapsed.
            .onChange(of: isExpanded) { expanded in
                NotchWindowController.shared.setCollapsed(!expanded)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Accent color from source
    
    private var accentColor: Color {
        Theme.accent(for: media.currentTrack.source)
    }
    
    // MARK: - Interaction Handling
    
    private func expand() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
            interaction.isHovered = true
            media.setExpanded(true)
        }
        // Stagger: content fades in AFTER the shell finishes stretching
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
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
                media.setExpanded(false)
            }
        }
    }
    
    private func togglePin() {
        if interaction.isPinned {
            interaction.isPinned = false
            collapse()
        } else {
            interaction.isPinned = true
            expand()
        }
    }
    
    private func handleHover(_ hovering: Bool) {
        interaction.collapseWorkItem?.cancel()
        
        if hovering {
            expand()
        } else {
            let workItem = DispatchWorkItem {
                if !self.interaction.isPinned {
                    self.collapse()
                }
            }
            interaction.collapseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
        }
    }
}
