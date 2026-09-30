import AppKit
import SwiftUI
import Combine

@MainActor
public final class NotchWindowController: NSObject, ObservableObject {
    public static let shared = NotchWindowController()
    
    private var window: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var screenChangeObserver: Any?
    
    // Cached notch geometry
    private var notchWidth: CGFloat = 179
    private var notchHeight: CGFloat = 32
    private var notchCenterX: CGFloat = 735.5
    private var screenMaxY: CGFloat = 956
    
    // Window sizing
    private let expandedExtraWidth: CGFloat = 220
    private let expandedHeight: CGFloat = 175
    
    public override init() {
        super.init()
        detectNotchGeometry()
        setupWindow()
        observeScreenChanges()
        observeExpansionState()
    }
    
    // MARK: - Notch Geometry Detection
    
    private func detectNotchGeometry() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        
        if #available(macOS 12.0, *),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           left.width > 0, right.width > 0 {
            notchWidth = right.minX - left.maxX
            notchHeight = screen.frame.maxY - left.minY
            notchCenterX = left.maxX + notchWidth / 2
            screenMaxY = screen.frame.maxY
        } else {
            // Fallback for screens without notch — use 13" defaults
            let screen = NSScreen.main ?? NSScreen.screens.first!
            notchWidth = 179
            notchHeight = 32
            notchCenterX = screen.frame.width / 2
            screenMaxY = screen.frame.maxY
        }
    }
    
    // MARK: - Window Setup
    
    private func setupWindow() {
        // Start with compact dimensions exactly overlaying the notch
        let compactWindowWidth = notchWidth + 2 // tiny padding for hover detection
        let windowHeight = expandedHeight // allocate max height, content clips itself
        let x = notchCenterX - compactWindowWidth / 2
        let y = screenMaxY - windowHeight
        
        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: compactWindowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        
        let notchView = NotchView(
            notchWidth: notchWidth,
            notchHeight: notchHeight
        )
        
        let hostingView = NSHostingView(rootView: notchView)
        hostingView.frame = NSRect(x: 0, y: 0, width: compactWindowWidth, height: windowHeight)
        panel.contentView = hostingView
        
        panel.orderFrontRegardless()
        self.window = panel
        
        updateWindowFrame(isExpanded: false)
    }
    
    // MARK: - Dynamic Window Frame
    
    private func observeExpansionState() {
        PlaybackCoordinator.shared.$isExpanded
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in
                self?.updateWindowFrame(isExpanded: expanded)
            }
            .store(in: &cancellables)
    }
    
    private func updateWindowFrame(isExpanded: Bool) {
        guard let window = self.window else { return }
        
        let targetWidth: CGFloat
        let targetHeight: CGFloat
        
        if isExpanded {
            targetWidth = notchWidth + expandedExtraWidth
            targetHeight = expandedHeight
        } else {
            // Compact: exact notch width + tiny hover margin
            targetWidth = notchWidth + 6
            targetHeight = notchHeight + 4 // +4 for bottom hover detection
        }
        
        let x = notchCenterX - targetWidth / 2
        let y = screenMaxY - targetHeight
        
        let newFrame = NSRect(x: x, y: y, width: targetWidth, height: targetHeight)
        
        // Animate the window frame change for smooth transition
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }
    
    // MARK: - Screen Changes
    
    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenChange()
            }
        }
    }
    
    private func handleScreenChange() {
        detectNotchGeometry()
        
        let notchView = NotchView(
            notchWidth: notchWidth,
            notchHeight: notchHeight
        )
        window?.contentView = NSHostingView(rootView: notchView)
        updateWindowFrame(isExpanded: PlaybackCoordinator.shared.isExpanded)
    }
    
    public func toggleVisibility() {
        guard let window = self.window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}
