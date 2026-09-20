import AppKit

/// 刘海几何参数：全部从系统实测读取，不写死任何机型数字
struct NotchGeometry {
    let screen: NSScreen
    /// 刘海宽度（点）
    let notchWidth: CGFloat
    /// 刘海高度（点），等于顶部安全区
    let notchHeight: CGFloat
    /// 是否真的有刘海
    let hasNotch: Bool

    /// 优先挑带刘海的那块屏（内建屏）。接了外接显示器时，主屏可能不是内建屏，
    /// 直接用 NSScreen.main 会把面板画到没有刘海的屏幕上。
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    init?(screen: NSScreen? = NotchGeometry.preferredScreen()) {
        guard let screen else { return nil }
        self.screen = screen

        let top = screen.safeAreaInsets.top
        if top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            // 刘海宽度 = 右侧可用区起点 - 左侧可用区终点
            self.notchWidth = right.minX - left.maxX
            self.notchHeight = top
            self.hasNotch = true
        } else {
            // 无刘海的外接屏/旧机型：退化成菜单栏高度的伪刘海，功能照常可用
            self.notchWidth = 200
            self.notchHeight = max(screen.frame.height - screen.visibleFrame.height, 24)
            self.hasNotch = false
        }
    }

    /// 给定面板尺寸，算出贴在屏幕顶部正中的窗口 frame（AppKit 坐标，y 向上）
    func windowFrame(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: screen.frame.midX - width / 2,
               y: screen.frame.maxY - height,
               width: width,
               height: height)
    }
}
