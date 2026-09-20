import Foundation
import IOKit.ps

/// 本机系统状态采集：CPU / 内存 / 电池 / 网速
/// 全部走 macOS 公开 API，不需要任何权限
/// 注意：内部保存了上一次的 CPU ticks 和网卡字节数用于求差，**不是**线程安全的。
/// 调用方必须始终在同一条串行队列上调用 sample()，见 AppDelegate.collectQueue。
final class SystemStatsProvider: @unchecked Sendable {
    // CPU 和网速都要靠两次采样做差分，这里存上一次的值
    private var lastCPUTicks: (user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64)?
    private var lastNet: (down: UInt64, up: UInt64, time: Date)?

    func sample() -> SystemStats {
        var s = SystemStats()
        s.cpuPercent = cpuUsage()
        let mem = memoryUsage()
        s.memoryPercent = mem.percent
        s.memoryUsedGB = mem.usedGB
        s.memoryTotalGB = mem.totalGB
        let bat = battery()
        s.batteryPercent = bat.percent
        s.batteryCharging = bat.charging
        s.batteryTimeLeft = bat.timeLeft
        let net = network()
        s.netDownBytes = net.down
        s.netUpBytes = net.up
        return s
    }

    // MARK: - CPU

    private func cpuUsage() -> Double {
        // C 宏 HOST_CPU_LOAD_INFO_COUNT 不能导入 Swift，按定义手算
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let user = UInt64(info.cpu_ticks.0)
        let sys = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)

        defer { lastCPUTicks = (user, sys, idle, nice) }
        guard let prev = lastCPUTicks else { return 0 }

        // 用无符号差值，防止计数器回绕导致负数
        let dUser = user &- prev.user
        let dSys = sys &- prev.sys
        let dIdle = idle &- prev.idle
        let dNice = nice &- prev.nice
        let total = dUser &+ dSys &+ dIdle &+ dNice
        guard total > 0 else { return 0 }
        return Double(dUser &+ dSys &+ dNice) / Double(total) * 100
    }

    // MARK: - 内存

    private func memoryUsage() -> (percent: Double, usedGB: Double, totalGB: Double) {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return (0, 0, totalBytes / 1_073_741_824) }

        let page = Double(vm_kernel_page_size)
        // 和「活动监视器」的口径对齐：活跃 + 联动 + 压缩
        let used = (Double(stats.active_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * page
        return (used / totalBytes * 100, used / 1_073_741_824, totalBytes / 1_073_741_824)
    }

    // MARK: - 电池

    private func battery() -> (percent: Int?, charging: Bool, timeLeft: String?) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return (nil, false, nil) }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            guard let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }

            let pct = Int((Double(current) / Double(max) * 100).rounded())
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let charging = state == kIOPSACPowerValue

            var timeLeft: String?
            if let mins = desc[kIOPSTimeToEmptyKey] as? Int, mins > 0 {
                timeLeft = "\(mins / 60):\(String(format: "%02d", mins % 60))"
            }
            return (pct, charging, timeLeft)
        }
        return (nil, false, nil)
    }

    // MARK: - 网速

    private func network() -> (down: Double, up: Double) {
        var down: UInt64 = 0, up: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            // 只统计真实网络接口，跳过回环和虚拟网卡，否则本机流量会被算进去
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            guard let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            down &+= UInt64(data.pointee.ifi_ibytes)
            up &+= UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer { lastNet = (down, up, now) }
        guard let prev = lastNet else { return (0, 0) }
        let dt = now.timeIntervalSince(prev.time)
        guard dt > 0.01 else { return (0, 0) }
        return (Double(down &- prev.down) / dt, Double(up &- prev.up) / dt)
    }
}
