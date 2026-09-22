import ApplicationServices
import AppKit

@MainActor
final class PasteService {
    private let tracker: FrontAppTracker
    private let monitor: ClipboardMonitor

    init(tracker: FrontAppTracker, monitor: ClipboardMonitor) {
        self.tracker = tracker
        self.monitor = monitor
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
        if let target, !FrontAppTracker.isSelf(target) {
            target.activate()
        }
        guard Self.isTrusted(prompt: false) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.postCommandV()
        }
    }

    static func isTrusted(prompt: Bool) -> Bool {
        if !prompt {
            return AXIsProcessTrusted()
        }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [key: true] as NSDictionary
        return AXIsProcessTrustedWithOptions(options)
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

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x09), keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
