import Foundation

/// 账号切换追踪。
///
/// 起因：Codex 的会话日志里没有任何账号字段（session_meta 只有 session_id、cwd、
/// 模型等），换账号之后旧账号的日志照样会被读到，而且只要它足够新鲜就不会触发
/// API 兜底去纠正，额度能一直显示错的。
///
/// 办法是拿 auth.json 里的 account_id 当锚点：一旦它变了，就记下切换时刻，
/// 此后只认这个时刻之后写入的会话日志。
final class AccountTracker: @unchecked Sendable {
    static let shared = AccountTracker()

    private let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".notchdash/state.json")
    private let lock = NSLock()

    /// 当前 Codex 账号的 id，读不到返回 nil
    func codexAccountId() -> String? {
        if Simulate.on("codex-logout") { return nil }
        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any]
        else { return nil }
        return (tokens["accountId"] as? String) ?? (tokens["account_id"] as? String)
    }

    /// 记录当前账号，返回「这个账号是从什么时候开始用的」。
    /// 账号没变就沿用原时间；变了就以此刻为界。
    /// - Returns: 分界时刻；无法确定账号时返回 nil（表示不做过滤）
    func codexAccountSince() -> Date? {
        guard let current = codexAccountId() else { return nil }
        lock.lock()
        defer { lock.unlock() }

        var state = loadState()
        let known = state["codex_account_id"] as? String
        if known == current, let since = state["codex_account_since"] as? Double {
            return Date(timeIntervalSince1970: since)
        }

        // 首次记录，或账号确实换了
        let now = Date()
        state["codex_account_id"] = current
        state["codex_account_since"] = now.timeIntervalSince1970
        state["codex_account_switched"] = (known != nil && known != current)
        saveState(state)
        // 首次记录时不过滤历史日志，只有确认换过账号才以此刻为界
        return known == nil ? nil : now
    }

    /// 账号是否刚刚换过（供上层决定要不要清掉 API 结果缓存）
    func consumeCodexSwitchFlag() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var state = loadState()
        let flag = state["codex_account_switched"] as? Bool ?? false
        if flag {
            state["codex_account_switched"] = false
            saveState(state)
        }
        return flag
    }

    private func loadState() -> [String: Any] {
        guard let data = try? Data(contentsOf: stateURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private func saveState(_ state: [String: Any]) {
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: state,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: stateURL)
    }
}
