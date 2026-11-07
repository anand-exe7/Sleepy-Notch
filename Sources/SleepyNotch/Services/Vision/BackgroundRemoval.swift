import AppKit
import CoreImage
import Vision

/// Cuts the subject out of a photo, on this Mac (Apple's Vision framework),
/// and saves it as a PNG with a transparent background.
///
/// Vision's foreground-instance mask needs macOS 14. On demand only: the
/// shelf's Transform menu runs it on the files you pick, off the main
/// thread, and nothing stays resident afterwards.
enum BackgroundRemoval {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether this Mac can do it.
    static var isAvailable: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    /// A new PNG next to `url` ("Name no background.png") with only the
    /// subject left. Throws if there's no subject or it can't be read.
    static func removeBackground(from url: URL) throws -> URL {
        guard #available(macOS 14.0, *) else { throw Failure(message: "Remove Background needs macOS 14 or later") }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure(message: "\(url.lastPathComponent) isn't an image")
        }
        let directory = url.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw Failure(message: "Can't save in \(directory.lastPathComponent)")
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { throw Failure(message: "Couldn't read \(url.lastPathComponent)") }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw Failure(message: "No subject found in \(url.lastPathComponent)")
        }
        let buffer: CVPixelBuffer
        do {
            buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
        } catch { throw Failure(message: "Couldn't cut out \(url.lastPathComponent)") }

        let context = CIContext()
        let cutout = CIImage(cvPixelBuffer: buffer)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let png = context.pngRepresentation(of: cutout, format: .RGBA8, colorSpace: colorSpace) else {
            throw Failure(message: "Couldn't write the cutout")
        }
        let output = ShelfTransform.unique(
            in: directory,
            name: url.deletingPathExtension().lastPathComponent + " no background",
            ext: "png"
        )
        do { try png.write(to: output, options: .atomic) } catch { throw Failure(message: "Couldn't save the cutout") }
        return output
    }
}
