import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowManager: NotchWindowController?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize Notch Window Manager
        self.windowManager = NotchWindowController.shared
        
        // Setup Menu Bar Item
        setupStatusBar()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "waveform.badge.magnifyingglass",
                accessibilityDescription: "Notch Music"
            ) ?? NSImage(
                systemSymbolName: "music.note",
                accessibilityDescription: "Notch Music"
            )
        }
        
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(
            title: "Toggle Notch HUD",
            action: #selector(toggleHUD),
            keyEquivalent: "n"
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        let demoItem = NSMenuItem(
            title: "Toggle Demo Mode",
            action: #selector(toggleDemo),
            keyEquivalent: "d"
        )
        demoItem.target = self
        menu.addItem(demoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let playItem = NSMenuItem(
            title: "Play / Pause",
            action: #selector(playPause),
            keyEquivalent: " "
        )
        playItem.target = self
        menu.addItem(playItem)
        
        let nextItem = NSMenuItem(
            title: "Next Track",
            action: #selector(nextTrack),
            keyEquivalent: "]"
        )
        nextItem.target = self
        menu.addItem(nextItem)
        
        let prevItem = NSMenuItem(
            title: "Previous Track",
            action: #selector(prevTrack),
            keyEquivalent: "["
        )
        prevItem.target = self
        menu.addItem(prevItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Automation access is required to control Music/Spotify at all. When
        // it's denied, this is the discoverable way to fix it — the HUD itself
        // only shows a small badge while expanded.
        let automationItem = NSMenuItem(
            title: "Automation Access…",
            action: #selector(openAutomationSettings),
            keyEquivalent: ""
        )
        automationItem.target = self
        menu.addItem(automationItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "Quit Notch Music",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func toggleHUD() {
        windowManager?.toggleVisibility()
    }
    
    @objc private func toggleDemo() {
        PlaybackCoordinator.shared.toggleDemoMode()
    }
    
    @objc private func playPause() {
        PlaybackCoordinator.shared.togglePlayPause()
    }
    
    @objc private func nextTrack() {
        PlaybackCoordinator.shared.nextTrack()
    }
    
    @objc private func prevTrack() {
        PlaybackCoordinator.shared.previousTrack()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc private func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
