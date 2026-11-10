import Foundation
import Darwin

/// A Unix socket the agent's hook scripts write one JSON event to.
///
/// Event-driven: a dispatch source wakes only when something connects, so
/// nothing runs between events. The socket lives in a folder only the user
/// can open, and only the user can connect to it. Each connection sends one
/// small JSON object and closes; anything bigger than `maxBytes`, or that
/// isn't a JSON object, is dropped.
final class AgentSocketServer: @unchecked Sendable {
    /// Called on the main queue with each event received.
    var onEvent: (([String: Any]) -> Void)?

    private let path: String
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.anandexe7.sleepy-notch.agent-socket", qos: .utility)
    private static let maxBytes = 64 * 1024

    init(path: String) {
        self.path = path
    }

    var isRunning: Bool { source != nil }

    /// Starts listening. False if the socket couldn't be made (path too
    /// long, folder not writable): the feature then stays off.
    @discardableResult
    func start() -> Bool {
        guard source == nil else { return true }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { close(fd); return false }
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { _ = strlcpy($0, path, capacity) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); unlink(path); return false }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnections(on: fd) }
        source.setCancelHandler { close(fd) }
        source.resume()
        listener = fd
        self.source = source
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
        listener = -1
        unlink(path)
    }

    private func acceptConnections(on fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { return }
            read(from: client)
        }
    }

    private func read(from client: Int32) {
        defer { close(client) }
        // A client that connects and says nothing must not hold the queue.
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= Self.maxBytes {
            let count = recv(client, &buffer, buffer.count, 0)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        guard !data.isEmpty, data.count <= Self.maxBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        DispatchQueue.main.async { [weak self] in self?.onEvent?(object) }
    }
}
