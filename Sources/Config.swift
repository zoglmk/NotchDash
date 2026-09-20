import Foundation

/// 自定义数据源：跑一条命令，把输出显示在面板上
struct CustomSource: Decodable {
    /// 面板上显示的标签
    var label: String
    /// 要执行的 shell 命令，取它的标准输出第一行
    var command: String
    /// 多少秒跑一次，最小 5 秒
    var interval: Double = 60
}

/// 配置文件 ~/.notchdash/config.json
/// 文件不存在时用默认值，不会报错
struct Config: Decodable {
    /// 本地数据过期时，是否允许用 OAuth API 兜底（会读取本机登录态、会联网）
    var oauthFallback: Bool = true
    /// true = 显示剩余额度（推荐，直接回答「还能用多少」）
    /// false = 显示已用额度
    var showRemaining: Bool = true
    /// 收起态的排布方式：
    /// "split" = 刘海左右各放一个（默认，对称好看）
    /// "left"  = 两个都放左边，面板不向刘海右侧伸出，不会压住右边的菜单栏图标
    var collapsedLayout: String = "split"
    /// 是否根据菜单栏实际占用自动挑排布（需要辅助功能权限，没授权则退回上面的手动设置）
    var autoLayout: Bool = true
    /// 是否已经弹过辅助功能授权请求。只弹一次，别反复打扰
    var accessibilityPromptShown: Bool = false
    /// 展开面板里额外显示的自定义数据
    var customSources: [CustomSource] = []

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".notchdash/config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return (try? d.decode(Config.self, from: data)) ?? Config()
    }
}
