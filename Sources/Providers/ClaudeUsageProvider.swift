import Foundation

/// Claude Code 额度采集
/// 主通道：statusline 快照文件。Claude Code 每次刷新状态栏时，会把官方 stdin 负载里的
/// rate_limits 交给我们的脚本落盘（见 scripts/claude-usage-tee.sh）。不碰凭据、不联网。
/// 快照格式刻意与 claude-hud 的 externalUsagePath 保持一致，同一个文件两边都能读。
final class ClaudeUsageProvider: Sendable {
    static let snapshotURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".notchdash/claude-usage.json")

    /// 这台机器装没装 Claude Code。
    ///
    /// 用 ~/.claude 目录判断，不用 statusline 快照：快照缺失也可能只是没配
    /// statusline（本来就是可选的），那种情况下 API 兜底还能拿到数据，不该当成没装。
    /// 目录是 Claude Code 自己建的，没装就一定没有。
    static var isInstalled: Bool {
        if Simulate.on("no-quota") { return false }
        return FileManager.default.fileExists(atPath: FileManager.default
            .homeDirectoryForCurrentUser.appendingPathComponent(".claude").path)
    }

    private struct Snapshot: Decodable {
        let updatedAt: DateValue?
        let fiveHour: Window?
        let sevenDay: Window?
        let plan: String?
        struct Window: Decodable {
            let usedPercentage: Double?
            let resetsAt: DateValue?
        }
    }

    /// 时间字段可能是 ISO 字符串，也可能是 Unix 秒，两种都要能吃下
    private enum DateValue: Decodable {
        case date(Date)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Double.self) {
                // 毫秒级时间戳也兼容一下
                self = .date(Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n))
                return
            }
            let s = try c.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { self = .date(d); return }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { self = .date(d); return }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "无法解析时间: \(s)")
        }
        var value: Date { if case .date(let d) = self { return d }; return Date() }
    }

    func fetch() -> Quota {
        var quota = Quota(id: "claude", name: "Claude Code", short: "CC", plan: nil,
                          primary: nil, secondary: nil, updatedAt: nil,
                          source: "statusline 快照", error: nil)

        if Simulate.on("empty-quota") {
            quota.error = "模拟：装了但取不到额度"
            return quota
        }

        let url = Self.snapshotURL
        guard let data = try? Data(contentsOf: url) else {
            quota.error = "等待 Claude Code 刷新状态栏"
            return quota
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let snap = try? decoder.decode(Snapshot.self, from: data) else {
            quota.error = "快照格式无法解析"
            return quota
        }

        quota.plan = snap.plan
        quota.updatedAt = snap.updatedAt?.value
        if let w = snap.fiveHour, let pct = w.usedPercentage {
            quota.primary = UsageWindow(usedPercent: pct, windowMinutes: 300,
                                        resetsAt: w.resetsAt?.value)
        }
        if let w = snap.sevenDay, let pct = w.usedPercentage {
            quota.secondary = UsageWindow(usedPercent: pct, windowMinutes: 10080,
                                          resetsAt: w.resetsAt?.value)
        }
        if quota.primary == nil && quota.secondary == nil {
            quota.error = "快照里没有额度字段"
        }
        return quota
    }
}
