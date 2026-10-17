import SwiftUI

/// Everything a person can turn on, off, or pick in the HUD, grouped by
/// what they'd be looking for: music, the peeks that drop out of the notch,
/// and the little indicators that live beside it.
struct SettingsView: View {
    @ObservedObject var settings: LabSettings

    var body: some View {
        Form {
            Section {
                Picker("Album animation", selection: $settings.artworkStyle) {
                    ForEach(ArtworkTransitionStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle("Tint controls with the album's colour", isOn: $settings.albumTint)
                Toggle("Peek when the song changes", isOn: $settings.songChangePeek)
            } header: {
                Text("Now Playing")
            }

            Section {
                Toggle("Keyboard (Caps Lock, layout changes)", isOn: $settings.keyboardPeek)
                Toggle("Meeting reminders five minutes before", isOn: $settings.meetingReminders)
                Toggle("Copied to clipboard", isOn: $settings.copyPeek)
            } header: {
                Text("Peeks")
            } footer: {
                Text("Charging and headphone peeks are always on.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Camera and mic indicators", isOn: $settings.privacyDots)
                Toggle("Battery level while charging", isOn: $settings.chargingWing)
            } header: {
                Text("Beside the notch")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
}
