import Foundation

/// 调试开关：伪造一些没法在本机安全复现的环境。
///
/// 起因是这几种情况都要动真实的家目录才能测：没装 Claude Code 要删 ~/.claude，
/// Codex 登出要删 ~/.codex/auth.json。在开发机上删这些代价太大，所以留一个
/// 环境变量的口子，只影响判定结果，不碰任何文件。
///
///     NOTCHDASH_SIMULATE=no-quota      假装本机没装 Claude Code 和 Codex
///     NOTCHDASH_SIMULATE=codex-logout  假装 Codex 已登出
///
/// 多个用逗号分隔。不设这个变量时一切照旧，所以不影响正常运行。
enum Simulate {
    static func on(_ name: String) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["NOTCHDASH_SIMULATE"] else { return false }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains(name)
    }
}
