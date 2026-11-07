import SwiftUI

/// The Controls tab: a row of quick toggles, like Control Center's. A lit
/// circle is on.
struct ControlsView: View {
    @ObservedObject var controls: ControlsService
    @ObservedObject var stayAwake: StayAwakeService
    @Environment(\.notchCardActive) private var cardActive
    let width: CGFloat

    var body: some View {
        HStack(spacing: 14) {
            toggle("Dark Mode", symbol: "circle.lefthalf.filled", on: controls.darkMode) { controls.toggleDarkMode() }
            toggle("Mute", symbol: controls.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", on: controls.muted) { controls.toggleMute() }
            toggle("Stay Awake", symbol: "cup.and.saucer.fill", on: stayAwake.isOn) { stayAwake.toggle() }
            if let wifi = controls.wifiOn {
                toggle("Wi-Fi", symbol: wifi ? "wifi" : "wifi.slash", on: wifi) { controls.toggleWifi() }
            }
        }
        .frame(width: width, height: 96, alignment: .center)
        .onAppear { if cardActive { controls.refresh() } }
        .onChange(of: cardActive) { active in if active { controls.refresh() } }
    }

    private func toggle(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(on ? .black : Theme.Text.primary)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(on ? Color.white : Color.white.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleButtonStyle())
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(on ? Theme.Text.primary : Theme.Text.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(on ? "on" : "off")")
        .accessibilityAddTraits(.isButton)
    }
}
