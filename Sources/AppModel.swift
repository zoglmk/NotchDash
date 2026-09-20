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

/// 百分比 → 颜色：越接近用满越红
///
/// 红色为什么调得偏粉：人眼对绿光最敏感、对红光最不敏感，同样饱和度下
/// 纯红在黑底上的感知亮度只有绿色的三分之二左右，看着发暗。
/// 提高红色的绿蓝分量把感知亮度拉回到和其他几档相当的水平。
func usageColor(_ pct: Double) -> Color {
    switch pct {
    case ..<50:  return Color(red: 0.30, green: 0.85, blue: 0.45)   // 感知亮度 ≈180
    case ..<80:  return Color(red: 0.98, green: 0.78, blue: 0.25)   // ≈200
    case ..<95:  return Color(red: 0.99, green: 0.55, blue: 0.22)   // ≈158
    default:     return Color(red: 1.00, green: 0.49, blue: 0.46)   // ≈150（原来只有 123）
    }
}

/// 用满时把字加粗，光靠颜色不够抓眼
func usageWeight(_ pct: Double) -> Font.Weight {
    pct >= 95 ? .bold : .semibold
}
