import SwiftUI

/// 刘海面板形状：顶部两侧是「反向圆角」（向外张开，与刘海直边平滑衔接），底部是普通圆角
struct NotchShape: Shape {
    var topRadius: CGFloat = 10
    var bottomRadius: CGFloat = 14

    /// 让形状可以跟随尺寸做动画
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let topR = min(topRadius, rect.width / 2)
        let botR = min(bottomRadius, rect.height / 2, (rect.width - 2 * topR) / 2)
        var p = Path()

        // 左上：从屏幕顶边起，反向圆角向内下方收
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
                       control: CGPoint(x: rect.minX + topR, y: rect.minY))
        // 左边往下
        p.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))
        // 左下圆角
        p.addQuadCurve(to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
                       control: CGPoint(x: rect.minX + topR, y: rect.maxY))
        // 底边
        p.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))
        // 右下圆角
        p.addQuadCurve(to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
                       control: CGPoint(x: rect.maxX - topR, y: rect.maxY))
        // 右边往上
        p.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))
        // 右上反向圆角
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - topR, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
