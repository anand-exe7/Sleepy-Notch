import Foundation
import Darwin

/// CPU and memory use, for the stats widget.
///
/// This is the one place the app samples on a timer, and only because there
/// is nothing to listen to: it ticks once a second while the widget is on
/// screen (the card open on the Widgets tab) and the moment it isn't, the
/// timer is gone.
@MainActor
final class SystemStatsSampler: ObservableObject {
    /// Fraction of the CPU in use, 0...1; nil until a second sample exists.
    @Published private(set) var cpu: Double?
    /// Fraction of memory in use, 0...1.
    @Published private(set) var memory: Double?
    @Published private(set) var memoryUsedGB: Double?
    let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    private var timer: Timer?
    private var last: (busy: UInt64, total: UInt64)?

    var isSampling: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        last = Self.ticks()
        sampleMemory()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        last = nil
        cpu = nil
    }

    private func tick() {
        if let now = Self.ticks(), let previous = last, now.total > previous.total {
            let busy = Double(now.busy &- previous.busy)
            let total = Double(now.total &- previous.total)
            // Whole percent: a change smaller than that isn't drawn anyway.
            let fraction = (min(1, max(0, busy / total)) * 100).rounded() / 100
            if fraction != cpu { cpu = fraction }
            last = now
        }
        sampleMemory()
    }

    // MARK: - Mach

    /// Busy and total CPU ticks since boot.
    private static func ticks() -> (busy: UInt64, total: UInt64)? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    private func sampleMemory() {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }
        // What Activity Monitor calls memory used: app memory, wired and compressed.
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        let used = Double(pages) * Double(vm_kernel_page_size)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let gigabytes = (used / 1_073_741_824 * 10).rounded() / 10
        if gigabytes != memoryUsedGB {
            memoryUsedGB = gigabytes
            memory = min(1, used / total)
        }
    }
}
