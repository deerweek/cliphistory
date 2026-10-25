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
    private var textExpander: TextExpanderService!
    private var hotkey: HotkeyListener!
    private var panelController: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        tracker.onAppActivated = { [weak self] app in
            self?.panelController.handleExternalAppActivated(app)
        }

        textExpander = TextExpanderService(store: store, settings: settings, pasteService: pasteService)
        textExpander.onExpanded = { [weak self] _ in
            self?.panelController.reloadIfVisible()
        }
        textExpander.start()

        panelController.onHotkeyChange = { [weak self] combo in
            self?.hotkey.register(combo)
        }
        panelController.onCleanupRulesChange = { [weak self] in
            self?.monitor.runCleanupNow()
            self?.panelController.reloadIfVisible()
        }
        panelController.onSnippetError = { [weak self] message in
            self?.presentAlert(title: "无法保存", message: message)
        }
        panelController.settingsModel.onHotkeyChange = panelController.onHotkeyChange
        panelController.settingsModel.onCleanupRulesChange = panelController.onCleanupRulesChange
        panelController.settingsModel.onPauseStateChange = { [weak self] paused in
            self?.panelController.model.isRecordingPaused = paused
            self?.updateStatusItemAppearance()
        }
        panelController.model.onPauseStateChange = { [weak self] in
            guard let self else { return }
            self.panelController.settingsModel.isRecordingPaused = self.settings.isRecordingPaused
            self.updateStatusItemAppearance()
        }

        monitor.onChange = { [weak self] in
            self?.panelController.reloadIfVisible()
        }
        monitor.onItemRecorded = { [weak self] item in
            self?.panelController.handleNewlyCopiedItem(item)
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

        panelController.applyDisplayMode()
    }

    private func closeOtherCopies() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.cliphistory") {
            guard app.processIdentifier != ownPID else { continue }
            if !app.terminate() {
                app.forceTerminate()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusItemAppearance()
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let paused = settings.isRecordingPaused
        let symbol = paused ? "pause.circle" : "doc.on.clipboard"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: paused ? "剪贴板记录（已暂停）" : "剪贴板记录")
        button.image?.isTemplate = true
        button.toolTip = paused ? "已暂停记录剪贴板 · 左键打开面板 / 右键恢复" : "左键打开面板 · 右键显示菜单"
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            tracker.rememberCurrent()
            panelController.toggleFromStatusItem()
            return
        }
        let isRightClick = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.option)

        if isRightClick {
            let menu = buildContextMenu()
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            tracker.rememberCurrent()
            panelController.toggleFromStatusItem()
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
        (try? store.totalCount()) ?? 0
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        let paused = settings.isRecordingPaused
        let statusTitle = paused
            ? "已暂停记录剪贴板 · 已保存 \(savedCount()) 条"
            : "后台运行中 · 已保存 \(savedCount()) 条"
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开面板（\(settings.hotkey.menuLabel)）", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(withTitle: "添加快捷回复与短码…", action: #selector(openAddSnippet), keyEquivalent: "")
        menu.addItem(withTitle: "动作工坊（插件管理）…", action: #selector(openActionStudio), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: paused ? "恢复记录剪贴板" : "暂停记录剪贴板（保护密码/隐私）",
            action: #selector(togglePauseRecording),
            keyEquivalent: ""
        )
        menu.addItem(withTitle: "清空未置顶历史", action: #selector(clearUnpinned), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        return menu
    }

    @objc private func openPanel() {
        tracker.rememberCurrent()
        panelController.show(page: .list, makeKey: true)
    }

    @objc private func openAddSnippet() {
        tracker.rememberCurrent()
        panelController.openComposerForNewSnippet()
    }

    @objc private func openActionStudio() {
        tracker.rememberCurrent()
        panelController.openActionStudio()
    }

    @objc private func openSettings() {
        tracker.rememberCurrent()
        panelController.show(page: .settings, makeKey: true)
    }

    @objc private func togglePauseRecording() {
        panelController.model.toggleRecordingPaused()
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
