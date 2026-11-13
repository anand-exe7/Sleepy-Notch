import SwiftUI

/// Shrinks slightly while held, springing back on release. The press
/// feedback for every bare-glyph button in the HUD.
///
/// The whole frame takes the click: without a content shape only the
/// glyph's own pixels did, so a click between a symbol's strokes did
/// nothing.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
