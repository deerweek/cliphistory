import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var store: Store!
    private var settings: AppSettings!
    private var monitor: ClipboardMonitor!
    private var tracker: FrontAppTracker!
    private var pasteService: PasteService!
    private var hotkey: HotkeyListener!
    private var panelController: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToInstalledCopy() {
            return
        }
        closeOtherCopies()
        settings = AppSettings.shared
        do {
            store = try Store(path: AppPaths.databasePath())
        } catch {
            presentAlert(title: "无法启动", message: "本地数据库创建失败：\(error.localizedDescription)")
            NSApp.terminate(nil)
            return
        }

        tracker = FrontAppTracker()
        tracker.start()
        monitor = ClipboardMonitor(store: store, settings: settings)
        pasteService = PasteService(tracker: tracker, monitor: monitor)
        panelController = PanelController(store: store, pasteService: pasteService, settings: settings)
        panelController.onHotkeyChange = { [weak self] combo in
            self?.hotkey.register(combo)
            self?.rebuildMenu()
        }
        panelController.onSnippetError = { [weak self] message in
            self?.presentAlert(title: "无法保存", message: message)
        }
        panelController.settingsModel.onHotkeyChange = panelController.onHotkeyChange
        monitor.onChange = { [weak self] in
            self?.panelController.reloadIfVisible()
            self?.rebuildMenu()
        }
        setupStatusItem()
        monitor.start()
        syncLaunchAtLogin()

        hotkey = HotkeyListener()
        hotkey.onPress = { [weak self] in
            self?.tracker.rememberCurrent()
            self?.panelController.toggleFromHotkey()
        }
        hotkey.register(settings.hotkey)

        rebuildMenu()
        panelController.applyDisplayMode()
        if !PasteService.isTrusted(prompt: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                _ = PasteService.isTrusted(prompt: true)
            }
        }
    }

    private func handOffToInstalledCopy() -> Bool {
        let installed = Self.installedAppURL.standardizedFileURL
        let current = Bundle.main.bundleURL.standardizedFileURL
        guard current != installed else { return false }
        guard FileManager.default.fileExists(atPath: installed.path) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: installed, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        return true
    }

    private func closeOtherCopies() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.cliphistory") {
            if app.processIdentifier != ownPID {
                app.terminate()
            }
        }
    }

    static var installedAppURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/剪贴板记录.app", isDirectory: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "剪贴板记录")
            button.image?.isTemplate = true
        }
    }

    private func syncLaunchAtLogin() {
        guard settings.launchAtLogin else { return }
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("登录时启动注册失败：\(error.localizedDescription)")
        }
    }

    private func savedCount() -> Int {
        (try? store.items().count) ?? 0
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: "后台运行中 · 已保存 \(savedCount()) 条", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开面板（\(settings.hotkey.menuLabel)）", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: "添加快捷回复", action: #selector(openAddSnippet), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "清空未置顶", action: #selector(clearUnpinned), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openPanel() {
        tracker.rememberCurrent()
        panelController.show(page: .list, makeKey: true)
    }

    @objc private func openAddSnippet() {
        tracker.rememberCurrent()
        panelController.show(page: .composer, makeKey: true)
    }

    @objc private func openSettings() {
        tracker.rememberCurrent()
        panelController.show(page: .settings, makeKey: true)
    }

    @objc private func clearUnpinned() {
        try? store.clearUnpinnedHistory()
        panelController.reloadIfVisible()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
