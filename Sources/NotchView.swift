import SwiftUI

struct NotchView: View {
    @ObservedObject var model: AppModel
    let geo: NotchGeometry

    /// 收起态两翼宽度不写死：实测左右两块内容的自然宽度（见 model.measuredSlot），
    /// 取较大者对称展开，这样换机型、改缩放、换字体、内容变长都不会被裁掉。
    /// 兜底下限，避免首帧测量到 0 时面板闪一下
    private let minSlotContent: CGFloat = 52

    /// 展开宽度：先按屏幕定个基准，再保证底部那行内容放得下（自定义数据源
    /// 数量和长度都由用户决定），最后不超过屏幕宽度。
    private var expandedWidth: CGFloat {
        let base = min(max(geo.screen.frame.width * 0.30, 430), 600)
        let needed = model.statsRowWidth + detailPadding * 2 + 16
        return min(max(base, needed), geo.screen.frame.width - 60)
    }
    /// 展开态内容的左右内边距
    private let detailPadding: CGFloat = 22
    /// 内容与刘海之间的水平留白
    private let gutter: CGFloat = 8
    /// 顶部反向圆角半径。注意：形状的黑色主体宽度只有 width - 2*topRadius，
    /// 内容必须往里缩这么多，否则会画到黑色区域之外。
    private let topRadius: CGFloat = 10
    /// 内容与面板外缘之间的视觉留白。没有它内容会正好压在黑色形状的边界上。
    private let edgeInset: CGFloat = 7

    private var isExpanded: Bool { model.isExpanded }
    /// 单侧翼宽 = 该侧内容实测宽度 + 与刘海的留白 + 反向圆角 + 外缘留白
    ///
    /// 注意这里不能写成 max(content, minSlotContent)：那样会把两侧一起抬到同一个
    /// 下限，窄的一侧就凭空多出一块黑边，独立贴合等于白做。下限只在首帧
    /// （还没测到宽度，content 为 0）时兜底。
    private func wingWidth(_ content: CGFloat) -> CGFloat {
        (content > 0 ? content : minSlotContent) + gutter + topRadius + edgeInset
    }
    /// 实际生效的排布。开了自动就按菜单栏实测空间挑，否则用手动设置的。
    private var layout: String {
        guard model.autoLayout, let space = model.menuBarSpace else { return model.collapsedLayout }
        // 左右分开：右侧要放得下右翼，左侧要放得下左翼
        if space.right >= wingWidth(model.rightSlotWidth),
           space.left >= wingWidth(model.leftSlotWidth) { return "split" }
        // 全部靠左：左侧要放得下两个额度并排
        if space.left >= wingWidth(model.combinedWidth) { return "left" }
        // 两侧都挤不下，只能收到刘海正下方
        return "below"
    }
    /// 靠左模式下两个额度之间的间距
    private let bothSpacing: CGFloat = 14

    /// 全部靠左模式：右侧不伸出，避免压住菜单栏右边那排图标
    private var leftOnly: Bool { !isExpanded && layout == "left" }
    /// 刘海正下方模式：面板不超出刘海宽度，完全不占菜单栏那一行。
    /// 菜单栏图标排满右侧后会跳过刘海继续往左排，所以只有这个模式是绝对不会撞车的。
    private var belowMode: Bool { !isExpanded && layout == "below" }
    /// 正下方模式里那一行内容的高度
    private let belowRowHeight: CGFloat = 21

    /// 展开态左右对称；收起态各自贴合内容，避免窄的一侧多出黑边
    private var leftWing: CGFloat {
        if isExpanded { return (expandedWidth - geo.notchWidth) / 2 }
        // 靠左模式下左槽装的是两个额度并排，宽度来源不同
        return wingWidth(leftOnly ? model.combinedWidth : model.leftSlotWidth)
    }
    private var rightWing: CGFloat {
        if isExpanded { return (expandedWidth - geo.notchWidth) / 2 }
        // 靠左模式下右侧只留反向圆角的宽度，黑色主体正好收在刘海右边缘
        return leftOnly ? topRadius : wingWidth(model.rightSlotWidth)
    }
    private var width: CGFloat {
        // 宽度取刘海宽 + 两个反向圆角，这样黑色主体正好和刘海等宽、边缘对齐
        if belowMode { return geo.notchWidth + topRadius * 2 }
        return leftWing + geo.notchWidth + rightWing
    }
    /// 两翼不等宽时，面板整体要挪一下，才能让中间那段仍然正对物理刘海
    private var notchAlignOffset: CGFloat {
        belowMode ? 0 : (rightWing - leftWing) / 2
    }

    var body: some View {
        VStack(spacing: 0) {
            if belowMode {
                // 上面这段正对物理刘海，必须留空
                Color.clear.frame(width: geo.notchWidth, height: geo.notchHeight)
                belowRow
            } else {
                topRow
                if isExpanded { detailBody }
            }
        }
        .frame(width: width)
        .background(
            NotchShape(topRadius: topRadius, bottomRadius: isExpanded ? 20 : 12)
                .fill(Color.black)
        )
        // 只有黑色面板区域接收鼠标，其余透明区域事件穿透到下层窗口
        .contentShape(NotchShape(topRadius: topRadius, bottomRadius: isExpanded ? 20 : 12))
        .onHover { hovering in
            guard !model.stateLocked else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                model.isExpanded = hovering
            }
        }
        .offset(x: notchAlignOffset)
        // 数字位数变化（9%→10%）会改变翼宽，加个短过渡避免硬跳
        .animation(.easeOut(duration: 0.18), value: model.leftSlotWidth)
        .animation(.easeOut(duration: 0.18), value: model.rightSlotWidth)
        .animation(.easeOut(duration: 0.18), value: model.combinedWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 顶行（与刘海同高，中间那段是物理刘海，必须留空）

    /// 刘海正下方那一行：两个额度并排居中
    private var belowRow: some View {
        HStack(spacing: bothSpacing) {
            miniQuota(model.quota("claude"))
            miniQuota(model.quota("codex"))
        }
        .frame(height: belowRowHeight)
        .frame(maxWidth: .infinity)
    }

    private var topRow: some View {
        HStack(spacing: 0) {
            leftSlot
                .fixedSize()
                .measuredWidth(LeftSlotWidthKey.self)
                .frame(width: leftWing - gutter - topRadius - edgeInset, alignment: .trailing)
                .padding(.leading, topRadius + edgeInset)
                .padding(.trailing, gutter)
            // 中间这段正对物理刘海，必须留空；高度要显式给，否则会撑高整行
            Color.clear
                .frame(width: geo.notchWidth, height: geo.notchHeight)
            rightSlot
                .fixedSize()
                .measuredWidth(RightSlotWidthKey.self)
                .frame(width: rightWing - gutter - topRadius - edgeInset, alignment: .leading)
                .padding(.leading, gutter)
                .padding(.trailing, topRadius + edgeInset)
        }
        .frame(height: geo.notchHeight)
        .clipped()
        // 只在左右分开且收起时才更新实测宽度。其他排布下两侧内容不一样，
        // 若照单全收就会变成「布局变→测量变→布局又变」的来回抖动。
        .onPreferenceChange(StatsWidthKey.self) { w in
            if w > 0, abs(w - model.statsRowWidth) > 1 { model.statsRowWidth = w }
        }
        .onPreferenceChange(LeftSlotWidthKey.self) { w in
            guard !isExpanded, w > 0 else { return }
            if leftOnly {
                if abs(w - model.combinedWidth) > 0.5 { model.combinedWidth = w }
            } else if layout == "split" {
                if abs(w - model.leftSlotWidth) > 0.5 { model.leftSlotWidth = w }
            }
        }
        .onPreferenceChange(RightSlotWidthKey.self) { w in
            guard !isExpanded, layout == "split", w > 0 else { return }
            if abs(w - model.rightSlotWidth) > 0.5 { model.rightSlotWidth = w }
        }
    }

    @ViewBuilder private var leftSlot: some View {
        if leftOnly {
            HStack(spacing: bothSpacing) {
                miniQuota(model.quota("claude"))
                miniQuota(model.quota("codex"))
            }
        } else if isExpanded {
            // 明确标出数字含义，否则「0%」会被读成「用了 0%」
            Text(model.showRemaining ? "剩余" : "已用")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
        } else {
            miniQuota(model.quota("claude"))
        }
    }

    @ViewBuilder private var rightSlot: some View {
        if isExpanded {
            // 唯一看得见的操作入口：刷新 / 改配置 / 退出都在这里
            Button {
                model.onShowMenu?()
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("刷新 / 配置 / 退出")
        } else if !leftOnly {
            miniQuota(model.quota("codex"))
        }
    }

    /// 收起态的紧凑额度：只有「标签 + 数字」。
    /// 这里没有进度条，所以状态全靠数字的颜色传达；
    /// 但亮度保持恒定，不跟着数据新鲜度变——那会让人误以为在闪。
    @ViewBuilder private func miniQuota(_ q: Quota?) -> some View {
        if let q, let used = q.headlinePercent {
            HStack(spacing: 4) {
                Text(q.short)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(q.isStale ? 0.3 : 0.5))
                    .fixedSize()
                // 用完了就显示倒计时，否则显示百分比
                Text(q.headlineText ?? "\(Int((model.showRemaining ? 100 - used : used).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(usageColor(used))
                    .monospacedDigit()
                    .fixedSize()
            }
        } else {
            Text(q?.short ?? "--")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.22))
        }
    }

    // MARK: - 展开态主体

    private var detailBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(model.quotas) { q in quotaRow(q) }
            Divider().overlay(.white.opacity(0.10)).padding(.vertical, 1)
            statsRow
            // 自定义数据源单独一行：内容由用户决定，长度不可控（比如指数带
            // 四到六位点位加涨跌幅），挤在系统状态后面迟早会被裁掉
            if !model.custom.isEmpty { customRow }
        }
        .padding(.horizontal, detailPadding)
        .padding(.top, 9)
        .padding(.bottom, 13)
        .frame(width: width, alignment: .leading)
    }

    private func quotaRow(_ q: Quota) -> some View {
        HStack(spacing: 9) {
            Text(q.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize()
                .frame(width: 86, alignment: .leading)

            if let err = q.error {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1)
            } else {
                bar(q.primary, wide: true)
                bar(q.secondary, wide: false)
                Spacer(minLength: 0)
                Text(q.primary?.resetText ?? q.secondary?.resetText ?? "")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
                    .monospacedDigit()
            }
        }
    }

    /// 进度条的填充色：整条纯色，和数字用同一个判定。
    ///
    /// 刻意不做条内渐变。试过在左端降透明度制造层次，但纯黑背景下
    /// 降透明度等于和黑色混合，左边会发黑发脏。
    private func barFill(_ used: Double) -> Color {
        usageColor(used)
    }

    /// 按设置换算成要显示的数值：剩余 或 已用
    private func shown(_ w: UsageWindow) -> Double {
        model.showRemaining ? 100 - w.usedPercent : w.usedPercent
    }

    @ViewBuilder private func bar(_ w: UsageWindow?, wide: Bool) -> some View {
        if let w {
            HStack(spacing: 5) {
                Text(w.label)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize()
                let full = wide ? 96.0 : 62.0
                let fill = full * min(max(shown(w), 0), 100) / 100
                ZStack(alignment: .leading) {
                    // 轨道。额度耗尽时给点暗红底，否则空条看着像没数据
                    Capsule()
                        .fill(w.usedPercent >= 99.5
                              ? usageDangerColor.opacity(0.30)
                              : .white.opacity(0.13))
                    Capsule()
                        .fill(barFill(w.usedPercent))
                        .frame(width: fill)
                }
                .frame(width: full, height: 5)

                Text("\(Int(shown(w).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(width: 32, alignment: .leading)
            }
        }
    }

    /// 系统状态行
    private var statsRow: some View {
        measuredRow {
            stat("CPU", String(format: "%.0f%%", model.stats.cpuPercent))
            stat("内存", String(format: "%.0f%%", model.stats.memoryPercent))
            stat("↓", SystemStats.rate(model.stats.netDownBytes))
            stat("↑", SystemStats.rate(model.stats.netUpBytes))
        }
    }

    /// 自定义数据源行
    private var customRow: some View {
        measuredRow {
            ForEach(model.custom.sorted(by: { $0.key < $1.key }).prefix(4), id: \.key) { k, v in
                stat(k, v)
            }
        }
    }

    /// 一行内容：取自然宽度、上报给面板决定该多宽，然后左对齐。
    ///
    /// 这里不能留 Spacer 或用 maxWidth 再测量：那样量到的是容器宽度，
    /// 而容器宽度又由这个量值决定，会一路撑到屏幕边缘。
    private func measuredRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 14) { content() }
            .fixedSize()
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: StatsWidthKey.self, value: g.size.width)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.38))
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .monospacedDigit()
        }
    }
}


// MARK: - 内容宽度实测

protocol SlotWidthKeyProtocol: PreferenceKey where Value == CGFloat {}

struct LeftSlotWidthKey: SlotWidthKeyProtocol {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 展开态底部那行的自然宽度
struct StatsWidthKey: SlotWidthKeyProtocol {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct RightSlotWidthKey: SlotWidthKeyProtocol {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// 把自身渲染后的实际宽度上报到指定的键
    func measuredWidth<K: SlotWidthKeyProtocol>(_ key: K.Type) -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(key: K.self, value: g.size.width)
            }
        )
    }
}
