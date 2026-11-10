import AppKit
import SwiftUI

/// A hosting view that acts on the very first click. These panels never
/// become the active window, and without this a click would only be
/// swallowed as "activate the window".
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
