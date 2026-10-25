import ApplicationServices
import AppKit

@MainActor
final class PasteService {
    /// Accessibility is granted to an app identity, not to its display name.
    /// Keeping the current path in the status makes it clear when the user
    /// authorised an older copy of the app.
    struct AccessibilityStatus: Equatable {
        let axTrusted: Bool
        let eventPostingTrusted: Bool
        let bundlePath: String
        let bundleIdentifier: String

        var trusted: Bool { axTrusted }

        var message: String {
            if trusted {
                return "已授权当前运行的应用副本"
            }
            if axTrusted && !eventPostingTrusted {
                return "辅助功能已授权；系统键盘事件状态仍在刷新，应用会继续尝试粘贴。"
            }
            if !axTrusted && eventPostingTrusted {
                return "键盘事件权限已授权，但辅助功能仍未授权。请勾选当前应用副本。"
            }
            return "未授权当前运行的应用副本。请在列表中勾选下面显示的这一份。"
        }

        @MainActor static var current: AccessibilityStatus {
            AccessibilityStatus(
                axTrusted: PasteService.isAXTrusted(prompt: false),
                eventPostingTrusted: PasteService.isEventPostingTrusted(),
                bundlePath: Bundle.main.bundlePath,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "local.cliphistory"
            )
        }
    }

    private let tracker: FrontAppTracker
    private let monitor: ClipboardMonitor

    init(tracker: FrontAppTracker, monitor: ClipboardMonitor) {
        self.tracker = tracker
        self.monitor = monitor
    }

    /// Resolve the destination before the panel receives focus.
    func capturePasteTarget() -> NSRunningApplication? {
        tracker.capturePasteTarget()
    }

    func frontmostOtherApp() -> NSRunningApplication? {
        tracker.frontmostOtherApp()
    }

    /// Writes text to clipboard without triggering `⌘V`.
    func copyOnly(_ text: String) {
        monitor.writeWithoutRecording(text)
    }

    /// Writes image data to clipboard without triggering `⌘V`.
    func copyImageOnly(_ data: Data) {
        monitor.writeImageWithoutRecording(data)
    }

    func paste(_ text: String, preferredApp: NSRunningApplication? = nil) {
        monitor.writeWithoutRecording(text)
        deliver(preferredApp: preferredApp)
    }

    func pasteImage(_ data: Data, preferredApp: NSRunningApplication? = nil) {
        monitor.writeImageWithoutRecording(data)
        deliver(preferredApp: preferredApp)
    }

    private func deliver(preferredApp: NSRunningApplication?) {
        let target = preferredApp ?? tracker.frontmostOtherApp()
        guard let target, !FrontAppTracker.isSelf(target), !target.isTerminated else {
            NSLog("剪贴板记录没有找到粘贴目标；内容已写入剪贴板")
            return
        }
        guard Self.isTrusted(prompt: false) else {
            NSLog("剪贴板记录没有辅助功能权限；内容已写入剪贴板，跳过 ⌘V (bundle=%@)", Bundle.main.bundlePath)
            return
        }

        var attempts = 0
        let pid = target.processIdentifier

        func activateAndPaste() {
            guard !target.isTerminated else { return }
            let alreadyFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            if !alreadyFrontmost {
                _ = target.activate()
            }
            let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            if isFrontmost || attempts >= 20 {
                let settle = alreadyFrontmost ? 0.025 : (isFrontmost ? 0.04 : 0.03)
                DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                    guard !target.isTerminated else { return }
                    Self.postCommandV(to: pid, isFrontmost: isFrontmost)
                }
                return
            }
            attempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                activateAndPaste()
            }
        }

        let initialDelay = (NSWorkspace.shared.frontmostApplication?.processIdentifier == pid) ? 0.005 : 0.015
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) {
            activateAndPaste()
        }
    }

    static func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            _ = isAXTrusted(prompt: true)
        }
        return isAXTrusted(prompt: false)
    }

    private static func isAXTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [key: prompt] as NSDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func isEventPostingTrusted() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightPostEventAccess()
        }
        return false
    }

    static func requestAccessibilityAccess() {
        _ = isTrusted(prompt: true)
        openAccessibilitySettings()
    }

    static func revealCurrentApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for raw in candidates {
            if let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    private static func postCommandV(to processID: pid_t, isFrontmost: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false)
        up?.flags = .maskCommand
        if isFrontmost {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        } else {
            down?.postToPid(processID)
            up?.postToPid(processID)
        }
    }
}
