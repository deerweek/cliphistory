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
                if !Self.isSelf(app) {
                    self.previousApp = app
                }
            }
        }
    }

    func rememberCurrent() {
        if let app = NSWorkspace.shared.frontmostApplication, !Self.isSelf(app) {
            previousApp = app
        }
    }

    func frontmostOtherApp() -> NSRunningApplication? {
        if let app = NSWorkspace.shared.frontmostApplication, !Self.isSelf(app) {
            return app
        }
        return previousApp
    }

    static func isSelf(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
}
