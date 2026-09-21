import SwiftUI
import AppKit

/// 收起态那个「标签 + 数值」小块的排版常量。
/// 宽度预算和实际绘制共用这一套数字，分开写迟早会对不上。
enum ChipMetrics {
    /// 标签和数值之间的间距
    static let labelValueSpacing: CGFloat = 4
    /// 并排两个条目之间的间距
    static let itemSpacing: CGFloat = 14
    static let labelSize: CGFloat = 9
    static let valueSize: CGFloat = 11
}

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
    @Published var leftSlotWidths: [Int: CGFloat] = [:]
    @Published var rightSlotWidths: [Int: CGFloat] = [:]
    /// 同上，只认额度页的宽度
    var leftSlotWidth: CGFloat { leftSlotWidths[0] ?? 52 }
    var rightSlotWidth: CGFloat { rightSlotWidths[0] ?? 52 }
    /// 靠左模式下「两个额度并排」的实测宽度。必须和上面两个分开存：
    /// 那两个记的是单个额度的宽度，拿来当并排宽度用会把内容裁掉。
    /// 各页内容的实测宽度（键是页码）。
    ///
    /// 面板宽度取各页最大值，不跟着当前页走：轮播时黑条必须纹丝不动，
    /// 否则一胀一缩比不轮播还晃眼。
    ///
    /// 也不能只认额度页。「行情页本来就比额度页窄」这个前提不成立：额度页
    /// 宽度随百分比位数在 100~130pt 之间浮动，而行情标签长度由用户决定，
    /// 「沪深300 4525 +0.38%」实测 118pt，比「CC 55% Codex 71%」的 115pt 还宽，
    /// 个股（「贵州茅台 1680 +1.23%」127pt）只会更长。锁死在额度页会让这些
    /// 内容溢出，左边留白被吃掉，文字贴到黑条边缘上。
    @Published var combinedWidths: [Int: CGFloat] = [:]
    /// 面板宽度 = 各页里最宽的那页。
    ///
    /// 每页优先用 SwiftUI 的实测值；还没轮播到、因而没测过的页用文本预算值兜底。
    /// 没有这个兜底，黑条就得等轮播转到那一页才知道自己该多宽，于是启动后第一圈
    /// 会被一格格撑大，加个股、额度见底改显示倒计时时也会各撑一次。
    var combinedWidth: CGFloat {
        let widths = (0..<carouselPageCount).map { page in
            combinedWidths[page] ?? estimatedWidth(forPage: page)
        }
        return max(widths.max() ?? 0, 112)
    }
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
    /// 这台机器装没装 Claude Code / Codex。两个都没装时额度那一项根本不会出现，
    /// 收起态改显示系统状态，免得留一块空白黑条。启动时就测好，不等第一轮刷新，
    /// 否则头几秒会先空一下再跳出内容。
    @Published var hasAnyQuotaSource: Bool = true
    /// 收起态是否轮换显示额度与行情
    @Published var carousel: Bool = false
    /// 当前轮到第几页：0 是额度，之后每页两个行情
    @Published var carouselPage: Int = 0

    /// 行情每页放几个。一次一个，黑条就不会被撑长。
    static let itemsPerPage = 1

    /// 一共几页：额度一页，行情每两个一页
    var carouselPageCount: Int {
        guard carousel, !custom.isEmpty else { return 1 }
        return 1 + (custom.count + Self.itemsPerPage - 1) / Self.itemsPerPage
    }
    /// 菜单栏两侧的剩余空间，nil 表示没有辅助功能权限、测不出来
    @Published var menuBarSpace: MenuBarProbe.Space?
    /// 点界面上那个按钮时弹菜单，由 AppDelegate 注入
    var onShowMenu: (() -> Void)?
    /// 截图自检时锁死展开状态，避免鼠标恰好悬停导致截到的不是想要的那一态
    var stateLocked = false

    /// 按 id 取额度，找不到返回 nil
    func quota(_ id: String) -> Quota? { quotas.first { $0.id == id } }

    /// 收起态第 page 页要显示的条目。page 0 是额度，之后每页放 itemsPerPage 个行情。
    ///
    /// 放在 model 而不是 view 里，是因为宽度预算也要用它：两边各写一份的话，
    /// 改了显示规则而忘了改预算，黑条就会按错的内容算宽度。
    func items(forPage page: Int) -> [(label: String, value: String, color: Color)] {
        if carousel, page > 0, !custom.isEmpty {
            let start = (page - 1) * Self.itemsPerPage
            guard start < custom.count else { return [] }
            return custom[start..<min(start + Self.itemsPerPage, custom.count)].map {
                ($0.label, $0.value, changeColor($0.value) ?? .white.opacity(0.9))
            }
        }
        let quotaItems = ["claude", "codex"].compactMap { id -> (String, String, Color)? in
            guard let q = quota(id), let used = q.headlinePercent else { return nil }
            let shown = showRemaining ? 100 - used : used
            return (q.short, q.headlineText ?? "\(Int(shown.rounded()))%", usageColor(used))
        }
        if !quotaItems.isEmpty { return quotaItems }

        // 一个额度都拿不到。装了只是暂时没数据（刚启动、没配 statusline）就先留空，
        // 几秒后自己会有；确认没装才退回系统状态——只想看行情的人不该对着
        // 一块空白黑条，而 CPU 和内存任何机器上都读得到。
        guard !hasAnyQuotaSource else { return [] }
        return [("CPU", String(format: "%.0f%%", stats.cpuPercent), .white.opacity(0.9)),
                ("内存", String(format: "%.0f%%", stats.memoryPercent), .white.opacity(0.9))]
    }

    /// 下一个有内容的页。
    ///
    /// 没装 Claude Code / Codex 又配了行情时，额度页是空的，轮到它只会让面板
    /// 空白几秒，直接跳过去。全部都空就别动，免得空转。
    func nextCarouselPage() -> Int {
        let count = carouselPageCount
        guard count > 1 else { return 0 }
        for step in 1...count {
            let next = (carouselPage + step) % count
            if !items(forPage: next).isEmpty { return next }
        }
        return carouselPage
    }

    /// 文本里带涨跌幅就按涨跌上色，平盘和普通文本保持原样
    func changeColor(_ value: String) -> Color? {
        guard let v = changeValue(in: value), v != 0 else { return nil }
        return (v > 0) == redUp ? usageDangerColor : usageSafeColor
    }

    /// 不等 SwiftUI 渲染，直接按文本算出某一页的内容宽度。
    ///
    /// 和实测值的偏差：四组真实内容对照下来，这个算法稳定比 SwiftUI 小
    /// 0.3~0.6pt，方向一致，所以补一个常量。宁可多零点几个点的留白，
    /// 也不要算小了让文字贴到黑条边缘上。
    func estimatedWidth(forPage page: Int) -> CGFloat {
        let items = items(forPage: page)
        guard !items.isEmpty else { return 0 }
        let chips = items.reduce(CGFloat(0)) { $0 + Self.chipWidth(label: $1.label, value: $1.value) }
        let gaps = CGFloat(items.count - 1) * ChipMetrics.itemSpacing
        return chips + gaps + Self.estimateSlack
    }

    /// 预算补偿，见 estimatedWidth 的说明
    private static let estimateSlack: CGFloat = 1

    /// 一个「标签 + 数值」小块的宽度
    static func chipWidth(label: String, value: String) -> CGFloat {
        textWidth(label, font: roundedFont(ChipMetrics.labelSize, .bold))
            + ChipMetrics.labelValueSpacing
            + textWidth(value, font: roundedDigitFont(ChipMetrics.valueSize, .semibold))
    }

    private static func textWidth(_ s: String, font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    /// 对应 SwiftUI 的 .system(size:weight:design: .rounded)
    private static func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: d, size: size) ?? base
    }

    /// 同上，再加 .monospacedDigit()。数值用等宽数字，否则 11% 和 88% 不一样宽
    private static func roundedDigitFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: d, size: size) ?? base
    }

    /// 当前页没内容就立刻跳走。
    ///
    /// nextCarouselPage 只在计时器翻页时才跑，而 carouselPage 初始就是 0。
    /// 额度页要是一直没内容（装了 Claude Code 但既没配 statusline 也没登录），
    /// 启动后得干等一个轮播间隔面板才会跳到行情，这期间是一块纯黑。
    /// 所以数据一到位就检查一次。
    func skipEmptyPageIfNeeded() {
        guard carousel, items(forPage: carouselPage).isEmpty else { return }
        let next = nextCarouselPage()
        if next != carouselPage { carouselPage = next }
    }

    /// 丢掉超出当前页数的实测宽度。
    ///
    /// 宽度改成取各页最大值之后，这一步是必须的：关掉轮播、或者删掉一个行情
    /// 标的之后，那一页的宽度还留在字典里，黑条就再也缩不回去了。
    func pruneWidths() {
        let count = carouselPageCount
        func prune(_ d: inout [Int: CGFloat]) {
            guard d.keys.contains(where: { $0 < 0 || $0 >= count }) else { return }
            d = d.filter { (0..<count).contains($0.key) }
        }
        prune(&combinedWidths)
        prune(&leftSlotWidths)
        prune(&rightSlotWidths)
    }
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

