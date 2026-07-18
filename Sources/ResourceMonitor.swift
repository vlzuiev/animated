import Foundation
import Darwin

/// Samples the app's own resource usage every few seconds for the menu.
final class ResourceMonitor: ObservableObject {
    static let shared = ResourceMonitor()

    @Published private(set) var cpuText = "CPU: measuring…"
    @Published private(set) var memoryText = "Memory: —"
    @Published private(set) var cacheText = "Disk cache: —"

    private var timer: Timer?
    private var lastCPUSeconds: Double?
    private var lastSampleTime: Date?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleDiskCache()
    }

    /// CPU% = process CPU-seconds consumed since last sample / wall time.
    private func sampleCPU() {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpuSeconds = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let now = Date()
        if let last = lastCPUSeconds, let lastTime = lastSampleTime {
            let wall = now.timeIntervalSince(lastTime)
            if wall > 0 {
                let percent = max(0, (cpuSeconds - last) / wall * 100)
                cpuText = String(format: "CPU: %.1f %%", percent)
            }
        }
        lastCPUSeconds = cpuSeconds
        lastSampleTime = now
    }

    /// phys_footprint is the figure Activity Monitor's "Memory" column shows.
    private func sampleMemory() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        memoryText = "Memory: " + ByteCountFormatter.string(
            fromByteCount: Int64(info.phys_footprint), countStyle: .memory
        )
    }

    /// Disk the app occupies: the Apple-original backup + temp conversion files.
    private func sampleDiskCache() {
        let fm = FileManager.default
        var total: Int64 = 0

        let appSupport = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Animated")
        if let enumerator = fm.enumerator(at: appSupport, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let file as URL in enumerator {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }

        if let tmpFiles = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for file in tmpFiles where file.lastPathComponent.hasPrefix("animated-lockscreen-") {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }

        cacheText = "Disk cache: " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
}
