import Foundation
import Speech
import AVFoundation

/// Speech to text, on this Mac only (Apple's Speech framework with
/// on-device recognition required: audio never leaves the machine).
///
/// Two uses, both on demand: dictating into the clipboard from the menu bar,
/// and turning an audio or video file on the shelf into a text file. Nothing
/// runs until one is started.
enum SpeechTranscription {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - Permission

    static func requestSpeechAccess() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// A recognizer that can work on this Mac without the network: the
    /// user's language if it can, else US English.
    static func onDeviceRecognizer() throws -> SFSpeechRecognizer {
        for locale in [Locale.current, Locale(identifier: "en-US")] {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        throw Failure(message: "On-device speech recognition isn't available for your language")
    }

    // MARK: - A file

    /// The words spoken in an audio or video file.
    static func transcribe(fileAt url: URL) async throws -> String {
        guard await requestSpeechAccess() else {
            throw Failure(message: "Allow Speech Recognition for Sleepy Notch in Privacy & Security")
        }
        let recognizer = try onDeviceRecognizer()
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let text: String = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    finished = true
                    continuation.resume(throwing: Failure(message: "Couldn't read the speech in \(url.lastPathComponent)"))
                    _ = error
                }
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure(message: "No speech found in \(url.lastPathComponent)")
        }
        return text
    }

    static func isAudioOrVideo(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie)
    }

    /// Saves `text` next to the audio as "Name transcript.txt".
    static func writeTranscript(_ text: String, for url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw Failure(message: "Can't save in \(directory.lastPathComponent)")
        }
        let output = ShelfTransform.unique(in: directory, name: url.deletingPathExtension().lastPathComponent + " transcript", ext: "txt")
        try Data(text.utf8).write(to: output, options: .atomic)
        return output
    }
}
