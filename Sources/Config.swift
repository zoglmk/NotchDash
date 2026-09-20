import Foundation

/// 自定义数据源：跑一条命令，把输出显示在面板上
struct CustomSource: Decodable {
    /// 面板上显示的标签
    var label: String
    /// 要执行的 shell 命令，取它的标准输出第一行
    var command: String
    /// 多少秒跑一次，最小 5 秒
    var interval: Double = 60

    enum CodingKeys: String, CodingKey { case label, command, interval }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        command = try c.decode(String.self, forKey: .command)
        interval = try c.decodeIfPresent(Double.self, forKey: .interval) ?? 60
    }
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
    /// "left"  = 两个都放左边，面板不向刘海右侧伸出
    /// "below" = 收到刘海正下方，完全不占菜单栏
    var collapsedLayout: String = "split"
    /// 是否根据菜单栏实际占用自动挑排布（需要辅助功能权限）
    var autoLayout: Bool = true
    /// 是否已经弹过辅助功能授权请求。只弹一次，别反复打扰
    var accessibilityPromptShown: Bool = false
    /// 自定义数据源里涨跌的配色：true = 红涨绿跌（A 股习惯），false = 绿涨红跌
    var redUp: Bool = true
    /// 展开面板里额外显示的自定义数据
    var customSources: [CustomSource] = []

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".notchdash/config.json")

    init() {}

    /// 手写解码，逐项 decodeIfPresent。
    ///
    /// 不能用合成的 Decodable：它在 JSON 缺字段时直接抛错，**不会**回退到
    /// 属性默认值。那样每新增一个配置项，所有旧配置文件都会整个解析失败、
    /// 退回全默认值——用户的自定义数据源会毫无征兆地消失。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        oauthFallback = try c.decodeIfPresent(Bool.self, forKey: .oauthFallback) ?? true
        showRemaining = try c.decodeIfPresent(Bool.self, forKey: .showRemaining) ?? true
        collapsedLayout = try c.decodeIfPresent(String.self, forKey: .collapsedLayout) ?? "split"
        autoLayout = try c.decodeIfPresent(Bool.self, forKey: .autoLayout) ?? true
        accessibilityPromptShown = try c.decodeIfPresent(Bool.self, forKey: .accessibilityPromptShown) ?? false
        redUp = try c.decodeIfPresent(Bool.self, forKey: .redUp) ?? true
        customSources = try c.decodeIfPresent([CustomSource].self, forKey: .customSources) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case oauthFallback, showRemaining, collapsedLayout, autoLayout
        case accessibilityPromptShown, redUp, customSources
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url) else { return Config() }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return (try? d.decode(Config.self, from: data)) ?? Config()
    }
}
