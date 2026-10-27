import SwiftUI

/// Which pane is showing. A small object rather than view state, and
/// remembered between launches the way System Settings reopens where you
/// left it.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane? {
        didSet { UserDefaults.standard.set(pane?.rawValue, forKey: Self.key) }
    }

    private static let key = "settings.lastPane"

    init() {
        pane = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(SettingsPane.init(rawValue:)) ?? .general
    }
}

/// The Settings window, built like System Settings: a sidebar of coloured
/// icons on the left, and on the right a grouped form that opens with a box
/// describing the pane.
struct SettingsView: View {
    @ObservedObject var preferences: HUDPreferences
    @ObservedObject var playback: PlaybackCoordinator
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let pane = navigation.pane {
                detail(for: pane)
                    .navigationTitle(pane.title)
            }
        }
        .frame(width: 715, height: 540)
        .modifier(HidesSidebarToggle())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $navigation.pane) {
            // No tag, so it can't be selected.
            AppIdentityRow()
                .padding(.vertical, 6)

            Section {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        SettingsIcon(symbol: pane.symbol, color: pane.color)
                    }
                    .tag(pane)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(215)
    }

    // MARK: - Panes

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        Form {
            Section {
                SettingsPaneHeader(pane: pane)
            }

            switch pane {
            case .general: general
            case .nowPlaying: nowPlaying
            case .peeks: peeks
            case .indicators: indicators
            }
        }
        .formStyle(.grouped)
        // Each pane starts at the top, not wherever the last one was scrolled.
        .id(pane)
    }

    @ViewBuilder
    private var general: some View {
        Section {
            SettingsRow(
                title: "Automation",
                detail: "Lets Sleepy Notch control Music and Spotify.",
                symbol: "hand.raised.fill",
                color: .blue
            ) {
                Button("Open Privacy & Security…") {
                    SystemSettings.openAutomation()
                }
                .controlSize(.small)
            }
        } header: {
            Text("Music Apps")
        }

        Section {
            SettingsToggle(
                title: "Demo Mode",
                detail: "Plays a sample track, so no music app is needed.",
                symbol: "waveform",
                color: .indigo,
                isOn: demoMode
            )
        }
    }

    @ViewBuilder
    private var nowPlaying: some View {
        Section {
            SettingsRow(
                title: "Album animation",
                detail: preferences.artworkStyle.summary,
                symbol: "photo.stack.fill",
                color: .purple
            ) {
                Picker("Album animation", selection: $preferences.artworkStyle) {
                    ForEach(ArtworkTransitionStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }

            SettingsToggle(
                title: "Match album colour",
                detail: "Tints the playback controls with a colour from the cover.",
                symbol: "paintpalette.fill",
                color: .orange,
                isOn: $preferences.albumTint
            )

            SettingsToggle(
                title: "Song change",
                detail: "Shows the new song for a moment when the track changes.",
                symbol: "music.note.list",
                color: .pink,
                isOn: $preferences.songChangePeek
            )
        } header: {
            Text("Player")
        }
    }

    @ViewBuilder
    private var peeks: some View {
        Section {
            SettingsToggle(
                title: "Keyboard",
                detail: "Caps Lock and input source changes.",
                symbol: "capslock.fill",
                color: .gray,
                isOn: $preferences.keyboardPeek
            )

            SettingsToggle(
                title: "Meeting reminders",
                detail: "Five minutes before a calendar event, with a button to join.",
                symbol: "calendar",
                color: .red,
                isOn: $preferences.meetingReminders
            )

            SettingsToggle(
                title: "Copied",
                detail: "A short confirmation when you copy something.",
                symbol: "doc.on.clipboard.fill",
                color: .blue,
                isOn: $preferences.copyPeek
            )
        } header: {
            Text("Show a Peek For")
        } footer: {
            Text("Charging and headphone peeks are always on.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var indicators: some View {
        Section {
            SettingsToggle(
                title: "Camera and microphone",
                detail: "A green or orange dot while an app is using them.",
                symbol: "mic.fill",
                color: .orange,
                isOn: $preferences.privacyDots
            )

            SettingsToggle(
                title: "Battery while charging",
                detail: "The charge level beside the notch while plugged in.",
                symbol: "bolt.fill",
                color: .green,
                isOn: $preferences.chargingWing
            )
        } header: {
            Text("Beside the Notch")
        }
    }

    /// Demo mode is switched rather than set on the coordinator, because
    /// turning it off has to go back to whatever's really playing.
    private var demoMode: Binding<Bool> {
        Binding(
            get: { playback.isDemoMode },
            set: { on in
                if on != playback.isDemoMode { playback.toggleDemoMode() }
            }
        )
    }
}

/// The row at the top of the sidebar, where System Settings shows your
/// Apple Account: the app's icon, name and build.
private struct AppIdentityRow: View {
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("Sleepy Notch")
                    .font(.headline)
                Text(Self.version)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static var version: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return "Version \(version)"
        }
        return "Development build"
    }
}

/// System Settings has no button to hide its sidebar.
private struct HidesSidebarToggle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}
