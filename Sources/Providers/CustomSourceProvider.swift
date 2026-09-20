import Foundation

/// 自定义数据源采集：按配置执行命令，取输出显示。
///
/// 注意：命令来自你自己的 ~/.notchdash/config.json，等同于你在终端里手敲，
/// 所以别把不信任的配置文件放进来。
final class CustomSourceProvider: @unchecked Sendable {
    private var cache: [String: (value: String, at: Date)] = [:]
    /// 单条命令最多跑这么久，超时就放弃，免得拖住采集队列
    private let timeout: TimeInterval = 5

    func fetch(_ sources: [CustomSource]) -> [String: String] {
        var out: [String: String] = [:]
        for src in sources {
            let interval = max(src.interval, 5)
            if let c = cache[src.label], Date().timeIntervalSince(c.at) < interval {
                out[src.label] = c.value
                continue
            }
            let value = run(src.command) ?? "—"
            cache[src.label] = (value, Date())
            out[src.label] = value
        }
        return out
    }

    private func run(_ command: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }

        // 超时保护：到点还没结束就干掉它
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if p.isRunning { p.terminate(); return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        // 只取第一行，面板放不下多行
        let line = s.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? nil : String(line.prefix(24))
    }
}
