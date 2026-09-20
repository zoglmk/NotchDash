import Foundation

/// statusline 旁路落盘：Claude Code 每次刷新状态栏都会把一包 JSON 喂到 stdin，
/// 里面含官方的 rate_limits。这里把它抄一份存成快照，供刘海面板读取。
/// 只读不写 Claude Code 的任何东西，也不联网。
enum StatuslineTee {
    static func run() {
        guard let data = try? FileHandle.standardInput.readToEnd(), !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // 官方在某些构建/订阅层级下会省略 rate_limits。
        // 这种情况保持旧快照不动，否则刚拿到的额度会被一包空数据冲掉。
        guard let rl = obj["rate_limits"] as? [String: Any] else { return }

        var snapshot: [String: Any] = [:]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        snapshot["updated_at"] = iso.string(from: Date())

        var gotAny = false
        for key in ["five_hour", "seven_day"] {
            guard let w = rl[key] as? [String: Any] else { continue }
            var out: [String: Any] = [:]
            if let p = w["used_percentage"] as? Double { out["used_percentage"] = p; gotAny = true }
            else if let p = w["used_percentage"] as? Int { out["used_percentage"] = Double(p); gotAny = true }
            if let r = w["resets_at"] { out["resets_at"] = r }
            if !out.isEmpty { snapshot[key] = out }
        }
        guard gotAny else { return }

        // 顺带存一点上下文，排查问题时有用
        if let model = obj["model"] as? [String: Any],
           let name = model["display_name"] as? String { snapshot["model"] = name }
        if let cost = obj["cost"] as? [String: Any],
           let usd = cost["total_cost_usd"] as? Double { snapshot["session_cost_usd"] = usd }

        write(snapshot)
    }

    private static func write(_ snapshot: [String: Any]) {
        let url = ClaudeUsageProvider.snapshotURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return }
        // 先写临时文件再原子替换，避免面板读到写了一半的 JSON
        let tmp = dir.appendingPathComponent("claude-usage.json.tmp")
        do {
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? data.write(to: url)
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}
