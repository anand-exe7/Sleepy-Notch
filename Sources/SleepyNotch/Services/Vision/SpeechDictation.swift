import Foundation
import Speech
import AVFoundation

/// Dictation to the clipboard: speak, stop, and what was said is copied.
///
/// Started and stopped from the menu bar. While it listens, the microphone
/// is open and the words are recognized on this Mac as they come; nothing is
/// recorded to disk. It stops by itself after `maxDuration`, so a forgotten
/// one doesn't listen forever.
@MainActor
final class SpeechDictation: ObservableObject {
    @Published private(set) var isListening = false
    /// What has been recognized so far.
    @Published private(set) var transcript = ""

    /// Called with the final words when listening ends.
    var onFinish: ((String) -> Void)?
    /// Called with a short reason when it can't start or fails.
    var onProblem: ((String) -> Void)?

    static let maxDuration: TimeInterval = 180

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var limit: DispatchWorkItem?

    func toggle() {
        if isListening { stop() } else { Task { await start() } }
    }

    func start() async {
        guard !isListening else { return }
        guard await SpeechTranscription.requestSpeechAccess() else {
            return onProblem?("Allow Speech Recognition for Sleepy Notch in Privacy & Security") ?? ()
        }
        guard await SpeechTranscription.requestMicrophoneAccess() else {
            return onProblem?("Allow the microphone for Sleepy Notch in Privacy & Security") ?? ()
        }
        let recognizer: SFSpeechRecognizer
        do { recognizer = try SpeechTranscription.onDeviceRecognizer() } catch {
            return onProblem?(error.localizedDescription) ?? ()
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return onProblem?("No microphone found") ?? () }
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            request.append(buffer)
        }
        do { try engine.start() } catch {
            engine.inputNode.removeTap(onBus: 0)
            return onProblem?("Couldn't open the microphone") ?? ()
        }

        self.engine = engine
        self.request = request
        transcript = ""
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true || error != nil
            Task { @MainActor [weak self] in
                guard let self, self.isListening || isFinal else { return }
                if let text { self.transcript = text }
                if isFinal { self.finish() }
            }
        }
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        limit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxDuration, execute: work)
    }

    /// Stops listening; the recognizer then delivers the final words.
    func stop() {
        guard isListening else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        request?.endAudio()
        // `finish` runs when the recognizer reports its last result; if it
        // never does, don't leave the user waiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.finish() }
    }

    private func finish() {
        guard isListening else { return }
        isListening = false
        limit?.cancel()
        limit = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        task?.cancel()
        task = nil
        request = nil
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty { onProblem?("Didn't catch anything") } else { onFinish?(words) }
    }
}
