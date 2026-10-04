#if DEBUG
import AppKit
import Combine

/// Wires the trial features to real events, and offers "simulate" actions
/// for trying them on demand. Development builds only: none of this is part
/// of the shipping app until a design is picked and made official.
@MainActor
enum FeatureLab {
    private static var cancellables = Set<AnyCancellable>()
    private static var lastTrack: TrackSnapshot?

    static func start() {
        PowerSourceMonitor.shared.onEvent = { event in
            PeekCenter.shared.post(.power(event))
        }
        PowerSourceMonitor.shared.start()

        AudioDeviceMonitor.shared.onEvent = { event in
            showHeadphones(event)
        }
        AudioDeviceMonitor.shared.start()

        PlaybackCoordinator.shared.$currentTrack
            .sink { track in trackDidChange(track) }
            .store(in: &cancellables)
    }

    // MARK: - Real events

    private static func trackDidChange(_ track: TrackInfo) {
        let snapshot = TrackSnapshot(track)
        let previous = lastTrack
        lastTrack = snapshot

        // Same song (play/pause, seek, artwork arriving) isn't a change, and
        // the jump from the empty card to the first song at launch isn't news.
        guard let previous,
              previous.key != snapshot.key,
              !previous.isPlaceholder,
              !snapshot.isPlaceholder,
              LabSettings.shared.songChangePeek
        else { return }

        PeekCenter.shared.post(.track(TrackChange(previous: previous, current: snapshot)))
    }

    private static func showHeadphones(_ event: HeadphoneEvent) {
        PeekCenter.shared.post(.headphones(event))
        guard event.isConnected else { return }
        Task {
            // AirPods often report levels a moment after connecting, so one
            // retry. A one-shot delay, not a polling loop.
            var battery = await BluetoothBatteryReader.battery(forDeviceNamed: event.name)
            if battery == nil {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                battery = await BluetoothBatteryReader.battery(forDeviceNamed: event.name)
            }
            guard let battery else { return }
            PeekCenter.shared.attachBattery(battery, toHeadphonesNamed: event.name)
        }
    }

    // MARK: - Simulations

    static func simulateSongChange() {
        PlaybackCoordinator.shared.advanceDemoSong()
    }

    static func simulatePower(_ kind: PowerEvent.Kind) {
        let realLevel = PowerSnapshot.read()?.level
        let level: Int
        switch kind {
        case .fullyCharged: level = 100
        case .low: level = 15
        case .pluggedIn, .unplugged: level = realLevel ?? 72
        }
        PeekCenter.shared.post(.power(PowerEvent(kind: kind, level: level, isCharging: kind == .pluggedIn)))
    }

    static func simulateHeadphones(_ model: HeadphoneModel, connected: Bool) {
        let name: String
        switch model {
        case .airPods: name = "AirPods"
        case .airPodsPro: name = "AirPods Pro"
        case .airPodsMax: name = "AirPods Max"
        case .beats: name = "Beats Studio Pro"
        case .headphones: name = "Headphones"
        }
        PeekCenter.shared.post(.headphones(HeadphoneEvent(name: name, model: model, isConnected: connected)))
        guard connected else { return }

        // Mimic levels arriving a moment after the connection.
        let battery = model == .airPodsMax || model == .beats || model == .headphones
            ? HeadphoneBattery(main: 64)
            : HeadphoneBattery(left: 92, right: 88, caseLevel: 57)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            PeekCenter.shared.attachBattery(battery, toHeadphonesNamed: name)
        }
    }

    /// Puts a few generated files on the shelf, for trying it without
    /// dragging. They live in a temporary folder.
    static func addSampleFiles() {
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
        ShelfStore.shared.add(urls)
    }
}
#endif
