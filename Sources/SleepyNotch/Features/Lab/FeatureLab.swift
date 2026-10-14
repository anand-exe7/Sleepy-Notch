#if DEBUG
import AppKit
import SwiftUI
import Combine

/// Wires the trial features to real events, and offers "simulate" actions
/// for trying them on demand. Development builds only: none of this is part
/// of the shipping app until a design is picked and made official.
@MainActor
final class FeatureLab {
    let lab: LabSettings
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

    private var cancellables = Set<AnyCancellable>()
    private var lastTrack: TrackSnapshot?

    init(
        playback: PlaybackCoordinator,
        peeks: PeekCenter,
        shelf: ShelfStore,
        lab: LabSettings,
        powerSource: PowerSourceMonitor,
        audioDevices: AudioDeviceMonitor,
        power: PowerStateMonitor,
        status: NotchStatus,
        privacy: PrivacyIndicatorMonitor,
        keyboard: KeyboardMonitor,
        calendar: CalendarMonitor,
        clipboard: ClipboardMonitor
    ) {
        self.playback = playback
        self.peeks = peeks
        self.shelf = shelf
        self.lab = lab
        self.powerSource = powerSource
        self.audioDevices = audioDevices
        self.power = power
        self.status = status
        self.privacy = privacy
        self.keyboard = keyboard
        self.calendar = calendar
        self.clipboard = clipboard
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

        keyboard.onEvent = { [weak self] event in
            guard let self, self.lab.keyboardPeek else { return }
            self.peeks.post(.keyboard(event))
        }
        keyboard.start()

        calendar.onReminder = { [weak self] meeting in
            guard let self, self.lab.meetingReminders else { return }
            self.peeks.post(.meeting(meeting))
        }
        lab.$meetingReminders
            .sink { [weak self] on in
                if on { self?.calendar.start() } else { self?.calendar.stop() }
            }
            .store(in: &cancellables)

        clipboard.onCopy = { [weak self] preview in
            self?.peeks.post(.copied(preview))
        }
        // Only watches the clipboard while the peek is on and the notch can
        // be seen.
        power.$isNotchVisible.combineLatest(lab.$copyPeek)
            .sink { [weak self] visible, on in self?.clipboard.setActive(visible && on) }
            .store(in: &cancellables)

        audioDevices.onEvent = { [weak self] event in
            self?.showHeadphones(event)
        }
        audioDevices.start()

        playback.$currentTrack
            .sink { [weak self] track in self?.trackDidChange(track) }
            .store(in: &cancellables)
    }

    // MARK: - Real events

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
              lab.songChangePeek
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

    // MARK: - Simulations

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
        case .headphones: name = "Headphones"
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
#endif
