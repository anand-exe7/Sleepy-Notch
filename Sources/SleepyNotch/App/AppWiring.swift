import AppKit
import SwiftUI
import Combine

/// Wires real events — track changes, power, headphones, privacy, keyboard,
/// calendar, clipboard — into the HUD. The Feature Lab menu's simulations
/// live in an extension at the end of this file.
@MainActor
final class AppWiring {
    let preferences: HUDPreferences
    let shelf: ShelfStore
    let powerSource: PowerSourceMonitor
    let status: NotchStatus
    let calendar: CalendarMonitor

    private let playback: PlaybackCoordinator
    private let peeks: PeekCenter
    private let audioDevices: AudioDeviceMonitor
    private let power: PowerStateMonitor
    private let privacy: PrivacyIndicatorMonitor
    private let keyboard: KeyboardMonitor
    private let clipboard: ClipboardMonitor
    private let downloads: DownloadsMonitor
    private let agents: AgentStatusService
    private let windDown: WindDownScheduler
    private let eyeBreak: EyeBreakScheduler
    private let bridge: LocalBridge
    private let timers: TimerService
    private let hud: SystemHUDMonitor
    private let accessibility: AccessibilityAccess
    private let crowding: MenuBarCrowding
    private let mediaKeys: MediaKeyInterceptor
    private let recording: ScreenRecordingMonitor
    private let pomodoro: PomodoroService
    private let clipboardHistory: ClipboardHistory
    private let fileDrag: FileDragMonitor

    private var cancellables = Set<AnyCancellable>()
    private var lastTrack: TrackSnapshot?

    init(
        playback: PlaybackCoordinator,
        peeks: PeekCenter,
        shelf: ShelfStore,
        preferences: HUDPreferences,
        powerSource: PowerSourceMonitor,
        audioDevices: AudioDeviceMonitor,
        power: PowerStateMonitor,
        status: NotchStatus,
        privacy: PrivacyIndicatorMonitor,
        keyboard: KeyboardMonitor,
        calendar: CalendarMonitor,
        clipboard: ClipboardMonitor,
        downloads: DownloadsMonitor,
        agents: AgentStatusService,
        windDown: WindDownScheduler,
        eyeBreak: EyeBreakScheduler,
        bridge: LocalBridge,
        timers: TimerService,
        hud: SystemHUDMonitor,
        accessibility: AccessibilityAccess,
        crowding: MenuBarCrowding,
        mediaKeys: MediaKeyInterceptor,
        recording: ScreenRecordingMonitor,
        pomodoro: PomodoroService,
        clipboardHistory: ClipboardHistory,
        fileDrag: FileDragMonitor
    ) {
        self.playback = playback
        self.peeks = peeks
        self.shelf = shelf
        self.preferences = preferences
        self.powerSource = powerSource
        self.audioDevices = audioDevices
        self.power = power
        self.status = status
        self.privacy = privacy
        self.keyboard = keyboard
        self.calendar = calendar
        self.clipboard = clipboard
        self.downloads = downloads
        self.agents = agents
        self.windDown = windDown
        self.eyeBreak = eyeBreak
        self.bridge = bridge
        self.timers = timers
        self.hud = hud
        self.accessibility = accessibility
        self.crowding = crowding
        self.mediaKeys = mediaKeys
        self.recording = recording
        self.pomodoro = pomodoro
        self.clipboardHistory = clipboardHistory
        self.fileDrag = fileDrag
    }

    func start() {
        powerSource.onEvent = { [weak self] event in
            self?.peeks.post(.power(event))
        }
        powerSource.onSnapshot = { [weak self] snapshot in
            self?.status.chargingLevel = snapshot.isOnAC && snapshot.isCharging ? snapshot.level : nil
        }
        powerSource.start()

        privacy.onChange = { [weak self] mic, camera in
            self?.status.micInUse = mic
            self?.status.cameraInUse = camera
        }
        privacy.start()

        // The voice waves listen only while another app already has the mic
        // on, they're switched on, and the notch can be seen.
        status.$micInUse
            .combineLatest(preferences.$voiceWaves, preferences.$privacyDots, power.$isNotchVisible)
            .map { $0 && $1 && $2 && $3 }
            .removeDuplicates()
            .sink { MicLevelMonitor.shared.setActive($0) }
            .store(in: &cancellables)

        // The bedtime reminder: one one-shot, re-planned after it fires, on
        // wake and unlock; it is skipped when nobody can see the notch.
        windDown.onDue = { [weak self] label in
            self?.peeks.post(.windDown(bedtime: label))
        }
        windDown.canShow = { [weak self] in self?.power.isNotchVisible ?? false }
        preferences.$windDown.combineLatest(preferences.$windDownMinutes)
            .sink { [weak self] on, minutes in
                self?.windDown.schedule(minutesAfterMidnight: on ? minutes : nil)
            }
            .store(in: &cancellables)

        // The eye break runs only while it's switched on and the screen is
        // in use; locking or sleeping cancels it and coming back starts a
        // fresh interval.
        eyeBreak.onDue = { [weak self] in self?.peeks.post(.eyeBreak) }
        preferences.$eyeBreak.combineLatest(power.$isNotchVisible)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] running in self?.eyeBreak.setRunning(running) }
            .store(in: &cancellables)

        // The system HUDs: volume, brightness and keyboard backlight, shown
        // in the notch. Listens only while it's switched on and the screen
        // is in use. macOS's own HUDs still show too: there is no safe,
        // event-driven way to hide them.
        hud.onReading = { [weak self] reading in
            guard let self, self.preferences.systemHUDs else { return }
            self.peeks.postHUD(reading)
        }
        preferences.$systemHUDs.combineLatest(power.$isNotchVisible)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] on in self?.hud.setRunning(on) }
            .store(in: &cancellables)

        // Looks at the menu bar beside the notch only while "adapt to a
        // crowded menu bar" is on and Accessibility is allowed.
        preferences.$adaptiveStyle.combineLatest(accessibility.$isTrusted)
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] on in self?.crowding.setRunning(on) }
            .store(in: &cancellables)

        // The media keys are taken over only while the HUDs are on, the
        // switch is on, Accessibility is allowed and the notch can be seen,
        // so the lock screen and a sleeping display keep their own keys.
        preferences.$takeOverMediaKeys
            .combineLatest(preferences.$systemHUDs, accessibility.$isTrusted, power.$isNotchVisible)
            .map { $0 && $1 && $2 && $3 }
            .removeDuplicates()
            .sink { [weak self] on in self?.mediaKeys.setRunning(on) }
            .store(in: &cancellables)

        // The recording timer listens to the system log only while it's on.
        preferences.$recordingTimer
            .removeDuplicates()
            .sink { [weak self] on in self?.recording.setRunning(on) }
            .store(in: &cancellables)

        // Pomodoro rounds say when they end, and follow the length chosen in Settings.
        pomodoro.onNotice = { [weak self] text in self?.peeks.post(.message(text)) }
        preferences.$pomodoroMinutes
            .sink { [weak self] minutes in self?.pomodoro.focusMinutes = Double(minutes) }
            .store(in: &cancellables)

        // Scripts: a fixed list of actions, only while the switch is on.
        bridge.onCommand = { [weak self] command in self?.run(command) }
        preferences.$bridge
            .removeDuplicates()
            .sink { [weak self] on in self?.bridge.setRunning(on) }
            .store(in: &cancellables)

        keyboard.onEvent = { [weak self] event in
            guard let self, self.preferences.keyboardPeek else { return }
            self.peeks.post(.keyboard(event))
        }
        keyboard.start()

        calendar.onReminder = { [weak self] meeting in
            guard let self, self.preferences.meetingReminders else { return }
            self.peeks.post(.meeting(meeting))
        }
        preferences.$meetingReminders
            .sink { [weak self] on in
                if on { self?.calendar.start() } else { self?.calendar.stop() }
            }
            .store(in: &cancellables)

        // While files are dragged, a pill below the notch gives them a place
        // to be dropped that isn't the top edge, where macOS opens Mission
        // Control. Only while the shelf is on.
        preferences.$shelf
            .removeDuplicates()
            .sink { [weak self] on in self?.fileDrag.setRunning(on) }
            .store(in: &cancellables)
        fileDrag.$isDraggingFiles
            .removeDuplicates()
            .sink { [weak self] dragging in
                guard let self else { return }
                if dragging { self.peeks.postNow(.dropHint) } else { self.peeks.dismissDropHint() }
            }
            .store(in: &cancellables)

        shelf.notify = { [weak self] text in self?.peeks.post(.message(text)) }

        // One detection serves the "Copied" peek and the clipboard history.
        clipboard.onCopy = { [weak self] preview in
            guard let self, self.preferences.copyPeek else { return }
            self.peeks.post(.copied(preview))
        }
        clipboard.onEntry = { [weak self] entry in
            guard let self, self.preferences.clipboardHistory else { return }
            self.clipboardHistory.add(entry)
        }
        clipboardHistory.onOwnWrite = { [weak self] in self?.clipboard.skipCurrentChange() }
        // Only watches the clipboard while one of the two is on and the
        // notch can be seen.
        power.$isNotchVisible.combineLatest(preferences.$copyPeek, preferences.$clipboardHistory)
            .sink { [weak self] visible, peek, history in self?.clipboard.setActive(visible && (peek || history)) }
            .store(in: &cancellables)
        // Switching the history off forgets it.
        preferences.$clipboardHistory
            .sink { [weak self] on in if !on { self?.clipboardHistory.clear() } }
            .store(in: &cancellables)

        preferences.$shelf
            .sink { [weak self] on in if !on { self?.shelf.clear() } }
            .store(in: &cancellables)

        audioDevices.onEvent = { [weak self] event in
            self?.showHeadphones(event)
        }
        audioDevices.start()

        playback.$currentTrack
            .sink { [weak self] track in self?.trackDidChange(track) }
            .store(in: &cancellables)
    }

    private func trackDidChange(_ track: TrackInfo) {
        let snapshot = TrackSnapshot(track)
        let previous = lastTrack
        lastTrack = snapshot

        // Same song (play/pause, seek, artwork arriving) isn't a change, and
        // the jump from the empty card to the first song at launch isn't news.
        guard let previous,
              previous.key != snapshot.key,
              !previous.isPlaceholder,
              !snapshot.isPlaceholder,
              preferences.songChangePeek
        else { return }

        peeks.post(.track(TrackChange(previous: previous, current: snapshot)))
    }

    private func showHeadphones(_ event: HeadphoneEvent) {
        peeks.post(.headphones(event))
        guard event.isConnected else { return }
        Task { [weak self] in
            // AirPods report their levels anywhere from right away to a few
            // seconds after connecting, and the buds sometimes before the
            // case. A short ladder of one-shot reads, stopping as soon as
            // every part has a level — not a polling loop.
            let delays: [Double] = [0, 0.7, 1.2, 1.6, 2.5]
            var shown: HeadphoneBattery?
            for delay in delays {
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard let battery = await BluetoothBatteryReader.battery(forDeviceNamed: event.name) else { continue }
                if battery != shown {
                    shown = battery
                    self?.peeks.attachBattery(battery, toHeadphonesNamed: event.name)
                }
                if battery.isComplete(for: event.model) { break }
            }
        }
    }
}

extension AppWiring {
    func simulateSongChange() {
        playback.advanceDemoSong()
    }

    func simulatePower(_ kind: PowerEvent.Kind) {
        let realLevel = PowerSnapshot.read()?.level
        let level: Int
        switch kind {
        case .fullyCharged: level = 100
        case .low: level = 15
        case .pluggedIn, .unplugged: level = realLevel ?? 72
        }
        peeks.post(.power(PowerEvent(kind: kind, level: level, isCharging: kind == .pluggedIn)))
    }

    func simulateHeadphones(_ model: HeadphoneModel, connected: Bool) {
        let name: String
        switch model {
        case .airPods: name = "AirPods"
        case .airPodsPro: name = "AirPods Pro"
        case .airPodsMax: name = "AirPods Max"
        case .beats: name = "Beats Studio Pro"
        case .earbuds: name = "Galaxy Buds2 Pro"
        case .headphones: name = "WH-1000XM5"
        }
        peeks.post(.headphones(HeadphoneEvent(name: name, model: model, isConnected: connected)))
        guard connected else { return }

        // Mimic real AirPods: levels arrive a moment after the connection,
        // the buds before the case.
        if model == .airPodsMax || model == .beats || model == .headphones {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.peeks.attachBattery(HeadphoneBattery(main: 64), toHeadphonesNamed: name)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.peeks.attachBattery(HeadphoneBattery(left: 92, right: 78), toHeadphonesNamed: name)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { [weak self] in
            self?.peeks.attachBattery(HeadphoneBattery(left: 92, right: 78, caseLevel: 57), toHeadphonesNamed: name)
        }
    }

    private func run(_ command: BridgeCommand) {
        switch command {
        case .peek(let text):
            peeks.post(.message(text))
        case .shelfAdd(let url):
            guard preferences.shelf else { return }
            shelf.add([url])
        case .timer(let minutes):
            timers.start(minutes: minutes)
        case .timerCancel:
            timers.cancel()
        }
    }

    func simulateHUD(_ reading: HUDReading) {
        peeks.postHUD(reading)
    }

    func simulateRecording(_ on: Bool) {
        recording.simulate(on)
    }

    func simulateEyeBreak() {
        peeks.post(.eyeBreak)
    }

    func simulateWindDown() {
        peeks.post(.windDown(bedtime: WindDownScheduler.label(forMinutes: preferences.windDownMinutes)))
    }

    func simulateGoodNight() {
        peeks.post(.goodNight)
    }

    func simulateAgent(_ state: AgentState) {
        agents.simulate(state)
    }

    func clearSimulatedAgent() {
        agents.clearSimulated()
    }

    func simulateDownload(_ fraction: Double?) {
        downloads.simulate(name: "Sleepy Notch.dmg", fraction: fraction)
    }

    func simulateDownloadFinished() {
        downloads.clearSimulated()
        peeks.post(.downloadDone(name: "Sleepy Notch.dmg"))
    }

    func clearSimulatedDownload() {
        downloads.clearSimulated()
    }

    func simulatePrivacy(mic: Bool, camera: Bool) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            status.micInUse = mic
            status.cameraInUse = camera
        }
    }

    func simulateCharging(_ on: Bool) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
            status.chargingLevel = on ? (PowerSnapshot.read()?.level ?? 64) : nil
        }
    }

    func simulateKeyboard(_ event: KeyboardEvent) {
        peeks.post(.keyboard(event))
    }

    func simulateMeeting(withLink: Bool) {
        let start = Date().addingTimeInterval(5 * 60)
        peeks.post(.meeting(MeetingReminder(
            id: UUID().uuidString,
            title: "Standup",
            start: start,
            end: start.addingTimeInterval(15 * 60),
            calendarColor: .systemBlue,
            joinURL: withLink ? URL(string: "https://meet.google.com/") : nil
        )))
    }

    func simulateCopy(_ kind: ClipboardPreview.Kind) {
        peeks.post(.copied(ClipboardPreview(kind: kind)))
    }

    /// Puts a few generated files on the shelf, for trying it without
    /// dragging. They live in a temporary folder.
    func addSampleFiles() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SleepyNotch-Lab", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var urls: [URL] = []
        let notes = folder.appendingPathComponent("Shelf notes.txt")
        if (try? "Dropped on the notch shelf.\n".write(to: notes, atomically: true, encoding: .utf8)) != nil {
            urls.append(notes)
        }
        let cover = folder.appendingPathComponent("Demo cover.png")
        if let tiff = DemoArtwork.cover(1).tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
           (try? png.write(to: cover)) != nil {
            urls.append(cover)
        }
        let readme = folder.appendingPathComponent("Read me.md")
        if (try? "# Feature Lab\n\nDrag me out of the notch.\n".write(to: readme, atomically: true, encoding: .utf8)) != nil {
            urls.append(readme)
        }
        shelf.add(urls)
    }
}
