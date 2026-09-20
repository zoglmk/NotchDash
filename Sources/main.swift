import AppKit
import ApplicationServices
import SwiftUI

// ── 命令行模式：不启动界面，处理完直接退出 ──
let args = CommandLine.arguments
if args.contains("--statusline-tee") {
    StatuslineTee.run()
    exit(0)
}
if args.contains("--probe-menubar") {
    Probe.runMenuBar()
    exit(0)
}
if args.contains("--probe-oauth") {
    Probe.runOAuthOnly()
    exit(0)
}
if args.contains("--probe") {
    Probe.run()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // 纯后台 App，不进 Dock、不抢焦点

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NotchWindow?
    private let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 只允许跑一个实例。构建目录和 /Applications 下各有一份时，
        // 很容易不小心开出两个，两块面板叠在一起还都在抢刘海的位置。
        let mine = Bundle.main.bundleIdentifier
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == mine && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        if !others.isEmpty {
            FileHandle.standardError.write("NotchDash 已在运行\n".data(using: .utf8)!)
            NSApp.terminate(nil)
            return
        }

        guard rebuildWindow() else {
            FileHandle.standardError.write("找不到可用屏幕，退出\n".data(using: .utf8)!)
            NSApp.terminate(nil)
            return
        }

        // 分辨率/缩放变化、插拔外接显示器、合盖开盖都会发这个通知，
        // 刘海尺寸随之改变，必须重新量一次并重建窗口
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.rebuildWindow() }
        }

        requestAccessibilityIfNeeded()
        startRefreshing()

        // 调试用：NOTCHDASH_DEMO=expanded 启动即展开
        if let demo = ProcessInfo.processInfo.environment["NOTCHDASH_DEMO"] {
            model.isExpanded = (demo == "expanded")
            model.stateLocked = true   // 锁死，免得鼠标悬停打乱截图
        }

        // 自检用：--snapshot <路径> 让 App 把自己的界面渲染成 PNG 后退出。
        // 走的是 App 自身的绘制缓冲，不需要屏幕录制权限。
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"),
           i + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[i + 1]
            // 自定义数据源要跑 shell 命令（可能带网络请求），给够时间再截
            let delay = ProcessInfo.processInfo.environment["NOTCHDASH_SNAPSHOT_DELAY"]
                .flatMap(Double.init) ?? 2.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.writeSnapshot(to: path)
                NSApp.terminate(nil)
            }
        }
    }

    /// 把窗口内容渲染成 PNG，底下垫一层灰色方便看清黑色面板的轮廓
    private func writeSnapshot(to path: String) {
        guard let view = window?.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)

        let canvas = NSImage(size: bounds.size)
        canvas.lockFocus()
        NSColor(calibratedWhite: 0.42, alpha: 1).setFill()
        bounds.fill()
        rep.draw(in: bounds)
        canvas.unlockFocus()

        // 顺带把实际布局数值打出来，比对着图片目测靠谱
        let gutter: CGFloat = 8, topRadius: CGFloat = 10, edgeInset: CGFloat = 7
        let lw = model.leftSlotWidth > 0 ? model.leftSlotWidth : 52, rw = model.rightSlotWidth > 0 ? model.rightSlotWidth : 52
        let leftWing = lw + gutter + topRadius + edgeInset
        let rightWing = rw + gutter + topRadius + edgeInset
        FileHandle.standardError.write("""
        布局实测（单位：点）
          左侧内容宽 \(String(format: "%.1f", model.leftSlotWidth))   右侧内容宽 \(String(format: "%.1f", model.rightSlotWidth))
          左翼 \(String(format: "%.1f", leftWing))   右翼 \(String(format: "%.1f", rightWing))
          面板总宽 \(String(format: "%.1f", leftWing + 185 + rightWing))   偏移 \(String(format: "%.1f", (rightWing - leftWing) / 2))
          文字到黑色边缘：两侧都应是 edgeInset = \(edgeInset)
          文字到刘海：两侧都应是 gutter = \(gutter)

        """.data(using: .utf8)!)

        guard let tiff = canvas.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write("snapshot -> \(path)\n".data(using: .utf8)!)
    }

    /// 重新测量屏幕并重建窗口。屏幕参数变了就得重来一遍。
    @discardableResult
    private func rebuildWindow() -> Bool {
        guard let geo = NotchGeometry() else { return false }

        // 窗口固定为展开态所需的最大尺寸；实际黑色区域由 SwiftUI 内部控制，
        // 这样展开/收起时不需要 resize 窗口，动画不会抖。
        let winWidth = min(geo.screen.frame.width, 760)
        let winHeight = geo.notchHeight + 240
        let frame = geo.windowFrame(width: winWidth, height: winHeight)

        let hosting = NSHostingView(rootView: NotchView(model: model, geo: geo))
        // 菜单挂在视图上供 NotchWindow.rightMouseDown 取用；
        // 界面上那个 ⋯ 按钮走 onShowMenu 回调，两条路弹的是同一个菜单。
        hosting.menu = buildMenu()
        model.showRemaining = config.showRemaining
        model.collapsedLayout = config.collapsedLayout
        model.autoLayout = config.autoLayout
        model.redUp = config.redUp
        model.carousel = config.carousel
        model.onShowMenu = { [weak self] in self?.showMenuAtMouse() }

        if let win = window {
            win.contentView = hosting
            win.setFrame(frame, display: true)
        } else {
            let win = NotchWindow(contentRect: frame)
            win.contentView = hosting
            win.setFrame(frame, display: true)
            win.orderFrontRegardless()
            window = win
        }
        return true
    }

    /// 在鼠标当前位置弹菜单。
    /// 不用 becomesKey 的方式，避免点一下就把你正在打字的窗口焦点抢走。
    private func showMenuAtMouse() {
        guard let win = window, let view = win.contentView, let menu = view.menu else { return }
        let inWindow = win.convertPoint(fromScreen: NSEvent.mouseLocation)
        menu.popUp(positioning: nil, at: view.convert(inWindow, from: nil), in: view)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let items: [(String, Selector, String)] = [
            (model.showRemaining ? "改为显示已用" : "改为显示剩余", #selector(menuToggleMode), "t"),


            ("立即刷新", #selector(menuRefresh), "r"),
            ("打开配置文件", #selector(menuOpenConfig), ","),
            ("复制诊断信息", #selector(menuCopyDiagnostics), "d"),
        ]
        for (title, action, key) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        // 轮播
        let carouselItem = NSMenuItem(title: "轮播", action: nil, keyEquivalent: "")
        let cSub = NSMenu()
        let toggle = NSMenuItem(title: "轮流显示额度与行情",
                                action: #selector(menuToggleCarousel), keyEquivalent: "p")
        toggle.target = self
        toggle.state = config.carousel ? .on : .off
        cSub.addItem(toggle)
        cSub.addItem(.separator())
        for (title, sec) in [("5 秒", 5.0), ("10 秒", 10.0), ("20 秒", 20.0), ("30 秒", 30.0)] {
            let it = NSMenuItem(title: title, action: #selector(menuSetCarouselInterval(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = sec
            it.state = abs(config.carouselInterval - sec) < 0.5 ? .on : .off
            it.isEnabled = config.carousel
            cSub.addItem(it)
        }
        carouselItem.submenu = cSub
        menu.addItem(carouselItem)

        // 行情
        let stocksItem = NSMenuItem(title: "行情", action: nil, keyEquivalent: "")
        stocksItem.submenu = buildStocksMenu()
        menu.addItem(stocksItem)

        // 收起态排布
        let layoutItem = NSMenuItem(title: "收起态排布", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let auto = NSMenuItem(title: autoLayoutTitle(), action: #selector(menuToggleAuto), keyEquivalent: "")
        auto.target = self
        auto.state = model.autoLayout ? .on : .off
        sub.addItem(auto)
        sub.addItem(.separator())
        for (key, title) in [("split", "刘海左右分开"),
                             ("left", "全部靠左"),
                             ("below", "刘海正下方（不占菜单栏）")] {
            let it = NSMenuItem(title: title, action: #selector(menuSetLayout(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = key
            it.state = (!model.autoLayout && model.collapsedLayout == key) ? .on : .off
            it.isEnabled = !model.autoLayout
            sub.addItem(it)
        }
        layoutItem.submenu = sub
        menu.addItem(layoutItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 NotchDash", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// 切换剩余/已用，并写回配置文件，下次启动仍然生效
    @objc private func menuToggleMode() {
        model.showRemaining.toggle()
        config.showRemaining = model.showRemaining
        writeConfig(["show_remaining": model.showRemaining])
        // 菜单标题要跟着变
        window?.contentView?.menu = buildMenu()
    }

    /// 行情子菜单：常用标的直接勾选，个股走「添加代码」
    private func buildStocksMenu() -> NSMenu {
        let menu = NSMenu()
        let chosen = Set(config.stocks.items.map(\.code))

        for preset in StockPresets.all {
            let it = NSMenuItem(title: preset.label, action: #selector(menuToggleStock(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = preset.code
            it.state = chosen.contains(preset.code) ? .on : .off
            menu.addItem(it)
        }

        // 用户自己添加的（不在预设里的）也列出来，方便取消
        let extras = config.stocks.items.filter { StockPresets.label(for: $0.code) == nil }
        if !extras.isEmpty {
            menu.addItem(.separator())
            for e in extras {
                let it = NSMenuItem(title: "\(e.label)（\(e.code)）",
                                    action: #selector(menuToggleStock(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = e.code
                it.state = .on
                menu.addItem(it)
            }
        }

        menu.addItem(.separator())
        let add = NSMenuItem(title: "添加代码…", action: #selector(menuAddStock), keyEquivalent: "")
        add.target = self
        menu.addItem(add)

        menu.addItem(.separator())
        let freq = NSMenuItem(title: "刷新频率", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, sec) in [("10 秒", 10.0), ("30 秒", 30.0), ("1 分钟", 60.0), ("5 分钟", 300.0)] {
            let it = NSMenuItem(title: title, action: #selector(menuSetStockInterval(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = sec
            it.state = abs(config.stocks.interval - sec) < 0.5 ? .on : .off
            sub.addItem(it)
        }
        freq.submenu = sub
        menu.addItem(freq)
        return menu
    }

    @objc private func menuToggleStock(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        if let idx = config.stocks.items.firstIndex(where: { $0.code == code }) {
            config.stocks.items.remove(at: idx)
        } else {
            let label = StockPresets.label(for: code)
                ?? stockProvider.lookupName(code) ?? code
            config.stocks.items.append(StockItem(label: label, code: code))
        }
        saveStocks()
    }

    @objc private func menuSetStockInterval(_ sender: NSMenuItem) {
        guard let sec = sender.representedObject as? Double else { return }
        config.stocks.interval = sec
        saveStocks()
    }

    /// 弹窗输入一个代码，名称自动向接口查
    @objc private func menuAddStock() {
        let alert = NSAlert()
        alert.messageText = "添加行情代码"
        alert.informativeText = "个股直接填代码，如 sh600519（贵州茅台）、sz000001（平安银行）。\n名称会自动获取。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "例如 sh600519"
        alert.accessoryView = field
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        // 面板是非激活窗口，不先激活的话输入框敲不进字
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeFirstResponder(field)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let code = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !config.stocks.items.contains(where: { $0.code == code }) else { return }

        guard let name = stockProvider.lookupName(code) else {
            let fail = NSAlert()
            fail.messageText = "查不到这个代码"
            fail.informativeText = "「\(code)」没有返回行情数据，检查一下写法。\nA 股要带市场前缀：sh600519 / sz000001。"
            fail.runModal()
            return
        }
        config.stocks.items.append(StockItem(label: name, code: code))
        saveStocks()
    }

    /// 写回配置并立即刷新
    private func saveStocks() {
        writeConfig(["stocks": [
            "interval": config.stocks.interval,
            "items": config.stocks.items.map { ["label": $0.label, "code": $0.code] },
        ]])
        refreshQuotas()
        window?.contentView?.menu = buildMenu()
    }

    /// 自动排布这一项的标题：顺带把量到的空间显示出来，方便判断
    private func autoLayoutTitle() -> String {
        guard menuBarProbe.isAuthorized else { return "自动（需辅助功能权限）" }
        guard let s = model.menuBarSpace else { return "自动适应菜单栏" }
        return String(format: "自动适应菜单栏（左 %.0f / 右 %.0f 可用）", s.left, s.right)
    }

    @objc private func menuToggleAuto() {
        // 想开自动但还没授权：弹系统授权框，引导去设置里勾选
        if !model.autoLayout && !menuBarProbe.isAuthorized {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        model.autoLayout.toggle()
        config.autoLayout = model.autoLayout
        writeConfig(["auto_layout": model.autoLayout])
        if model.autoLayout { refreshMenuBarSpace() }
        window?.contentView?.menu = buildMenu()
    }

    /// 设置收起态排布，并写回配置
    @objc private func menuSetLayout(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        model.collapsedLayout = key
        config.collapsedLayout = key
        model.autoLayout = false            // 手动指定了就别再自动改
        config.autoLayout = false
        writeConfig(["collapsed_layout": key, "auto_layout": false])
        window?.contentView?.menu = buildMenu()
    }

    /// 往配置文件里合并若干键，保留其他内容
    private func writeConfig(_ patch: [String: Any]) {
        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: Config.url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = existing
        }
        for (k, v) in patch { obj[k] = v }
        try? FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: obj,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Config.url)
        }
    }

    @objc private func menuSetCarouselInterval(_ sender: NSMenuItem) {
        guard let sec = sender.representedObject as? Double else { return }
        config.carouselInterval = sec
        writeConfig(["carousel_interval": sec])
        startCarousel()
        window?.contentView?.menu = buildMenu()
    }

    @objc private func menuToggleCarousel() {
        config.carousel.toggle()
        writeConfig(["carousel": config.carousel])
        startCarousel()
        window?.contentView?.menu = buildMenu()
    }

    @objc private func menuRefresh() {
        config = Config.load()
        refreshSystem()
        refreshQuotas()
    }

    @objc private func menuOpenConfig() {
        let url = Config.url
        if !FileManager.default.fileExists(atPath: url.path) {
            // 第一次打开时生成一份带注释说明的模板
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            let template = """
            {
              "oauth_fallback": true,
              "custom_sources": [
                { "label": "负载", "command": "sysctl -n vm.loadavg | awk '{print $2}'", "interval": 20 }
              ]
            }
            """
            try? template.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func menuCopyDiagnostics() {
        var lines = ["NotchDash 诊断", "时间: \(Date())"]
        for q in model.quotas {
            lines.append("\(q.name): 来源=\(q.source) 短窗口=\(q.primary?.usedPercent.description ?? "-") "
                         + "长窗口=\(q.secondary?.usedPercent.description ?? "-") "
                         + "更新=\(q.staleText ?? "-") 错误=\(q.error ?? "无")")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - 数据刷新

    private let sysProvider = SystemStatsProvider()
    private let claudeProvider = ClaudeUsageProvider()
    private let codexProvider = CodexUsageProvider()
    private let oauthProvider = OAuthUsageProvider()
    private let customProvider = CustomSourceProvider()
    private let stockProvider = StockProvider()
    private let menuBarProbe = MenuBarProbe()
    private var config = Config.load()
    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var carouselTimer: Timer?
    /// 串行队列：保证 SystemStatsProvider 的差分状态不会被并发访问
    private let collectQueue = DispatchQueue(label: "app.notchdash.NotchDash.collect", qos: .utility)
    /// 菜单栏探测单独一条队列。全量扫描要一秒多，挤在上面那条队列里
    /// 会把 CPU / 网速的采样一起堵住，差分间隔就不准了。
    private let menuBarQueue = DispatchQueue(label: "app.notchdash.NotchDash.menubar", qos: .utility)

    private func startRefreshing() {
        refreshSystem()
        refreshQuotas()
        refreshMenuBarSpace()
        startCarousel()

        // 切换 App：只有菜单长度会变，图标没动，用缓存快查即可
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMenuBarSpace(rescanExtras: false) }
        }

        // App 启动/退出：状态栏图标可能增减，必须重新全量扫描。
        // 延迟一下再扫——图标是 App 起来之后才注册的，立刻扫会扫了个寂寞。
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    MainActor.assumeIsolated { self?.refreshMenuBarSpace(rescanExtras: true) }
                }
            }
        }
        // 系统状态变化快，2 秒一次；CPU/网速本来就要靠两次采样求差
        fastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSystem() }
        }
        // 额度是读本地文件，20 秒一次足够，也不会拖慢机器
        slowTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.config = Config.load()   // 改了配置文件不用重启
                self?.refreshQuotas()
                // 兜底重扫。图标增减靠上面的 App 启停事件就够了，
                // 这里只防漏网（比如 App 没退出但自己把图标撤了）。
                // 注意括号：?? 的优先级比 % 低，不加括号会变成 tick == 0，永远不成立。
                guard let self else { return }
                self.menuBarTick += 1
                if self.menuBarTick % 3 == 0 {
                    self.refreshMenuBarSpace(rescanExtras: true)
                }
            }
        }
    }

    /// 收起态轮播：在「额度」和「行情」之间来回翻
    private func startCarousel() {
        carouselTimer?.invalidate()
        carouselTimer = nil
        model.carousel = config.carousel
        guard config.carousel else {
            model.carouselPage = 0
            return
        }
        let interval = max(config.carouselInterval, 2)
        carouselTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 没有行情数据就只剩一页，别翻成空白
                let pages = self.model.carouselPageCount
                guard pages > 1 else {
                    self.model.carouselPage = 0
                    return
                }
                self.model.carouselPage = (self.model.carouselPage + 1) % pages
            }
        }
    }

    private func refreshSystem() {
        let sys = sysProvider
        // 采集要读 mach/IOKit，挪到后台串行队列，既不卡界面也不会并发打架
        collectQueue.async { [weak self] in
            let s = sys.sample()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.model.stats = s }
            }
        }
    }

    /// 想用自动排布但还没授权时，启动时请求一次（仅一次）。
    /// 没有这个权限 App 照常工作，只是排布得自己在菜单里选。
    private func requestAccessibilityIfNeeded() {
        guard config.autoLayout,
              !menuBarProbe.isAuthorized,
              !config.accessibilityPromptShown else { return }
        config.accessibilityPromptShown = true
        writeConfig(["accessibility_prompt_shown": true])
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// 量一下菜单栏两侧还剩多少空间。走辅助功能接口，可能偏慢，放后台。
    private var menuBarTick = 0

    private func refreshMenuBarSpace(rescanExtras: Bool = true) {
        guard let geo = NotchGeometry() else { return }
        guard config.autoLayout, menuBarProbe.isAuthorized else {
            writeStatus(nil)      // 没授权也要留个记录，方便排查
            return
        }
        let probe = menuBarProbe
        let notchLeft = geo.screen.frame.midX - geo.notchWidth / 2
        let notchRight = geo.screen.frame.midX + geo.notchWidth / 2
        let frame = geo.screen.frame
        menuBarQueue.async { [weak self] in
            let space = probe.probe(notchLeft: notchLeft, notchRight: notchRight,
                                    screenFrame: frame, rescanExtras: rescanExtras)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.model.menuBarSpace != space {
                        withAnimation(.easeOut(duration: 0.25)) { self.model.menuBarSpace = space }
                    }
                    self.writeStatus(space)
                }
            }
        }
    }

    /// 把当前运行状态写到 ~/.notchdash/status.json。
    /// App 是 GUI 进程看不到 stdout，出问题时读这个文件最直接。
    private func writeStatus(_ space: MenuBarProbe.Space?) {
        var obj: [String: Any] = [
            "accessibility_authorized": menuBarProbe.isAuthorized,
            "auto_layout": model.autoLayout,
            "configured_layout": model.collapsedLayout,
            "left_slot_width": model.leftSlotWidth,
            "right_slot_width": model.rightSlotWidth,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
            "carousel_enabled": model.carousel,
            "carousel_page": model.carouselPage,
            "custom_item_count": model.custom.count,
            "carousel_timer_running": carouselTimer != nil,
        ]
        if let space {
            obj["space_left"] = space.left
            obj["space_right"] = space.right
        }
        let url = Config.url.deletingLastPathComponent().appendingPathComponent("status.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: obj,
                                               options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: url)
        }
    }

    /// 调试用：NOTCHDASH_FAKE="35,25" 把两个额度的**剩余**百分比写死，
    /// 用来验收配色阈值，不用干等真实额度掉下来。
    private func fakeQuotas() -> [Quota]? {
        guard let raw = ProcessInfo.processInfo.environment["NOTCHDASH_FAKE"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return [("claude", "Claude Code", "CC", parts[0]), ("codex", "Codex", "Codex", parts[1])]
            .map { id, name, short, remaining in
                Quota(id: id, name: name, short: short, plan: "demo",
                      primary: UsageWindow(usedPercent: 100 - remaining, windowMinutes: 300,
                                           resetsAt: Date().addingTimeInterval(3600)),
                      secondary: nil, updatedAt: Date(), source: "假数据", error: nil)
            }
    }

    private func refreshQuotas() {
        if let fake = fakeQuotas() {
            model.quotas = fake
            return
        }
        let claude = claudeProvider, codex = codexProvider
        let oauth = oauthProvider, custom = customProvider, stocks = stockProvider
        let cfg = config
        collectQueue.async { [weak self] in
            // 主通道：纯本地读文件，零风险
            var list = [claude.fetch(), codex.fetch()]

            // 兜底：本地这份缺失或已过期时，才去问官方 API。
            // 拿不到就保留本地那份（哪怕是旧的），也比显示空白强。
            if cfg.oauthFallback {
                for i in list.indices where list[i].error != nil || list[i].isStale {
                    let fb = list[i].id == "claude" ? oauth.fetchClaude() : oauth.fetchCodex()
                    if let fb { list[i] = fb }
                }
            }

            // 行情在前、自定义命令在后，各自保持配置里的顺序
            let quotes = stocks.fetch(cfg.stocks)
            let customValues = custom.fetch(cfg.customSources)
            var items: [DisplayItem] = []
            for item in cfg.stocks.items {
                if let v = quotes[item.label] {
                    items.append(DisplayItem(id: items.count, label: item.label, value: v))
                }
            }
            for src in cfg.customSources {
                if let v = customValues[src.label] {
                    items.append(DisplayItem(id: items.count, label: src.label, value: v))
                }
            }
            let snapshot = list
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.model.quotas = snapshot
                    self?.model.custom = items
                    self?.model.showRemaining = cfg.showRemaining
                    // 每轮都记一次状态，方便从外面看到实时情况
                    self?.writeStatus(self?.model.menuBarSpace ?? nil)
                    self?.model.collapsedLayout = cfg.collapsedLayout
                    self?.model.autoLayout = cfg.autoLayout
                    self?.model.redUp = cfg.redUp
                }
            }
        }
    }
}

// 顶层代码确实运行在主线程上，这里是准确的断言而不是绕过检查
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
