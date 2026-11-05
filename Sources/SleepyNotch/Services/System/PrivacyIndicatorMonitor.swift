import AppKit
import CoreAudio
import CoreMediaIO
import Foundation

/// Reports whether any app is using a microphone or a camera, for the
/// privacy dots beside the notch.
///
/// Asks CoreAudio and CoreMediaIO whether each input device is "running
/// somewhere" — in use by any process — which needs no microphone or camera
/// permission, since nothing is captured. Both call back on changes; nothing
/// is polled.
///
/// The mic is judged per app where macOS allows it (14 and later), leaving
/// this app out: while another app has the mic on, this one reads its level
/// for the voice waves (see `MicLevelMonitor`), and counting that would keep
/// the mic "in use" after the other app stopped.
@MainActor
final class PrivacyIndicatorMonitor {
    var onChange: ((_ micInUse: Bool, _ cameraInUse: Bool) -> Void)?

    private var watchedMics: Set<AudioDeviceID> = []
    private var watchedCameras: Set<CMIOObjectID> = []
    private var watchedProcesses: Set<AudioObjectID> = []
    private var isStarted = false
    private var last: (mic: Bool, camera: Bool)?

    init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        var devices = Self.audioAddress(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, .main) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        if #available(macOS 14, *) {
            var processes = Self.audioAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &processes, .main) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }

        var cameras = Self.cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cameras, .main) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        refresh()
    }

    /// Starts watching devices that appeared, then reports the current state.
    private func refresh() {
        let mics = Self.inputDevices()
        for mic in mics where !watchedMics.contains(mic) {
            watchedMics.insert(mic)
            var running = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectAddPropertyListenerBlock(mic, &running, .main) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.report() }
            }
        }

        if #available(macOS 14, *) {
            for process in Self.audioProcesses() where !watchedProcesses.contains(process) {
                watchedProcesses.insert(process)
                var running = Self.audioAddress(kAudioProcessPropertyIsRunningInput)
                AudioObjectAddPropertyListenerBlock(process, &running, .main) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.report() }
                }
            }
        }

        let cameras = Self.cameraDevices()
        for camera in cameras where !watchedCameras.contains(camera) {
            watchedCameras.insert(camera)
            var running = Self.cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            CMIOObjectAddPropertyListenerBlock(camera, &running, .main) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.report() }
            }
        }

        report()
    }

    private func report() {
        let mic: Bool
        if #available(macOS 14, *), let others = Self.anotherAppIsRecording() {
            mic = others
        } else {
            mic = Self.inputDevices().contains { Self.isRunning($0) }
        }
        let camera = Self.cameraDevices().contains { Self.isCameraRunning($0) }
        if let last, last.mic == mic, last.camera == camera { return }
        last = (mic, camera)
        onChange?(mic, camera)
    }

    // MARK: - CoreAudio

    private static func audioAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func inputDevices() -> [AudioDeviceID] {
        var address = audioAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { device in
            var streams = audioAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    private static func isRunning(_ device: AudioDeviceID) -> Bool {
        var address = audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    // MARK: - Per app (macOS 14+)

    @available(macOS 14, *)
    private static func audioProcesses() -> [AudioObjectID] {
        var address = audioAddress(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Whether any app but this one is taking input from a mic. `nil` when
    /// macOS doesn't list audio apps, so the caller falls back to devices.
    @available(macOS 14, *)
    private static func anotherAppIsRecording() -> Bool? {
        let processes = audioProcesses()
        guard !processes.isEmpty else { return nil }
        let me = getpid()
        return processes.contains { process in
            var pidAddress = audioAddress(kAudioProcessPropertyPID)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid != me else { return false }
            var runningAddress = audioAddress(kAudioProcessPropertyIsRunningInput)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr && running != 0
        }
    }

    /// The apps taking input from a mic right now, this one left out: a
    /// helper process (a browser's audio helper, say) counts as the app it
    /// lives inside. Empty before macOS 14, which doesn't say. Read when
    /// asked; nothing is watched for it.
    static func appsUsingMic() -> [NSRunningApplication] {
        guard #available(macOS 14, *) else { return [] }
        let me = getpid()
        var seen = Set<String>()
        var apps: [NSRunningApplication] = []
        for process in audioProcesses() {
            var pidAddress = audioAddress(kAudioProcessPropertyPID)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var runningAddress = audioAddress(kAudioProcessPropertyIsRunningInput)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid != me,
                  AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0,
                  let app = owningApp(of: pid)
            else { continue }
            let key = app.bundleIdentifier ?? "\(app.processIdentifier)"
            if seen.insert(key).inserted { apps.append(app) }
        }
        return apps
    }

    /// The app a process belongs to: itself if it's an app, else the
    /// outermost `.app` it lives inside, if that's running.
    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        guard let process = NSRunningApplication(processIdentifier: pid) else { return nil }
        if process.activationPolicy == .regular { return process }
        guard let path = process.bundleURL?.path ?? process.executableURL?.path,
              let range = path.range(of: ".app/") ?? path.range(of: ".app", options: .backwards)
        else { return process }
        let appPath = String(path[..<range.lowerBound]) + ".app"
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == appPath } ?? process
    }

    // MARK: - CoreMediaIO

    private static func cameraAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private static func cameraDevices() -> [CMIOObjectID] {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private static func isCameraRunning(_ device: CMIOObjectID) -> Bool {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        var running: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return CMIOObjectGetPropertyData(device, &address, 0, nil, size, &used, &running) == noErr && running != 0
    }
}
