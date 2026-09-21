import Foundation

/// Codex 额度采集
/// 数据来源：~/.codex/sessions/<年>/<月>/<日>/rollout-*.jsonl 里的 token_count 事件
/// 这是 Codex CLI 自己写的本地会话日志，不涉及凭据、不联网
final class CodexUsageProvider: Sendable {
    private let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")

    /// 这台机器装没装 Codex。理由同 ClaudeUsageProvider.isInstalled：
    /// 用目录判断，sessions 子目录不存在只说明还没跑过，不代表没装。
    static var isInstalled: Bool {
        if Simulate.on("no-quota") { return false }
        return FileManager.default.fileExists(atPath: FileManager.default
            .homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
    }

    /// 只扫最近改动的这么多个会话文件，避免翻遍历史
    private let maxFilesToScan = 20
    /// 每个文件只读末尾这么多字节——最新的额度记录一定在文件尾部
    private let tailBytes: UInt64 = 512 * 1024

    private struct Event: Decodable {
        let timestamp: String?
        let payload: Payload?
        struct Payload: Decodable {
            let type: String?
            let rateLimits: RateLimits?
        }
        struct RateLimits: Decodable {
            let limitId: String?
            let planType: String?
            let primary: Window?
            let secondary: Window?
        }
        struct Window: Decodable {
            let usedPercent: Double?
            let windowMinutes: Int?
            let resetsAt: Double?
        }
    }

    func fetch() -> Quota {
        var quota = Quota(id: "codex", name: "Codex", short: "Codex", plan: nil,
                          primary: nil, secondary: nil, updatedAt: nil,
                          source: "codex 会话日志", error: nil)

        if Simulate.on("empty-quota") {
            quota.error = "模拟：装了但取不到额度"
            return quota
        }

        guard FileManager.default.fileExists(atPath: sessionsRoot.path) else {
            quota.error = "未找到 ~/.codex/sessions"
            return quota
        }

        // 换过账号的话，只认切换之后写入的会话日志——日志本身不记账号，
        // 否则会一直拿旧账号的额度当成当前账号的。
        let since = AccountTracker.shared.codexAccountSince()
        let files = recentSessionFiles(since: since)
        guard !files.isEmpty else {
            quota.error = since == nil ? "没有会话记录" : "账号刚切换，等待新会话"
            return quota
        }

        // 文件按最近修改排序，第一个能解析出有效额度的就是最新的
        for file in files {
            if let (rl, ts) = latestRateLimits(in: file) {
                quota.plan = rl.planType
                quota.primary = window(rl.primary)
                quota.secondary = window(rl.secondary)
                quota.updatedAt = ts
                return loggedOutIfNeeded(quota)
            }
        }
        quota.error = "会话日志里暂无额度数据"
        return quota
    }

    /// 登出之后，会话日志不会跟着删，里面那份额度属于上一个账号，再显示出来
    /// 就是误导：面板会一直挂着退出前的百分比，看不出「其实没登录」。
    ///
    /// 判据是 auth.json 里读不到账号（Codex CLI 登出时会删掉这个文件）。但不能
    /// 一读不到就判定登出：CLI 刷新 token、重写这个文件的瞬间也读不到。所以再加
    /// 一个条件，本地数据同时已经过期（超过 15 分钟没更新）才这么判。正在用的人
    /// 会话日志是新鲜的，不会被误伤。
    private func loggedOutIfNeeded(_ q: Quota) -> Quota {
        guard AccountTracker.shared.codexAccountId() == nil, q.isStale else { return q }
        var out = q
        out.plan = nil
        out.primary = nil
        out.secondary = nil
        out.updatedAt = nil
        out.error = "未登录 Codex"
        return out
    }

    private func window(_ w: Event.Window?) -> UsageWindow? {
        guard let w, let pct = w.usedPercent else { return nil }
        return UsageWindow(usedPercent: pct,
                           windowMinutes: w.windowMinutes ?? 0,
                           resetsAt: w.resetsAt.map { Date(timeIntervalSince1970: $0) })
    }

    /// 按最近修改时间列出会话文件
    /// - Parameter since: 只要这个时刻之后改动过的（账号切换分界），nil 表示不限
    private func recentSessionFiles(since: Date?) -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: sessionsRoot,
                                    includingPropertiesForKeys: [.contentModificationDateKey],
                                    options: [.skipsHiddenFiles]) else { return [] }
        var files: [(URL, Date)] = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if let since, date < since { continue }
            files.append((url, date))
        }
        return files.sorted { $0.1 > $1.1 }.prefix(maxFilesToScan).map(\.0)
    }

    /// 从文件尾部往前找最后一条带有效额度的记录
    private func latestRateLimits(in url: URL) -> (Event.RateLimits, Date)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }

        let readSize = min(size, tailBytes)
        guard (try? handle.seek(toOffset: size - readSize)) != nil,
              let data = try? handle.readToEnd() else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines = data.split(separator: UInt8(ascii: "\n"))
        // 截断读取时第一行多半是半截 JSON，丢掉
        if readSize == tailBytes, !lines.isEmpty { lines.removeFirst() }

        for line in lines.reversed() {
            guard line.count > 2,
                  let ev = try? decoder.decode(Event.self, from: Data(line)),
                  let rl = ev.payload?.rateLimits,
                  rl.primary != nil || rl.secondary != nil
            else { continue }
            let ts = ev.timestamp.flatMap { iso.date(from: $0) } ?? Date()
            return (rl, ts)
        }
        return nil
    }
}
