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
    @ObservedObject var accessibility: AccessibilityAccess
    @ObservedObject var glance: CalendarGlance
    @ObservedObject var floating: FloatingPlayerController
    @ObservedObject var clipboardHistory: ClipboardHistory
    @ObservedObject var agentInstaller: AgentHookInstaller
    @ObservedObject private var motion = MotionArtworkService.shared
    /// Plays the startup welcome now.
    let previewWelcome: () -> Void

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
            case .card: card
            case .peeks: peeks
            case .indicators: indicators
            case .system: system
            case .tools: tools
            case .agent: agent
            }
        }
        .formStyle(.grouped)
        // Each pane starts at the top, not wherever the last one was scrolled.
        .id(pane)
    }

    @ViewBuilder
    private var general: some View {
        Section {
            if NotchFinish.glass.isAvailable {
                Picker(selection: $preferences.finish) {
                    ForEach(NotchFinish.allCases, id: \.self) { finish in
                        Text(finish.title).tag(finish)
                    }
                } label: {
                    Text("Finish")
                    Text(preferences.finish.summary)
                }
            }
            Toggle(isOn: $preferences.idleCard) {
                Text("Idle card")
                Text("A small card when you hover the notch with nothing playing.")
            }
            Toggle(isOn: demoMode) {
                Text("Demo Mode")
                Text("Plays a sample track, so no music app is needed.")
            }
        } header: {
            Text("Notch")
        }

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
    }

    /// The pages of the open card: Music is always there; Calendar and
    /// Controls are the user's to add.
    @ViewBuilder
    private var card: some View {
        Section {
            LabeledContent {
                Text("Always on").foregroundStyle(.secondary)
            } label: {
                Text("Music")
                Text("The first button. The card always opens on it.")
            }
            Toggle(isOn: $preferences.widgets) {
                Text("Calendar")
                Text("The second button: the card opens big with the month. Click a day to see its events.")
            }
            Toggle(isOn: $preferences.controls) {
                Text("Controls")
                Text("The third button: Dark Mode, Mute, Stay Awake and a Focus timer.")
            }
        } header: {
            Text("Card Buttons")
        }

        if preferences.widgets {
            Section {
                LabeledContent {
                    if glance.canReadEvents {
                        Text("Allowed").foregroundStyle(.secondary)
                    } else {
                        Button("Allow…") { Task { await glance.requestAccess() } }
                    }
                } label: {
                    Text("Calendar events")
                    Text("Shows your events for the day you pick. The month itself needs no access.")
                }
            } header: {
                Text("Calendar")
            }
        }

        if preferences.controls {
            Section {
                Picker(selection: $preferences.pomodoroMinutes) {
                    ForEach([15, 20, 25, 30, 45, 50], id: \.self) { Text("\($0) minutes").tag($0) }
                } label: {
                    Text("Focus round")
                    Text("Breaks are 5 minutes, and 15 after every fourth round.")
                }
            } header: {
                Text("Controls")
            }
        }
    }

    @ViewBuilder
    private var system: some View {
        Section {
            Toggle(isOn: $preferences.systemHUDs) {
                Text("Volume and brightness")
                Text("Shows volume, screen brightness and keyboard backlight in the notch.")
            }
            Toggle(isOn: $preferences.takeOverMediaKeys) {
                Text("Hide macOS's own pop-ups")
                Text("Takes over the volume and brightness keys so only the notch shows them. If Sleepy Notch quits, the keys go back to normal at once. Needs Accessibility.")
            }
            .disabled(!preferences.systemHUDs)
            if preferences.takeOverMediaKeys && !accessibility.isTrusted {
                LabeledContent {
                    Button("Allow…") { accessibility.request() }
                } label: {
                    Text("Accessibility access needed")
                    Text("Switch Sleepy Notch on under Privacy & Security > Accessibility.")
                }
            }
        } header: {
            Text("Volume and Brightness")
        }

        Section {
            Toggle(isOn: $preferences.stayAwake) {
                Text("Stay Awake")
                Text("The Stay Awake item in the menu bar menu. It's always on the Controls button.")
            }
            Toggle(isOn: $preferences.timers) {
                Text("Timers")
                Text("Start a countdown from the menu bar; it runs beside the notch.")
            }
            Toggle(isOn: $preferences.downloads) {
                Text("Downloads")
                Text("Shows download progress beside the notch. macOS may ask to allow access to your Downloads folder.")
            }
            Toggle(isOn: $preferences.recordingTimer) {
                Text("Screen recording time")
                Text("A red dot and the time while the screen is being recorded.")
            }
        } header: {
            Text("Beside the Notch")
        }
    }

    @ViewBuilder
    private var tools: some View {
        Section {
            Toggle(isOn: $preferences.shelf) {
                Text("File shelf")
                Text("Drag files onto the notch to keep them close at hand.")
            }
        } header: {
            Text("Shelf")
        }

        Section {
            Toggle(isOn: $preferences.speechToText) {
                Text("Speech to text")
                Text("Menu bar → Dictate to Clipboard, and Transcribe for audio files on the shelf. Done on this Mac only.")
            }
            Toggle(isOn: $preferences.textCapture) {
                Text("Capture Text")
                Text("Menu bar → Capture Text…: drag over anything on screen and its words are copied. Needs Screen Recording access.")
            }
            Toggle(isOn: $preferences.bridge) {
                Text("Scripting")
                Text("Lets scripts show a message, add a file to the shelf or start a timer. Run scripts/sleepynotch --help.")
            }
        } header: {
            Text("Tools")
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
            LabeledContent {
                HStack(spacing: 7) {
                    ForEach(HighlightColour.allCases) { choice in
                        Button { preferences.highlight = choice } label: {
                            Circle()
                                .fill(choice == .multicolour
                                      ? AnyShapeStyle(AngularGradient(colors: HighlightColour.rolled.map(\.color) + [HighlightColour.rolled[0].color], center: .center))
                                      : AnyShapeStyle(choice.color))
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                                .overlay {
                                    if preferences.highlight == choice {
                                        Circle().strokeBorder(Color.primary, lineWidth: 1.6).frame(width: 22, height: 22)
                                    }
                                }
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(choice.title)
                        .accessibilityLabel(choice.title)
                        .accessibilityAddTraits(preferences.highlight == choice ? .isSelected : [])
                    }
                }
            } label: {
                Text("Highlight colour")
                Text("The playing bars and the progress line. White is the system's own look; the rainbow picks a new colour for every song.")
            }
            Toggle(isOn: $preferences.albumTint) {
                Text("Match album colour")
                Text("Tints the playback controls with a colour from the cover.")
            }
            Toggle(isOn: $preferences.playingNext) {
                Text("Playing Next")
                Text("The next songs in the expanded floating player. Apple Music only.")
            }
            Toggle(isOn: $preferences.songChangePeek) {
                Text("Show song changes")
                Text("Shows the new song for a moment when the track changes.")
            }
        } header: {
            Text("Player")
        }

        Section {
            Toggle(isOn: Binding(get: { floating.isVisible }, set: { _ in floating.toggle() })) {
                Text("Show the floating player")
                Text("A small player that stays above your windows. Also in the menu bar menu.")
            }
            Picker(selection: $floating.size) {
                ForEach(FloatingPlayerSize.allCases) { Text($0.title).tag($0) }
            } label: {
                Text("Size")
                Text("Expanded adds a large cover, and what plays next in Apple Music.")
            }
        } header: {
            Text("Floating Player")
        }

        if SkyLightSpace.isAvailable {
            Section {
                Toggle(isOn: $preferences.lockScreenCard) {
                    Text("Lock screen card")
                    Text("A glass pill with what's playing on the lock screen. Click it for the player; click the cover to fill the screen with the art.")
                }
                if motion.hasToken {
                    LabeledContent {
                        Button("Remove") { motion.removeToken() }
                    } label: {
                        Text("Animated album art")
                        Text(motion.problem ?? "On. Albums with an animated cover in Apple Music play it full screen.")
                    }
                } else {
                    LabeledContent {
                        HStack {
                            SecureField("MusicKit token", text: $motion.tokenDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                                .onSubmit { motion.saveDraft() }
                            Button("Save") { motion.saveDraft() }
                                .disabled(motion.tokenDraft.isEmpty)
                        }
                    } label: {
                        Text("Animated album art")
                        Text("Apple Music's moving covers come only from the Apple Music API, which needs a MusicKit developer token from your own Apple Developer account. Paste one to turn them on; it's kept in your Keychain and sent only to Apple.")
                    }
                }
            } header: {
                Text("Lock Screen")
            }
        }
    }

    @ViewBuilder
    private var peeks: some View {
        Section {
            Toggle(isOn: $preferences.chargingPeek) {
                Text("Charging")
                Text("When the charger is plugged in or removed, and when the battery runs low.")
            }
            Toggle(isOn: $preferences.headphonePeek) {
                Text("Headphones")
                Text("When headphones connect, with their battery level.")
            }
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

            Toggle(isOn: $preferences.clipboardHistory) {
                Text("Clipboard history")
                Text("Keeps what you copy, to copy again from the notch's Clipboard tab. Kept in memory only, gone when the app quits; anything a password manager marks private is never kept.")
            }
            if preferences.clipboardHistory {
                LabeledContent {
                    Button("Clear") { clipboardHistory.clear() }
                        .disabled(clipboardHistory.entries.isEmpty)
                } label: {
                    Text("Clipboard history")
                    Text(clipboardHistory.entries.isEmpty ? "Nothing kept." : "\(clipboardHistory.entries.count) items kept (up to \(ClipboardHistory.maxEntries)).")
                }
            }
            Toggle(isOn: $preferences.copyPeek) {
                Text("Copied")
                Text("A short confirmation when you copy something. Off by default: it watches the clipboard for 30 seconds after you last use the Mac.")
            }

            Toggle(isOn: $preferences.welcomeAtStartup) {
                Text("Welcome")
                Text("Says hello each time the app opens, before anything else shows.")
            }
            Toggle(isOn: $preferences.colourfulHello) {
                Text("Colourful hello")
                Text("Writes the hello in Apple's colours. Off, it's frosted white.")
            }
            .disabled(!preferences.welcomeAtStartup)
            LabeledContent {
                Button("Preview") { previewWelcome() }
            } label: {
                Text("Preview welcome")
                Text("Plays it now, to see how it looks.")
            }
            Toggle(isOn: $preferences.eyeBreak) {
                Text("Eye break")
                Text("Every 20 minutes of screen time: look 20 feet away for 20 seconds.")
            }
            Toggle(isOn: $preferences.windDown) {
                Text("Bedtime reminder")
                Text("A calm reminder to wind down, once a day at the time you choose.")
            }
            if preferences.windDown {
                DatePicker(selection: bedtime, displayedComponents: .hourAndMinute) {
                    Text("Remind me at")
                }
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
    private var agent: some View {
        Section {
            Toggle(isOn: $preferences.agentStatus) {
                Text("Agent status")
                Text("Shows when your coding agent is working, needs you, or is done.")
            }
            Toggle(isOn: $preferences.agentBanter) {
                Text("Playful messages")
                Text("A light line like \"Cooking! You can watch reels btw 😎\" when the agent starts working.")
            }
            .disabled(!preferences.agentStatus)
            LabeledContent {
                if agentInstaller.isInstalled {
                    Button("Remove Hooks") { agentInstaller.uninstall() }
                } else {
                    Button("Install Hooks") { agentInstaller.install() }
                }
            } label: {
                Text(agentInstaller.isInstalled ? "Hooks installed" : "Hooks")
                Text(agentInstaller.status ?? "Adds four small entries to the agent's settings file. Removing them puts it back exactly as it was.")
            }
        } header: {
            Text("Agent")
        }
    }

    @ViewBuilder
    private var indicators: some View {
        Section {
            Picker(selection: $preferences.statusStyle) {
                ForEach(StatusStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            } label: {
                Text("Style")
                Text(preferences.statusStyle.summary)
            }
            Toggle(isOn: $preferences.nowPlayingWings) {
                Text("Now playing")
                Text("The album cover and bars beside the notch while a song is playing or paused.")
            }
            Toggle(isOn: $preferences.privacyDots) {
                Text("Camera and microphone")
                Text("A green or orange dot while an app is using them.")
            }
            Toggle(isOn: $preferences.voiceWaves) {
                Text("Voice waves")
                Text("The mic's bars move with your voice while an app is using it. Asks for microphone access once; nothing is recorded.")
            }
            .disabled(!preferences.privacyDots)
            Toggle(isOn: $preferences.chargingWing) {
                Text("Battery while charging")
                Text("The charge level beside the notch while plugged in.")
            }
        } header: {
            Text("Beside the Notch")
        }

        Section {
            Toggle(isOn: $preferences.adaptiveStyle) {
                Text("Adapt to a crowded menu bar")
                Text("Moves everything inside the notch when a menu bar icon is right beside it, so none is covered.")
            }
            if preferences.adaptiveStyle && !accessibility.isTrusted {
                LabeledContent {
                    Button("Allow…") { accessibility.request() }
                } label: {
                    Text("Accessibility access needed")
                    Text("macOS only lets an app see the menu bar's icons with this. Switch Sleepy Notch on under Privacy & Security > Accessibility.")
                }
            }
        } header: {
            Text("Menu Bar")
        }

        Section {
            ForEach(ActivityKind.placeable, id: \.kind.storageKey) { item in
                Picker(selection: placement(of: item.kind)) {
                    Text("Beside the notch").tag(false)
                    Text("Tray only").tag(true)
                } label: {
                    Text(item.title)
                }
            }
        } header: {
            Text("Where Activities Show")
        } footer: {
            Text("When more is running than fits beside the notch, a +N bubble opens a tray listing everything. \"Tray only\" keeps an activity out of the bubbles; it still shows in the notch when it's the only thing running.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Whether an activity is kept in the tray rather than getting a bubble.
    private func placement(of kind: ActivityKind) -> Binding<Bool> {
        Binding(
            get: { preferences.isTrayOnly(kind) },
            set: { tray in
                if tray {
                    preferences.trayOnly.insert(kind.storageKey)
                } else {
                    preferences.trayOnly.remove(kind.storageKey)
                }
            }
        )
    }

    /// The bedtime reminder's time, as the date the picker wants.
    private var bedtime: Binding<Date> {
        Binding(
            get: {
                var parts = DateComponents()
                parts.hour = preferences.windDownMinutes / 60
                parts.minute = preferences.windDownMinutes % 60
                return Calendar.current.date(from: parts) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                preferences.windDownMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 30)
            }
        )
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
