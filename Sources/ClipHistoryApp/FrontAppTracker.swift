import AppKit

@MainActor
final class FrontAppTracker {
    private(set) var previousApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    func start() {
        rememberCurrent()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                guard let self, let app else { return }
                if !Self.isSelf(app), !app.isTerminated {
                    self.previousApp = app
                }
            }
        }
    }

    func rememberCurrent() {
        if let app = NSWorkspace.shared.frontmostApplication,
           !Self.isSelf(app),
           !app.isTerminated {
            previousApp = app
        }
    }

    /// Capture the application that was in front immediately before the
    /// history panel became active.  The panel itself is a non-activating
    /// window, but AppKit can still report this process as frontmost for a
    /// run-loop turn while the hotkey/status-item action is being handled.
    /// Keeping the captured instance avoids trying to rediscover the target
    /// after the user clicks a row in the panel.
    func capturePasteTarget() -> NSRunningApplication? {
        if let app = NSWorkspace.shared.frontmostApplication,
           !Self.isSelf(app),
           !app.isTerminated {
            previousApp = app
            return app
        }
        guard let previousApp, !previousApp.isTerminated else { return nil }
        return previousApp
    }

    func frontmostOtherApp() -> NSRunningApplication? {
        if let app = NSWorkspace.shared.frontmostApplication,
           !Self.isSelf(app),
           !app.isTerminated {
            return app
        }
        guard let previousApp, !previousApp.isTerminated else { return nil }
        return previousApp
    }

    static func isSelf(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
}
