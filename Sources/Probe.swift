import Foundation
import AppKit

/// 命令行自检：不启动界面，直接把当前采集到的数据打印出来。
/// 用来确认数据链路是否通，以及排查「面板上数字不对」这类问题。
enum Probe {
    /// 只测 OAuth 兜底通道，绕开本地主通道。
    /// 用来确认钥匙串读取、token 有效性、端点连通性是否正常。
    static func runOAuthOnly() {
        print("OAuth 兜底通道单独测试")
        print(String(repeating: "─", count: 52))
        let oauth = OAuthUsageProvider()
        for (name, q) in [("Claude Code", oauth.fetchClaude()), ("Codex", oauth.fetchCodex())] {
            guard let q else {
                print("  \(name): ✗ 失败（拿不到 token、token 已过期、端点变更或网络不通）")
                continue
            }
            print("  \(name): ✓ 成功  [来源: \(q.source)]\(q.plan.map { "  套餐 \($0)" } ?? "")")
            for (tag, w) in [("短窗口", q.primary), ("长窗口", q.secondary)] {
                guard let w else { continue }
                print(String(format: "    %@ (%@) %5.1f%%   %@", tag, w.label, w.usedPercent,
                             w.resetText.map { "\($0)后重置" } ?? ""))
            }
        }
        print(String(repeating: "─", count: 52))
    }

    /// 菜单栏空间自检
    static func run() {
        print("NotchDash 数据自检")
        print(String(repeating: "─", count: 52))

        // CPU 要两次采样求差，先打一针基线
        let sys = SystemStatsProvider()
        _ = sys.sample()
        Thread.sleep(forTimeInterval: 0.6)
        let s = sys.sample()
        print("【系统状态】")
        print(String(format: "  CPU      %.1f%%", s.cpuPercent))
        print(String(format: "  内存     %.1f%%  (%.1f / %.1f GB)",
                     s.memoryPercent, s.memoryUsedGB, s.memoryTotalGB))
        if let b = s.batteryPercent {
            print("  电池     \(b)%\(s.batteryCharging ? " (充电中)" : "")"
                  + (s.batteryTimeLeft.map { "  剩余 \($0)" } ?? ""))
        } else {
            print("  电池     无（台式机或读取失败）")
        }
        print("  网速     ↓ \(SystemStats.rate(s.netDownBytes))/s   ↑ \(SystemStats.rate(s.netUpBytes))/s")

        let cfg = Config.load()
        print("\n【配置】 \(FileManager.default.fileExists(atPath: Config.url.path) ? Config.url.path : "使用默认值（无配置文件）")")
        print("  OAuth 兜底: \(cfg.oauthFallback ? "开启" : "关闭")   自定义数据源: \(cfg.customSources.count) 个")

        print("\n【额度】")
        // 跟面板同一套判据：没装的通道不采集，也不显示。这里额外把原因打出来，
        // 否则面板上少了一项，来跑自检却什么都看不出来
        var list: [Quota] = []
        for (name, installed, dir, make) in [
            ("Claude Code", ClaudeUsageProvider.isInstalled, "~/.claude",
             { ClaudeUsageProvider().fetch() }),
            ("Codex", CodexUsageProvider.isInstalled, "~/.codex",
             { CodexUsageProvider().fetch() }),
        ] as [(String, Bool, String, () -> Quota)] {
            if installed { list.append(make()) }
            else { print("  \(name)  未安装（\(dir) 不存在），面板上不会显示这一项") }
        }
        if list.isEmpty {
            print("  两个都没装，收起态会改显示 CPU 和内存")
        }
        if cfg.oauthFallback {
            let oauth = OAuthUsageProvider()
            for i in list.indices where list[i].error != nil || list[i].isStale {
                print("  ↻ \(list[i].name) 本地数据不可用/已过期，尝试 API 兜底…")
                if let fb = list[i].id == "claude" ? oauth.fetchClaude() : oauth.fetchCodex() {
                    list[i] = fb
                    print("    ✓ 兜底成功")
                } else {
                    print("    ✗ 兜底失败，保留本地数据")
                }
            }
        }
        for q in list {
            print("  \(q.name)  [来源: \(q.source)]")
            if let e = q.error {
                print("    ⚠️  \(e)")
                continue
            }
            if let p = q.plan { print("    套餐: \(p)") }
            for (tag, w) in [("短窗口", q.primary), ("长窗口", q.secondary)] {
                guard let w else { continue }
                let filled = Int(min(w.usedPercent, 100) / 10)
                let bar = String(repeating: "█", count: filled)
                        + String(repeating: "░", count: 10 - filled)
                print(String(format: "    %@ (%@) %@ %5.1f%%   %@",
                             tag, w.label, bar, w.usedPercent, w.resetText.map { "\($0)后重置" } ?? ""))
            }
            print("    更新于: \(q.staleText ?? "未知")\(q.isStale ? "  ⚠️ 已过期" : "")")
        }
        if !cfg.stocks.items.isEmpty {
            print("\n【行情】每 \(Int(max(cfg.stocks.interval, 10))) 秒刷新")
            let quotes = StockProvider().fetch(cfg.stocks)
            for item in cfg.stocks.items {
                print("  \(item.label) = \(quotes[item.label] ?? "—")   ← \(item.code)")
            }
        }
        if !cfg.customSources.isEmpty {
            print("\n【自定义数据源】")
            let values = CustomSourceProvider().fetch(cfg.customSources)
            for src in cfg.customSources {
                print("  \(src.label) = \(values[src.label] ?? "—")   ← \(src.command)")
            }
        }
        print(String(repeating: "─", count: 52))
    }
}
