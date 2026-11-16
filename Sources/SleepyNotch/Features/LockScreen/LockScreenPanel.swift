import AppKit

/// The lock screen card's window. It never takes the keyboard (that stays
/// with the password field), except while the album art fills the screen:
/// then Esc, or any key, closes the art.
final class LockScreenPanel: NSPanel {
    var takesKeyboard = false
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { takesKeyboard }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        guard takesKeyboard, let onCancel else { return super.keyDown(with: event) }
        onCancel()
    }
}
