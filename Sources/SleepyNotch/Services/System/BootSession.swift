import Darwin

/// Which startup of the Mac this is.
///
/// The kernel makes a new session UUID each time the Mac starts up or
/// restarts, and keeps it through sleep and wake, locking, switching users
/// and the app quitting and reopening. So "have we seen this ID before?"
/// tells a fresh startup apart from everything else, with nothing to watch.
enum BootSession {
    /// This startup's ID, or nil if the kernel won't say.
    static func current() -> String? {
        if let uuid = string("kern.bootsessionuuid"), !uuid.isEmpty {
            return uuid
        }
        // Older systems: the moment the Mac started up is just as unique.
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else { return nil }
        return "boottime-\(bootTime.tv_sec)-\(bootTime.tv_usec)"
    }

    private static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
