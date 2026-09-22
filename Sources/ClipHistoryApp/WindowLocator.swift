import AppKit
import ApplicationServices

enum WindowLocator {
    /// Largest normal window of the app, in AppKit coordinates (origin at bottom-left).
    static func mainWindowFrame(bundleID: String) -> NSRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }
        if let frame = cgWindowFrame(pid: app.processIdentifier) {
            return frame
        }
        return axWindowFrame(pid: app.processIdentifier)
    }

    private static func cgWindowFrame(pid: pid_t) -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let frames: [CGRect] = list.compactMap { info in
            let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue ?? -1
            guard owner == Int(pid) else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { return nil }
            guard let rect = cgRect(info[kCGWindowBounds as String]), rect.width >= 240, rect.height >= 160 else {
                return nil
            }
            return rect
        }
        guard let largest = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }
        return appKitRect(fromTopLeft: largest)
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
