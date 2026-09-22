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

        /// Accessibility is the permission required by this app's direct
        /// `CGEvent` delivery.  The post-event preflight is kept as a
        /// diagnostic only: on some macOS versions it reports false until a
        /// process has posted its first event even though the Accessibility
        /// checkbox is already enabled.  Gating paste on that transient value
        /// made the UI claim "未授权" and skipped every paste.
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

    /// Resolve the destination before the panel receives focus.  Callers
    /// should retain the returned process and pass it back to `paste`; doing
    /// a fresh frontmost-app lookup after a row click is racy because the
    /// panel is then the active application.
    func capturePasteTarget() -> NSRunningApplication? {
        tracker.capturePasteTarget()
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
            // There is no safe destination if the panel was opened without a
            // previous application. Keep the selected value on the clipboard
            // so the user can still paste it manually.
            NSLog("剪贴板记录没有找到粘贴目标；内容已写入剪贴板")
            return
        }
        guard Self.isTrusted(prompt: false) else {
            NSLog("剪贴板记录没有辅助功能权限；内容已写入剪贴板，跳过 ⌘V (bundle=%@)", Bundle.main.bundlePath)
            return
        }

        // Activating an application is asynchronous. A fixed delay works for
        // most apps, but chat clients can take longer to make their input
        // window key. Retry activation until the target is frontmost, then
        // post directly to its process. The target was captured before the
        // panel opened, so this cannot accidentally become the panel.
        var attempts = 0
        let pid = target.processIdentifier
        NSLog("剪贴板记录准备粘贴到 %@ (pid=%d, bundle=%@, path=%@)",
              target.localizedName ?? "未知应用",
              pid,
              target.bundleIdentifier ?? "(无 bundle id)",
              target.bundleURL?.path ?? "(无路径)")
        func activateAndPaste() {
            guard !target.isTerminated else { return }
            // A non-activating panel can remain the active application even
            // after it has been ordered out. `activateAllWindows` alone only
            // orders the target's windows; it does not always transfer the
            // active application on macOS. Force the hand-off before posting
            // the per-process event so ⌘V cannot be consumed by our panel.
            _ = target.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
            if isFrontmost || attempts >= 20 {
                // Route the event directly to the destination process. A
                // global event tap can race with the panel's final mouse/key
                // event and send ⌘V back to this app instead.
                // Even when the workspace reports the target as frontmost,
                // its key window may not have been restored yet. Give AppKit
                // one run-loop turn (and a short settling interval) after
                // activation before injecting the command.
                let settle = isFrontmost ? 0.22 : 0.08
                DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                    guard !target.isTerminated else { return }
                    Self.postCommandV(to: pid)
                    NSLog("剪贴板记录已发送 ⌘V 到 pid=%d", pid)
                }
                return
            }
            attempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                activateAndPaste()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
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

    /// Ask macOS to show its consent prompt and then open the exact
    /// Accessibility settings pane. SettingsView polls the status afterwards,
    /// so enabling the checkbox is reflected without restarting the app.
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

    private static func postCommandV(to processID: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false)
        up?.flags = .maskCommand
        down?.postToPid(processID)
        up?.postToPid(processID)
    }
}
