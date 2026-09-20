import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var isExpanded = false
    @Published var quotas: [Quota] = []
    @Published var stats = SystemStats()
    @Published var custom: [String: String] = [:]
    /// 收起态单侧内容的实测宽度。放在这里而不是用 @State，是因为 @State 在
    /// Swift 6 里是宏，Command Line Tools 不带 SwiftUIMacros 插件，会编译不过。
    /// 左右两侧内容各自的实测宽度。必须分开存：两边内容宽度不同，
    /// 强行等宽会让窄的那侧在外缘多出一块黑边，肉眼很容易看出来。
    @Published var leftSlotWidth: CGFloat = 52
    @Published var rightSlotWidth: CGFloat = 52
    /// 靠左模式下「两个额度并排」的实测宽度。必须和上面两个分开存：
    /// 那两个记的是单个额度的宽度，拿来当并排宽度用会把内容裁掉。
    @Published var combinedWidth: CGFloat = 112
    /// 是否显示剩余额度（而不是已用）
    @Published var showRemaining: Bool = true
    /// 收起态排布："split" 左右分开 / "left" 全部靠左 / "below" 刘海正下方
    @Published var collapsedLayout: String = "split"
    /// 是否自动挑排布
    @Published var autoLayout: Bool = true
    /// 菜单栏两侧的剩余空间，nil 表示没有辅助功能权限、测不出来
    @Published var menuBarSpace: MenuBarProbe.Space?
    /// 点界面上那个按钮时弹菜单，由 AppDelegate 注入
    var onShowMenu: (() -> Void)?
    /// 截图自检时锁死展开状态，避免鼠标恰好悬停导致截到的不是想要的那一态
    var stateLocked = false

    /// 按 id 取额度，找不到返回 nil
    func quota(_ id: String) -> Quota? { quotas.first { $0.id == id } }
}

/// 额度 → 颜色。入参是**已用**百分比。
///
/// 档位直接取自进度条那套色标（usageRampStops），不另立一套阈值：
/// 两处各写各的迟早会对不上，出现「数字已经红了、进度条还是橙的」这种别扭情况。
///
/// 红色为什么调得偏粉：人眼对绿光最敏感、对红光最不敏感，同样饱和度下
/// 纯红在深色底上的感知亮度只有绿色的三分之二左右，看着发暗。
/// 提高红色的绿蓝分量，把感知亮度拉回到和其他几档相当的水平。
func usageColor(_ used: Double) -> Color {
    let r = remainingRatio(used)
    // 取最后一个起点不超过当前余量的色标
    var picked = usageRampStops[0].rgb
    for stop in usageRampStops where stop.at <= r {
        picked = stop.rgb
    }
    return Color(red: picked.r, green: picked.g, blue: picked.b)
}

/// 同一套色标，但在相邻档位之间线性插值，得到连续变化的颜色。
/// 进度条用它：整条的颜色由当前额度决定，而不是沿填充路径铺一条色带——
/// 那样「已用 100%」的条子会大半是绿的，完全看不出危险。
func usageColorSmooth(_ used: Double) -> Color {
    let r = remainingRatio(used)
    let stops = usageRampStops
    if r <= stops[0].at { return Color(red: stops[0].rgb.r, green: stops[0].rgb.g, blue: stops[0].rgb.b) }
    if let last = stops.last, r >= last.at {
        return Color(red: last.rgb.r, green: last.rgb.g, blue: last.rgb.b)
    }
    for i in 1..<stops.count where r <= stops[i].at {
        let lo = stops[i - 1], hi = stops[i]
        let span = hi.at - lo.at
        let t = span > 0 ? (r - lo.at) / span : 0
        return Color(red: lo.rgb.r + (hi.rgb.r - lo.rgb.r) * t,
                     green: lo.rgb.g + (hi.rgb.g - lo.rgb.g) * t,
                     blue: lo.rgb.b + (hi.rgb.b - lo.rgb.b) * t)
    }
    let last = stops[stops.count - 1]
    return Color(red: last.rgb.r, green: last.rgb.g, blue: last.rgb.b)
}

/// 进度条渐变的色标，按「剩余比例」标定：0 = 见底，1 = 满格。
///
/// 这几个位置没有客观标准，是按使用者的判断定的：剩余三成以上就算健康，
/// 剩下的区间再往危险端切三档。想调就改这里，数字和进度条会一起跟着变。
/// 存 RGB 分量而不是 Color，是为了能在色标之间做插值
let usageRampStops: [(rgb: (r: Double, g: Double, b: Double), at: Double)] = [
    ((1.00, 0.49, 0.46), 0.00),   // 剩余 <8%：红
    ((0.99, 0.55, 0.22), 0.08),   // 8~18%：橙
    ((0.98, 0.78, 0.25), 0.18),   // 18~30%：黄
    ((0.30, 0.85, 0.45), 0.30),   // ≥30%：绿
]

/// 把已用百分比换算成剩余比例（0~1）
private func remainingRatio(_ used: Double) -> Double {
    (100 - min(max(used, 0), 100)) / 100
}

