import AppKit
import ApplicationServices

enum WindowLocator {
    /// The window we use as the anchor for attached mode.  `windowNumber` is
    /// the CoreGraphics window id, which can also be passed to
    /// `NSWindow.order(_:relativeTo:)` even though the window belongs to
    /// another application.
    struct MainWindow {
        let frame: NSRect
        let windowNumber: CGWindowID?
    }

    /// Largest normal window of the app, in AppKit coordinates (origin at bottom-left).
    static func mainWindowFrame(bundleID: String) -> NSRect? {
        mainWindow(bundleID: bundleID)?.frame
    }

    /// Returns the largest normal window and, when available, its CG window id.
    /// The id lets an attached panel be ordered directly above the target
    /// window while remaining at the target application's normal window level.
    static func mainWindow(bundleID: String) -> MainWindow? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }
        if let window = cgMainWindow(pid: app.processIdentifier) {
            return window
        }
        guard let frame = axWindowFrame(pid: app.processIdentifier) else { return nil }
        return MainWindow(frame: frame, windowNumber: nil)
    }

    private static func cgMainWindow(pid: pid_t) -> MainWindow? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let windows: [(frame: CGRect, windowNumber: CGWindowID)] = list.compactMap { info in
            let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue ?? -1
            guard owner == Int(pid) else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { return nil }
            guard let rect = cgRect(info[kCGWindowBounds as String]), rect.width >= 240, rect.height >= 160 else {
                return nil
            }
            guard let number = (info[kCGWindowNumber as String] as? NSNumber).map({ CGWindowID($0.uint32Value) }) else {
                return nil
            }
            return (rect, number)
        }
        guard let largest = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            return nil
        }
        return MainWindow(
            frame: appKitRect(fromTopLeft: largest.frame),
            windowNumber: largest.windowNumber
        )
    }

    private static func cgRect(_ value: Any?) -> CGRect? {
        guard let bounds = value as? [String: Any] else { return nil }
        func number(_ key: String) -> CGFloat? {
            (bounds[key] as? NSNumber).map { CGFloat($0.doubleValue) }
        }
        guard let x = number("X"), let y = number("Y"), let width = number("Width"), let height = number("Height") else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func axWindowFrame(pid: pid_t) -> NSRect? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowRef)
        if result != .success || windowRef == nil {
            windowRef = nil
            result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        }
        guard result == .success, let windowRef else { return nil }
        let window = windowRef as! AXUIElement
        guard let origin = pointAttribute(window, kAXPositionAttribute as CFString),
              let size = sizeAttribute(window, kAXSizeAttribute as CFString) else {
            return nil
        }
        return appKitRect(fromTopLeft: CGRect(origin: origin, size: size))
    }

    private static func pointAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        guard let value = attributeValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        guard let value = attributeValue(element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func attributeValue(_ element: AXUIElement, _ attribute: CFString) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    static func appKitRect(fromTopLeft cgRect: CGRect) -> NSRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let height = primary?.frame.height ?? 0
        return NSRect(
            x: cgRect.origin.x,
            y: height - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }
}
