import AVFoundation
import Accelerate
import Foundation

/// How loud the mic is, for the voice waves beside the notch.
///
/// Listens only while another app already has the mic on and the notch can
/// be seen, and only with the microphone permission. Nothing is recorded or
/// kept: each short buffer is reduced to one loudness number and dropped.
/// The level reaches the screen about 15 times a second, straight into Core
/// Animation layers (see `MicWaveView`), so SwiftUI never redraws for it.
@MainActor
final class MicLevelMonitor {
    static let shared = MicLevelMonitor()

    /// Whether the waves follow the voice right now. False before the
    /// permission is granted, after it's denied, or while not listening:
    /// the waves then play a calm speaking-style loop instead.
    private(set) var isLive = false {
        didSet {
            guard isLive != oldValue else { return }
            for observer in liveObservers.values { observer(isLive) }
        }
    }

    private var engine: AVAudioEngine?
    private var wanted = false
    private var observers: [UUID: (Float) -> Void] = [:]
    private var liveObservers: [UUID: (Bool) -> Void] = [:]
    private let meter = LevelMeter()

    private init() {}

    // MARK: - Observing

    /// Calls `onLevel` with each new level (0…1) and `onLive` when listening
    /// starts or stops. Returns a token for `removeObserver`.
    func addObserver(onLevel: @escaping (Float) -> Void, onLive: @escaping (Bool) -> Void) -> UUID {
        let id = UUID()
        observers[id] = onLevel
        liveObservers[id] = onLive
        onLive(isLive)
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
        liveObservers[id] = nil
    }

    // MARK: - Listening

    /// Listens while `active`: another app is using the mic, the waves are on
    /// in Settings, and the notch is visible.
    func setActive(_ active: Bool) {
        guard active != wanted else { return }
        wanted = active
        if active { start() } else { stop() }
    }

    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted, self.wanted { self.startEngine() }
                }
            }
        default:
            isLive = false
        }
    }

    private func startEngine() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        meter.reset()
        let meter = meter
        // ~20 buffers a second at 48 kHz: plenty for a level, little work.
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            guard let level = meter.process(buffer) else { return }
            DispatchQueue.main.async {
                MicLevelMonitor.shared.deliver(level)
            }
        }
        do {
            try engine.start()
            self.engine = engine
            isLive = true
        } catch {
            input.removeTap(onBus: 0)
            isLive = false
        }
    }

    private func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        isLive = false
        deliver(0)
    }

    private func deliver(_ level: Float) {
        for observer in observers.values { observer(level) }
    }
}

/// Turns audio buffers into a smoothed 0…1 loudness, at most 15 times a
/// second. Runs on the audio thread.
private final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var smoothed: Float = 0
    private var lastSent: TimeInterval = 0
    private static let interval: TimeInterval = 1.0 / 15

    func reset() {
        lock.lock()
        smoothed = 0
        lastSent = 0
        lock.unlock()
    }

    /// The level to show, or nil when it's not time to send one yet.
    func process(_ buffer: AVAudioPCMBuffer) -> Float? {
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
        // Speech sits roughly between -50 dB (quiet room) and -10 dB.
        let decibels = 20 * log10(max(rms, 0.000_01))
        let target = min(1, max(0, (decibels + 50) / 40))

        lock.lock()
        defer { lock.unlock() }
        // Rises quickly with the voice, falls back gently.
        smoothed += (target - smoothed) * (target > smoothed ? 0.6 : 0.25)
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSent >= Self.interval else { return nil }
        lastSent = now
        return smoothed
    }
}
