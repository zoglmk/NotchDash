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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
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
    private let menuBarProbe = MenuBarProbe()
    private var config = Config.load()
    private var fastTimer: Timer?
    private var slowTimer: Timer?
    /// 串行队列：保证 SystemStatsProvider 的差分状态不会被并发访问
    private let collectQueue = DispatchQueue(label: "local.zgm.notchdash.collect", qos: .utility)

    private func startRefreshing() {
        refreshSystem()
        refreshQuotas()
        refreshMenuBarSpace()

        // 切换 App 时菜单栏长度会变（不同 App 的菜单项数量不同），跟着重算
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMenuBarSpace() }
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
                self?.refreshMenuBarSpace()    // 图标可能被添加/移除
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
    private func refreshMenuBarSpace() {
        guard let geo = NotchGeometry() else { return }
        guard config.autoLayout, menuBarProbe.isAuthorized else {
            writeStatus(nil)      // 没授权也要留个记录，方便排查
            return
        }
        let probe = menuBarProbe
        let notchLeft = geo.screen.frame.midX - geo.notchWidth / 2
        let notchRight = geo.screen.frame.midX + geo.notchWidth / 2
        let frame = geo.screen.frame
        collectQueue.async { [weak self] in
            let space = probe.probe(notchLeft: notchLeft, notchRight: notchRight, screenFrame: frame)
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

    private func refreshQuotas() {
        let claude = claudeProvider, codex = codexProvider
        let oauth = oauthProvider, custom = customProvider
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

            let customValues = custom.fetch(cfg.customSources)
            let snapshot = list
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.model.quotas = snapshot
                    self?.model.custom = customValues
                    self?.model.showRemaining = cfg.showRemaining
                    self?.model.collapsedLayout = cfg.collapsedLayout
                    self?.model.autoLayout = cfg.autoLayout
                }
            }
        }
    }
}

// 顶层代码确实运行在主线程上，这里是准确的断言而不是绕过检查
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
