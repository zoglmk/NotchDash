import AppKit
import ApplicationServices

/// 探测菜单栏被占用的情况，算出刘海左右两侧各还剩多少空间。
///
/// 为什么不用 CGWindowList：现代 macOS 把整条菜单栏交给 WindowServer 统一渲染，
/// 窗口列表里只有一个整条菜单栏的窗口，拿不到单个图标的位置。
/// 辅助功能接口能逐个读出状态栏图标的坐标，这是目前唯一可行的办法。
///
/// 没有辅助功能权限时返回 nil，调用方降级成手动配置的布局。
final class MenuBarProbe: @unchecked Sendable {
    struct Space: Equatable {
        /// 刘海左侧可用宽度：App 菜单（和跳到左边的图标）右边缘 → 刘海左边缘
        var left: CGFloat
        /// 刘海右侧可用宽度：刘海右边缘 → 最靠左的那个状态栏图标
        var right: CGFloat
    }

    /// 和图标之间至少留这么多，别贴着
    private let gap: CGFloat = 6

    var isAuthorized: Bool { AXIsProcessTrusted() }

    func probe(notchLeft: CGFloat, notchRight: CGFloat, screenFrame: CGRect) -> Space? {
        guard AXIsProcessTrusted() else { return nil }

        var leftOccupiedTo: CGFloat = screenFrame.minX
        var rightStartsAt: CGFloat = screenFrame.maxX

        for f in extrasFrames(in: screenFrame) {
            if f.minX >= notchRight {
                // 刘海右侧那排
                rightStartsAt = min(rightStartsAt, f.minX)
            } else if f.maxX <= notchLeft {
                // 图标排满右侧后会跳过刘海、在左边继续排，这些也要算进占用
                leftOccupiedTo = max(leftOccupiedTo, f.maxX)
            }
        }

        // 前台 App 的菜单（文件 / 编辑 / 显示…），切换 App 时长度会变
        leftOccupiedTo = max(leftOccupiedTo, appMenuRightEdge(in: screenFrame))

        return Space(left: max(notchLeft - leftOccupiedTo - gap, 0),
                     right: max(rightStartsAt - notchRight - gap, 0))
    }

    // MARK: - 状态栏图标

    private func extrasFrames(in screenFrame: CGRect) -> [CGRect] {
        var out: [CGRect] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy != .prohibited else { continue }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            var extrasRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, "AXExtrasMenuBar" as CFString, &extrasRef) == .success,
                  let extras = extrasRef, CFGetTypeID(extras) == AXUIElementGetTypeID()
            else { continue }
            out.append(contentsOf: childFrames(of: extras as! AXUIElement, in: screenFrame))
        }
        return out
    }

    // MARK: - 前台 App 的菜单

    private func appMenuRightEdge(in screenFrame: CGRect) -> CGFloat {
        guard let front = NSWorkspace.shared.frontmostApplication else { return screenFrame.minX }
        let ax = AXUIElementCreateApplication(front.processIdentifier)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXMenuBarAttribute as CFString, &barRef) == .success,
              let bar = barRef, CFGetTypeID(bar) == AXUIElementGetTypeID()
        else { return screenFrame.minX }
        return childFrames(of: bar as! AXUIElement, in: screenFrame)
            .map(\.maxX).max() ?? screenFrame.minX
    }

    // MARK: - 公共

    private func childFrames(of element: AXUIElement, in screenFrame: CGRect) -> [CGRect] {
        var kidsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &kidsRef) == .success,
              let kids = kidsRef as? [AXUIElement]
        else { return [] }

        var out: [CGRect] = []
        for kid in kids {
            var posRef: CFTypeRef?, sizeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(kid, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(kid, kAXSizeAttribute as CFString, &sizeRef) == .success,
                  let p = posRef, let s = sizeRef,
                  CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
            else { continue }
            var point = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(p as! AXValue, .cgPoint, &point)
            AXValueGetValue(s as! AXValue, .cgSize, &size)
            let rect = CGRect(origin: point, size: size)
            // 多屏时坐标是全局的，只保留落在这块屏上的
            guard rect.minX >= screenFrame.minX, rect.maxX <= screenFrame.maxX else { continue }
            out.append(rect)
        }
        return out
    }
}
