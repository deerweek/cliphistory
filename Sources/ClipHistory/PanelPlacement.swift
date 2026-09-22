import CoreGraphics

public enum PanelPlacement {
    /// Puts the panel on the right of a target window, top-aligned.
    /// If that side does not fit, it tries the left, then clamps inside the screen.
    public static func snappedOrigin(panel: CGSize, target: CGRect, screen: CGRect, gap: CGFloat = 8) -> CGPoint {
        var origin = CGPoint(x: target.maxX + gap, y: target.maxY - panel.height)
        if origin.x + panel.width > screen.maxX {
            origin.x = target.minX - gap - panel.width
        }
        if origin.x < screen.minX {
            origin.x = screen.maxX - panel.width
        }
        return clampedOrigin(CGPoint(x: origin.x, y: origin.y), panel: panel, screen: screen)
    }

    public static func clampedOrigin(_ origin: CGPoint, panel: CGSize, screen: CGRect) -> CGPoint {
        let maxX = max(screen.minX, screen.maxX - panel.width)
        let maxY = max(screen.minY, screen.maxY - panel.height)
        return CGPoint(
            x: min(max(origin.x, screen.minX), maxX),
            y: min(max(origin.y, screen.minY), maxY)
        )
    }
}
