import Foundation
import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers

/// Things to do with the files on the shelf: zip them, convert images,
/// combine into one PDF, compress images and PDFs.
///
/// All on demand, off the main thread, with nothing kept afterwards. A
/// result is written next to the original (a new file; the original is never
/// changed) and put on the shelf.
enum ShelfTransform {
    enum ImageFormat: String, CaseIterable {
        case png = "PNG"
        case jpeg = "JPEG"
        case heic = "HEIC"

        var type: UTType {
            switch self {
            case .png: return .png
            case .jpeg: return .jpeg
            case .heic: return .heic
            }
        }

        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            case .heic: return "heic"
            }
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - What a file is

    static func isImage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) == true
    }

    /// Already in this format, so converting would only make a copy.
    static func isAlready(_ format: ImageFormat, _ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) == format.type
    }

    static func isPDF(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .pdf) == true
    }

    // MARK: - Where results go

    /// A name that isn't taken: "Name.ext", then "Name 2.ext", …
    static func unique(in directory: URL, name: String, ext: String) -> URL {
        var candidate = directory.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    private static func folder(for url: URL) throws -> URL {
        let directory = url.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw Failure(message: "Can't save in \(directory.lastPathComponent)")
        }
        return directory
    }

    // MARK: - Zip

    /// One zip of all of them: named after the file for one, "Archive" for
    /// several.
    static func zip(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw Failure(message: "Nothing to zip") }
        let directory = try folder(for: first)
        let name = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let output = unique(in: directory, name: name, ext: "zip")
        for url in urls {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            // From the file's own folder, so only its name goes in the zip.
            process.currentDirectoryURL = url.deletingLastPathComponent()
            process.arguments = ["-q", "-r", "-g", output.path, url.lastPathComponent]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: output)
                throw Failure(message: "Couldn't zip \(url.lastPathComponent)")
            }
        }
        return output
    }

    // MARK: - Convert an image

    static func convert(_ url: URL, to format: ImageFormat) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw Failure(message: "\(url.lastPathComponent) isn't an image")
        }
        let supported = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        guard supported.contains(format.type.identifier) else { throw Failure(message: "This Mac can't write \(format.rawValue)") }
        let output = unique(in: try folder(for: url), name: url.deletingPathExtension().lastPathComponent, ext: format.fileExtension)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw Failure(message: "Couldn't write \(format.rawValue)")
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: "Couldn't convert \(url.lastPathComponent)")
        }
        return output
    }

    // MARK: - Combine into a PDF

    /// Images and PDFs, in the order given, into one PDF next to the first.
    static func combinePDF(_ urls: [URL]) throws -> URL {
        let document = PDFDocument()
        for url in urls {
            if isPDF(url), let pdf = PDFDocument(url: url) {
                for index in 0..<pdf.pageCount {
                    if let page = pdf.page(at: index)?.copy() as? PDFPage { document.insert(page, at: document.pageCount) }
                }
            } else if isImage(url), let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                document.insert(page, at: document.pageCount)
            }
        }
        guard document.pageCount > 0, let first = urls.first else {
            throw Failure(message: "Add images or PDFs to combine")
        }
        let output = unique(in: try folder(for: first), name: "Combined", ext: "pdf")
        guard document.write(to: output) else { throw Failure(message: "Couldn't write the PDF") }
        return output
    }

    // MARK: - Compress

    /// A smaller copy of an image (JPEG, long side at most 2560 px) or a PDF
    /// (images re-encoded for screen). If it wouldn't be smaller, nothing is
    /// made.
    static func compress(_ url: URL) throws -> URL {
        let originalSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let name = url.deletingPathExtension().lastPathComponent + " compressed"
        let directory = try folder(for: url)
        let output: URL
        if isImage(url) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw Failure(message: "Couldn't read \(url.lastPathComponent)") }
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                throw Failure(message: "Couldn't read \(url.lastPathComponent)")
            }
            output = unique(in: directory, name: name, ext: "jpg")
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw Failure(message: "Couldn't write the image")
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.65] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Couldn't compress \(url.lastPathComponent)") }
        } else if isPDF(url), let pdf = PDFDocument(url: url) {
            // Re-encoding a PDF's images needs a newer macOS than this app's
            // minimum.
            guard #available(macOS 13.4, *) else { throw Failure(message: "Compressing PDFs needs macOS 13.4 or later") }
            output = unique(in: directory, name: name, ext: "pdf")
            let options: [PDFDocumentWriteOption: Any] = [
                .saveImagesAsJPEGOption: true,
                .optimizeImagesForScreenOption: true,
            ]
            guard pdf.write(to: output, withOptions: options) else { throw Failure(message: "Couldn't compress \(url.lastPathComponent)") }
        } else {
            throw Failure(message: "Compress works on images and PDFs")
        }
        let newSize = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard newSize > 0, newSize < originalSize else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: "\(url.lastPathComponent) is already small")
        }
        return output
    }
}

// MARK: - From the shelf

extension ShelfStore {
    /// Runs one transform off the main thread, puts what it made on the
    /// shelf, and says how it went.
    func transform(_ title: String, _ work: @escaping @Sendable () throws -> [URL]) {
        guard !isWorking else { return }
        isWorking = true
        Task { [weak self] in
            let result: Result<[URL], Error> = await Task.detached(priority: .utility) {
                Result { try work() }
            }.value
            guard let self else { return }
            self.isWorking = false
            switch result {
            case .success(let urls):
                self.add(urls)
                self.notify?(urls.count == 1 ? "\(title): \(urls[0].lastPathComponent)" : "\(title): \(urls.count) files")
            case .failure(let error):
                self.notify?(error.localizedDescription)
            }
        }
    }

    func zipFiles(_ items: [ShelfItem]) {
        let urls = items.map(\.url)
        transform("Zipped") { [try ShelfTransform.zip(urls)] }
    }

    func convertImages(_ items: [ShelfItem], to format: ShelfTransform.ImageFormat) {
        let images = items.map(\.url).filter { ShelfTransform.isImage($0) }
        guard !images.isEmpty else { return notify?("No images to convert") ?? () }
        let urls = images.filter { !ShelfTransform.isAlready(format, $0) }
        guard !urls.isEmpty else { return notify?("Already \(format.rawValue)") ?? () }
        transform("Converted to \(format.rawValue)") { try urls.map { try ShelfTransform.convert($0, to: format) } }
    }

    func combineIntoPDF(_ items: [ShelfItem]) {
        let urls = items.map(\.url).filter { ShelfTransform.isImage($0) || ShelfTransform.isPDF($0) }
        transform("Combined") { [try ShelfTransform.combinePDF(urls)] }
    }

    func removeBackgrounds(_ items: [ShelfItem]) {
        let urls = items.map(\.url).filter { ShelfTransform.isImage($0) }
        guard !urls.isEmpty else { return notify?("Remove Background works on images") ?? () }
        transform("Background removed") {
            // One with no subject shouldn't stop the others.
            var made: [URL] = []
            var firstFailure: Error?
            for url in urls {
                do { made.append(try BackgroundRemoval.removeBackground(from: url)) } catch { firstFailure = firstFailure ?? error }
            }
            if made.isEmpty, let firstFailure { throw firstFailure }
            return made
        }
    }

    func compressFiles(_ items: [ShelfItem]) {
        let urls = items.map(\.url).filter { ShelfTransform.isImage($0) || ShelfTransform.isPDF($0) }
        guard !urls.isEmpty else { return notify?("Compress works on images and PDFs") ?? () }
        transform("Compressed") {
            // One that is already small shouldn't stop the others.
            var made: [URL] = []
            var firstFailure: Error?
            for url in urls {
                do { made.append(try ShelfTransform.compress(url)) } catch { firstFailure = firstFailure ?? error }
            }
            if made.isEmpty, let firstFailure { throw firstFailure }
            return made
        }
    }
}
