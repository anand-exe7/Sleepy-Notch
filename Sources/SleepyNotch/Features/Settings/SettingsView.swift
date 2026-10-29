import SwiftUI

/// Which pane is showing, and what's typed in the sidebar's search field.
/// A small object rather than view state, and the pane is remembered
/// between launches the way System Settings reopens where you left it.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane? {
        didSet { UserDefaults.standard.set(pane?.rawValue, forKey: Self.key) }
    }
    @Published var query = ""

    private static let key = "settings.lastPane"

    init() {
        pane = UserDefaults.standard.string(forKey: Self.key)
            .flatMap(SettingsPane.init(rawValue:)) ?? .general
    }
}

/// The Settings window, built like System Settings out of the system's own
/// pieces: a sidebar with a search field and coloured icons, and grouped
/// forms of standard switches, pickers and buttons. Nothing here is drawn
/// by hand, so macOS styles all of it the way it styles its own settings.
struct SettingsView: View {
    @ObservedObject var preferences: HUDPreferences
    @ObservedObject var playback: PlaybackCoordinator
    @ObservedObject var keyboard: KeyboardMonitor
    @ObservedObject var calendar: CalendarMonitor
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
        .frame(minWidth: 715, maxWidth: 715, minHeight: 470, idealHeight: 540)
        .modifier(HidesSidebarToggle())
    }

    // MARK: - Sidebar

    private var visiblePanes: [SettingsPane] {
        SettingsPane.allCases.filter { $0.matches(navigation.query) }
    }

    /// Clicking the app row (or empty space) mustn't deselect the pane and
    /// leave the window blank, so only a real pane is ever taken.
    private var selection: Binding<SettingsPane?> {
        Binding(
            get: { navigation.pane },
            set: { if let pane = $0 { navigation.pane = pane } }
        )
    }

    private var sidebar: some View {
        List(selection: selection) {
            if navigation.query.isEmpty {
                // No tag, so it can't be selected.
                AppIdentityRow()
                    .padding(.vertical, 4)
            }

            Section {
                ForEach(visiblePanes) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        SettingsIcon(symbol: pane.symbol, color: pane.color)
                    }
                    .tag(pane)
                }
            }

            if visiblePanes.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $navigation.query, placement: .sidebar)
        .navigationSplitViewColumnWidth(215)
        // Typing a search jumps to the first pane that matches, like
        // System Settings does.
        .onChange(of: navigation.query) { _ in
            if let current = navigation.pane, visiblePanes.contains(current) { return }
            if let first = visiblePanes.first { navigation.pane = first }
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        Form {
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
            LabeledContent {
                Button("Open Privacy & Security…") {
                    SystemSettings.openAutomation()
                }
            } label: {
                Text("Automation")
                Text("Allow Sleepy Notch to control Music and Spotify.")
            }
        } header: {
            Text("Music Apps")
        }

        Section {
            Toggle(isOn: $preferences.shelf) {
                Text("File shelf")
                Text("Drag files onto the notch to keep them close at hand.")
            }
            Toggle(isOn: demoMode) {
                Text("Demo Mode")
                Text("Plays a sample track, so no music app is needed.")
            }
        } header: {
            Text("Notch")
        }
    }

    @ViewBuilder
    private var nowPlaying: some View {
        Section {
            Picker(selection: $preferences.artworkStyle) {
                ForEach(ArtworkTransitionStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            } label: {
                Text("Album animation")
                Text(preferences.artworkStyle.summary)
            }
            Toggle(isOn: $preferences.albumTint) {
                Text("Match album colour")
                Text("Tints the playback controls with a colour from the cover.")
            }
            Toggle(isOn: $preferences.songChangePeek) {
                Text("Show song changes")
                Text("Shows the new song for a moment when the track changes.")
            }
        } header: {
            Text("Player")
        }
    }

    @ViewBuilder
    private var peeks: some View {
        Section {
            Toggle(isOn: $preferences.keyboardPeek) {
                Text("Keyboard")
                Text("Caps Lock and input source changes.")
            }
            if preferences.keyboardPeek && !keyboard.canSeeCapsLock {
                LabeledContent {
                    Button("Allow…") {
                        KeyboardMonitor.requestCapsLockAccess()
                    }
                } label: {
                    Text("Caps Lock detection")
                    Text("Needs Accessibility access to see Caps Lock in other apps.")
                }
            }

            Toggle(isOn: $preferences.meetingReminders) {
                Text("Meeting reminders")
                Text("Five minutes before a calendar event, with a button to join.")
            }
            if preferences.meetingReminders && calendar.access == .denied {
                LabeledContent {
                    Button("Open Privacy & Security…") {
                        SystemSettings.openCalendars()
                    }
                } label: {
                    Text("Calendar access is off")
                    Text("Allow it in System Settings to get reminders.")
                }
            }

            Toggle(isOn: $preferences.copyPeek) {
                Text("Copied")
                Text("A short confirmation when you copy something.")
            }
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
            Toggle(isOn: $preferences.privacyDots) {
                Text("Camera and microphone")
                Text("A green or orange dot while an app is using them.")
            }
            Toggle(isOn: $preferences.chargingWing) {
                Text("Battery while charging")
                Text("The charge level beside the notch while plugged in.")
            }
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
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sleepy Notch")
                    .font(.headline)
                Text(Self.version)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
