import Foundation

/// OAuth 兜底通道：直接问官方要额度，不依赖 Claude Code / Codex 是否正在运行。
///
/// 安全说明：
/// - token 只从本机既有的登录态里读（Claude 走钥匙串，Codex 走 ~/.codex/auth.json），
///   本程序不保存、不落盘、不外传，只发给各自的官方域名。
/// - 用的是未公开端点，官方改动就可能失效，因此它只是「兜底」，主通道永远优先。
/// - 默认只在本地数据过期时才请求，并且有最小请求间隔，避免频繁弹钥匙串授权。
final class OAuthUsageProvider: @unchecked Sendable {
    /// 两次请求之间至少隔这么久
    private let minInterval: TimeInterval = 300
    private var lastClaudeFetch: Date?
    private var lastCodexFetch: Date?
    /// 上一次成功拿到的结果。限流期间要把它交回去，不能返回 nil——
    /// 否则调用方会退回那份早就过期的本地数据，界面就会以限流周期明暗交替。
    private var lastClaudeResult: Quota?
    private var lastCodexResult: Quota?
    private let timeout: TimeInterval = 8

    // MARK: - Claude

    func fetchClaude() -> Quota? {
        guard shouldFetch(last: lastClaudeFetch) else { return lastClaudeResult }
        lastClaudeFetch = Date()

        guard let token = claudeAccessToken() else { return lastClaudeResult }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = timeout

        guard let data = send(req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return lastClaudeResult }

        var q = Quota(id: "claude", name: "Claude Code", short: "CC", plan: nil,
                      primary: nil, secondary: nil, updatedAt: Date(),
                      source: "官方 API", error: nil)
        // 注意：这个端点用的是 utilization，跟 statusline 的 used_percentage 不是同一个字段名
        q.primary = oauthWindow(obj["five_hour"], minutes: 300)
        q.secondary = oauthWindow(obj["seven_day"], minutes: 10080)
        guard q.primary != nil || q.secondary != nil else { return lastClaudeResult }
        lastClaudeResult = q
        return q
    }

    private func oauthWindow(_ raw: Any?, minutes: Int) -> UsageWindow? {
        guard let d = raw as? [String: Any] else { return nil }
        let pct = (d["utilization"] as? Double) ?? (d["utilization"] as? Int).map(Double.init)
        guard let pct else { return nil }
        var reset: Date?
        if let s = d["resets_at"] as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            reset = iso.date(from: s) ?? {
                iso.formatOptions = [.withInternetDateTime]
                return iso.date(from: s)
            }()
        }
        return UsageWindow(usedPercent: pct, windowMinutes: minutes, resetsAt: reset)
    }

    /// 从钥匙串取 Claude Code 的登录态。不自己做 token 刷新：
    /// Claude Code 会在过期前自动续期并写回钥匙串，这里每次重新读即可。
    private func claudeAccessToken() -> String? {
        guard let raw = runSecurity(service: "Claude Code-credentials"),
              let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { return nil }
        // 已过期就别发了，省得白白拿个 401
        if let exp = oauth["expiresAt"] as? Double,
           Date(timeIntervalSince1970: exp / 1000) < Date() { return nil }
        return token
    }

    private func runSecurity(service: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Codex

    func fetchCodex() -> Quota? {
        // 刚换过账号：缓存里是上一个账号的额度，作废并立刻重新请求
        if AccountTracker.shared.consumeCodexSwitchFlag() {
            lastCodexResult = nil
            lastCodexFetch = nil
        }
        guard shouldFetch(last: lastCodexFetch) else { return lastCodexResult }
        lastCodexFetch = Date()

        let authURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: authURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = obj["tokens"] as? [String: Any],
              let token = tokens["accessToken"] as? String ?? tokens["access_token"] as? String
        else { return lastCodexResult }
        let account = (tokens["accountId"] as? String) ?? (tokens["account_id"] as? String) ?? ""

        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !account.isEmpty { req.setValue(account, forHTTPHeaderField: "chatgpt-account-id") }
        req.timeoutInterval = timeout

        guard let body = send(req),
              let r = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let rl = r["rate_limit"] as? [String: Any]
        else { return lastCodexResult }

        var q = Quota(id: "codex", name: "Codex", short: "Codex",
                      plan: r["plan_type"] as? String,
                      primary: nil, secondary: nil, updatedAt: Date(),
                      source: "官方 API", error: nil)
        q.primary = whamWindow(rl["primary_window"])
        q.secondary = whamWindow(rl["secondary_window"])
        guard q.primary != nil || q.secondary != nil else { return lastCodexResult }
        lastCodexResult = q
        return q
    }

    private func whamWindow(_ raw: Any?) -> UsageWindow? {
        guard let d = raw as? [String: Any] else { return nil }
        let pct = (d["used_percent"] as? Double) ?? (d["used_percent"] as? Int).map(Double.init)
        guard let pct else { return nil }
        let seconds = (d["limit_window_seconds"] as? Int) ?? 0
        var reset: Date?
        if let at = d["reset_at"] as? Double { reset = Date(timeIntervalSince1970: at) }
        else if let after = d["reset_after_seconds"] as? Double { reset = Date().addingTimeInterval(after) }
        return UsageWindow(usedPercent: pct, windowMinutes: seconds / 60, resetsAt: reset)
    }

    // MARK: - 公共

    private func shouldFetch(last: Date?) -> Bool {
        guard let last else { return true }
        return Date().timeIntervalSince(last) >= minInterval
    }

    /// 同步发请求。调用方始终在后台串行队列上，不会卡界面。
    private func send(_ req: URLRequest) -> Data? {
        let sem = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: req) { data, response, _ in
            defer { sem.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            result = data
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 2)
        return result
    }
}
