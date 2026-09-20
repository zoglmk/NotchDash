import AppKit
import SwiftUI

/// 悬浮在刘海下方的面板窗口
/// 要点：不激活、无边框、透明、层级高于菜单栏、跟随所有桌面空间
final class NotchWindow: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        // 关键：不抢焦点，点击时不会让当前 App 失去激活状态
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // 层级要高于菜单栏（菜单栏是 24），否则会被菜单栏盖住
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))

        // 所有桌面空间都显示、不参与 Mission Control 排布、全屏应用之上也在
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    // 无边框窗口默认不能成为 key window，这里放开，否则内部控件无法交互
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 右键菜单必须在这一层处理。
    /// 挂到 NSHostingView.menu 上是不行的——SwiftUI 会把 rightMouseDown 吃掉，
    /// 菜单永远弹不出来。窗口是响应链的下一站，在这里拦截才稳。
    override func rightMouseDown(with event: NSEvent) {
        guard let view = contentView, let menu = view.menu else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}
