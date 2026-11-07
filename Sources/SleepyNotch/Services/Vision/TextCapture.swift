import AppKit
import Vision

/// Reads the text out of a picture, on this Mac (Apple's Vision framework;
/// nothing is sent anywhere), and copies it.
///
/// "Capture Text" lets the user drag a rectangle over anything on screen with
/// the system's own screenshot selector, reads the words in it, and puts them
/// on the clipboard. It is on demand only: nothing runs until it's asked for.
enum TextCapture {
    enum Failure: LocalizedError {
        case cancelled
        case noText
        case unreadable
        case denied

        var errorDescription: String? {
            switch self {
            case .cancelled: return nil
            case .noText: return "No text found"
            case .unreadable: return "Couldn't read that picture"
            case .denied: return "Allow screen recording for Sleepy Notch in System Settings"
            }
        }
    }

    // MARK: - Reading

    /// The words in `image`, top to bottom, one line per line of text.
    nonisolated static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Every language this Mac's Vision can read, so a mixed or non-Latin
        // screenshot works too.
        if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { throw Failure.unreadable }
        let lines = (request.results ?? [])
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { throw Failure.noText }
        return lines.joined(separator: "\n")
    }

    static func recognize(fileAt url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure.unreadable }
        return try recognize(image)
    }

    // MARK: - Capturing

    /// Asks the user to select part of the screen, and reads it. Throws
    /// `cancelled` if they pressed Escape.
    static func captureFromScreen() async throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sleepy-notch-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        try await runSelector(writingTo: file)
        guard FileManager.default.fileExists(atPath: file.path) else { throw Failure.cancelled }
        return try await Task.detached(priority: .userInitiated) { try recognize(fileAt: file) }.value
    }

    /// `screencapture -i`: the system's crosshair selection. No sound, no
    /// window shadow, written to a file; no file means it was cancelled.
    private static func runSelector(writingTo file: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", "-o", file.path]
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume(throwing: Failure.denied) }
        }
    }
}
