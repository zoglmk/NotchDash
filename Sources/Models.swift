import Foundation

/// 一个限额窗口（比如「5 小时窗口」或「7 天窗口」）
struct UsageWindow: Equatable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date?

    /// 窗口的中文短名，如 "5h" / "7d"
    var label: String {
        if windowMinutes >= 1440 { return "\(windowMinutes / 1440)d" }
        if windowMinutes >= 60 { return "\(windowMinutes / 60)h" }
        return "\(windowMinutes)m"
    }

    /// 收起态用的紧凑倒计时，如 "23分" / "2小时" / "5天"。
    /// 那里只有一个数字的位置，放不下 "2小时30分" 这种完整写法。
    var compactResetText: String? {
        guard let resetsAt else { return nil }
        let s = resetsAt.timeIntervalSinceNow
        guard s > 0 else { return "即将" }
        let days = Int(s) / 86400
        if days > 0 { return "\(days)天" }
        let hours = Int(s) / 3600
        if hours > 0 { return "\(hours)小时" }
        return "\(max(Int(s) / 60, 1))分"
    }

    /// 距离重置还有多久，如 "2h30m"
    var resetText: String? {
        guard let resetsAt else { return nil }
        let s = resetsAt.timeIntervalSinceNow
        guard s > 0 else { return "即将重置" }
        let d = Int(s) / 86400, h = Int(s) % 86400 / 3600, m = Int(s) % 3600 / 60
        if d > 0 { return "\(d)天\(h)小时" }
        if h > 0 { return "\(h)小时\(m)分" }
        return "\(m)分钟"
    }
}

/// 某个 AI 编程工具的额度状态
struct Quota: Equatable, Identifiable {
    var id: String            // "claude" / "codex"
    var name: String          // 展开态显示的全名
    var short: String         // 收起态显示的两字母缩写
    var plan: String?         // 套餐名，如 "plus"
    var primary: UsageWindow?     // 短窗口（5 小时）
    var secondary: UsageWindow?   // 长窗口（7 天）
    var updatedAt: Date?
    var source: String        // 数据来自哪条通道，用于排查问题
    var error: String?        // 取数失败时的原因

    /// 收起态只显示一个最该关心的数字：优先短窗口，没有就用长窗口
    var headlinePercent: Double? {
        primary?.usedPercent ?? secondary?.usedPercent
    }

    /// 额度见底时，收起态改显示重置倒计时——都用完了，再看"0%"没有意义，
    /// 这时候真正要知道的是什么时候能接着用。
    var headlineText: String? {
        guard let used = headlinePercent, used >= 99.5 else { return nil }
        return (primary ?? secondary)?.compactResetText
    }

    /// 数据是否已经过期（超过 15 分钟没更新就标灰）
    var isStale: Bool {
        guard let updatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > 900
    }

    var staleText: String? {
        guard let updatedAt else { return nil }
        let s = Int(Date().timeIntervalSince(updatedAt))
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(s / 60)分钟前" }
        if s < 86400 { return "\(s / 3600)小时前" }
        return "\(s / 86400)天前"
    }
}

/// 本机系统状态
struct SystemStats: Equatable {
    var cpuPercent: Double = 0
    var memoryPercent: Double = 0
    var memoryUsedGB: Double = 0
    var memoryTotalGB: Double = 0
    var batteryPercent: Int?
    var batteryCharging: Bool = false
    var batteryTimeLeft: String?
    var netDownBytes: Double = 0
    var netUpBytes: Double = 0

    /// 把字节速率格式化成 "1.2M" 这种紧凑写法
    static func rate(_ bytesPerSec: Double) -> String {
        let v = bytesPerSec
        if v >= 1_048_576 { return String(format: "%.1fM", v / 1_048_576) }
        if v >= 1024 { return String(format: "%.0fK", v / 1024) }
        return "0K"
    }
}
