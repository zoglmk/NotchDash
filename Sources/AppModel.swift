import SwiftUI

/// 底部那行的一个条目
struct DisplayItem: Identifiable, Equatable {
    let id: Int
    let label: String
    let value: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var isExpanded = false
    @Published var quotas: [Quota] = []
    @Published var stats = SystemStats()
    /// 展开面板底部那行要显示的条目。用数组而不是字典，
    /// 否则显示顺序由字母序决定，跟配置里写的顺序对不上。
    @Published var custom: [DisplayItem] = []
    /// 收起态单侧内容的实测宽度。放在这里而不是用 @State，是因为 @State 在
    /// Swift 6 里是宏，Command Line Tools 不带 SwiftUIMacros 插件，会编译不过。
    /// 左右两侧内容各自的实测宽度。必须分开存：两边内容宽度不同，
    /// 强行等宽会让窄的那侧在外缘多出一块黑边，肉眼很容易看出来。
    @Published var leftSlotWidth: CGFloat = 52
    @Published var rightSlotWidth: CGFloat = 52
    /// 靠左模式下「两个额度并排」的实测宽度。必须和上面两个分开存：
    /// 那两个记的是单个额度的宽度，拿来当并排宽度用会把内容裁掉。
    @Published var combinedWidth: CGFloat = 112
    /// 展开态底部那一行（系统状态 + 自定义数据源）的自然宽度。
    /// 自定义数据源是用户自己加的，多少、多长都不可预知，面板得跟着它变宽。
    @Published var statsRowWidth: CGFloat = 0
    /// 是否显示剩余额度（而不是已用）
    @Published var showRemaining: Bool = true
    /// 收起态排布："split" 左右分开 / "left" 全部靠左 / "below" 刘海正下方
    @Published var collapsedLayout: String = "split"
    /// 是否自动挑排布
    @Published var autoLayout: Bool = true
    /// 涨跌配色：true = 红涨绿跌
    @Published var redUp: Bool = true
    /// 菜单栏两侧的剩余空间，nil 表示没有辅助功能权限、测不出来
    @Published var menuBarSpace: MenuBarProbe.Space?
    /// 点界面上那个按钮时弹菜单，由 AppDelegate 注入
    var onShowMenu: (() -> Void)?
    /// 截图自检时锁死展开状态，避免鼠标恰好悬停导致截到的不是想要的那一态
    var stateLocked = false

    /// 按 id 取额度，找不到返回 nil
    func quota(_ id: String) -> Quota? { quotas.first { $0.id == id } }
}

/// 额度 → 颜色。入参是**已用**百分比，数字和进度条共用。
///
/// 红色为什么调得偏粉：人眼对绿光最敏感、对红光最不敏感，同样饱和度下
/// 纯红在深色底上的感知亮度只有绿色的三分之二左右，看着发暗。
/// 提高红色的绿蓝分量，把感知亮度拉回到和绿色相当的水平。
/// 从自定义数据源的输出里认出涨跌幅，如「3912 +0.94%」里的 +0.94。
/// 认不出（没有带符号的百分比）就返回 nil，按普通文本显示。
func changeValue(in text: String) -> Double? {
    guard let r = text.range(of: #"[+-][0-9]+(\.[0-9]+)?%"#, options: .regularExpression) else {
        return nil
    }
    return Double(text[r].dropLast())
}

func usageColor(_ used: Double) -> Color {
    remainingRatio(used) >= usageSafeThreshold ? usageSafeColor : usageDangerColor
}

/// 进度条渐变的色标，按「剩余比例」标定：0 = 见底，1 = 满格。
///
/// 这几个位置没有客观标准，是按使用者的判断定的：剩余三成以上就算健康，
/// 剩下的区间再往危险端切三档。想调就改这里，数字和进度条会一起跟着变。
/// 只有两个状态：够用（绿）和不够用（红）。中间不设过渡档——
/// 额度这件事本来就是二元的，黄橙只会让人多花一秒去分辨「这算警告还是危险」。
/// 门槛：剩余 30%。
let usageSafeThreshold = 0.30
let usageDangerColor = Color(red: 1.00, green: 0.49, blue: 0.46)
let usageSafeColor = Color(red: 0.30, green: 0.85, blue: 0.45)

/// 把已用百分比换算成剩余比例（0~1）
private func remainingRatio(_ used: Double) -> Double {
    (100 - min(max(used, 0), 100)) / 100
}

