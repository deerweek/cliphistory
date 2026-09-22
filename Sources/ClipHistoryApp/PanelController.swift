import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let model: PanelModel
    let settingsModel: SettingsModel
    private let settings: AppSettings
    private let pasteService: PasteService
    private let panel: NSPanel
    private var localMonitor: Any?
    private var followTimer: Timer?
    private var adjustingFrame = false
    private var dragOffset = CGSize.zero
    private var followedBundleID = ""
    private var userDismissed = false
    private var appliedMode: PanelMode?

    var isVisible: Bool { panel.isVisible }
    var onHotkeyChange: ((HotkeyCombo) -> Void)?
    var onSnippetError: ((String) -> Void)?

    init(store: Store, pasteService: PasteService, settings: AppSettings) {
        self.model = PanelModel(store: store)
        self.settings = settings
        self.pasteService = pasteService
        self.settingsModel = SettingsModel(settings: settings)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "剪贴板记录"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self
        panel.minSize = NSSize(width: 420, height: 480)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        settingsModel.onDisplayChange = { [weak self] in
            self?.applyDisplayMode()
        }

        let root = PanelView(
            model: model,
            settingsModel: settingsModel,
            onPaste: { [weak self] item in
                self?.paste(item)
            },
            onSaveSnippet: { [weak self] title, body in
                self?.saveSnippet(title: title, body: body)
            },
            onClearUnpinned: { [weak self] in
                self?.model.clearUnpinned()
            },
            onPageChange: { [weak self] page in
                self?.panel.title = page.title
            }
        )
        panel.contentView = NSHostingView(rootView: root)
    }

    func show(page: PanelPage = .list, makeKey: Bool = true) {
        model.page = page
        if page == .list {
            model.query = ""
            model.reload()
        }
        userDismissed = false
        model.refreshAccess()
        panel.title = page.title
        if !panel.isVisible, settings.panelMode != .attachedToApp {
            positionOnActiveScreen()
        }
        applyLevel()
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            panel.orderFrontRegardless()
        }
        installKeyMonitor()
        if settings.panelMode == .attachedToApp {
            startFollowing()
        }
    }

    func hide() {
        userDismissed = true
        stopFollowing()
        panel.orderOut(nil)
        removeKeyMonitor()
    }

    func toggleFromHotkey() {
        if isVisible {
            if model.page != .list {
                model.page = .list
                panel.title = PanelPage.list.title
            } else {
                hide()
            }
            return
        }
        show(page: .list, makeKey: true)
    }

    func applyDisplayMode() {
        let modeChanged = appliedMode != settings.panelMode
        appliedMode = settings.panelMode
        if modeChanged {
            userDismissed = false
        }
        applyLevel()
        switch settings.panelMode {
        case .dismissAfterPaste:
            stopFollowing()
            model.attachStatus = nil
        case .alwaysOnTop:
            stopFollowing()
            model.attachStatus = nil
            if !userDismissed {
                ensureVisible(makeKey: false)
            }
        case .attachedToApp:
            if followedBundleID != settings.attachedBundleID {
                dragOffset = .zero
                followedBundleID = settings.attachedBundleID
            }
            if userDismissed {
                stopFollowing()
            } else {
                startFollowing()
                ensureVisible(makeKey: false)
            }
        }
    }

    func reloadIfVisible() {
        guard isVisible else { return }
        model.reload()
    }

    func paste(_ item: ClipItem) {
        let preferred = preferredPasteTarget()
        if settings.panelMode == .dismissAfterPaste {
            hide()
        }
        pasteService.paste(item.body, preferredApp: preferred)
    }

    func windowWillClose(_ notification: Notification) {
        userDismissed = true
        stopFollowing()
        removeKeyMonitor()
    }

    func windowDidMove(_ notification: Notification) {
        guard !adjustingFrame, settings.panelMode == .attachedToApp else { return }
        guard let target = WindowLocator.mainWindowFrame(bundleID: settings.attachedBundleID),
              let screen = screen(containing: target) else { return }
        let ideal = PanelPlacement.snappedOrigin(
            panel: panel.frame.size,
            target: target,
            screen: screen.visibleFrame
        )
        dragOffset = CGSize(
            width: panel.frame.origin.x - ideal.x,
            height: panel.frame.origin.y - ideal.y
        )
    }

    private func saveSnippet(title: String, body: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }
        do {
            try model.store.addSnippet(title: trimmedTitle.isEmpty ? nil : trimmedTitle, body: trimmedBody)
            model.page = .list
            panel.title = PanelPage.list.title
            model.reload()
        } catch {
            onSnippetError?(error.localizedDescription)
        }
    }

    private func preferredPasteTarget() -> NSRunningApplication? {
        guard settings.panelMode == .attachedToApp, !settings.attachedBundleID.isEmpty else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: settings.attachedBundleID).first
    }

    private func ensureVisible(makeKey: Bool) {
        if panel.isVisible {
            panel.orderFrontRegardless()
            return
        }
        show(page: model.page, makeKey: makeKey)
    }

    private func applyLevel() {
        switch settings.panelMode {
        case .dismissAfterPaste:
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        case .alwaysOnTop:
            panel.level = Self.topLevel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        case .attachedToApp:
            panel.level = Self.topLevel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }

    private func positionOnActiveScreen() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let size = panel.frame.size
        let origin = NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2 + 36
        )
        panel.setFrameOrigin(origin)
    }

    private func startFollowing() {
        followTimer?.invalidate()
        followAttachedWindow()
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.followAttachedWindow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
    }

    private func followAttachedWindow() {
        guard settings.panelMode == .attachedToApp else { return }
        let bundleID = settings.attachedBundleID
        guard !bundleID.isEmpty else {
            model.attachStatus = "请在设置里选择要吸附的应用"
            return
        }
        let name = KnownApps.displayName(for: bundleID)
        guard let target = WindowLocator.mainWindowFrame(bundleID: bundleID),
              let screen = screen(containing: target) else {
            model.attachStatus = "\(name) 没有打开，或还没允许辅助功能"
            return
        }
        model.attachStatus = "吸附在\(name)旁边"
        let ideal = PanelPlacement.snappedOrigin(
            panel: panel.frame.size,
            target: target,
            screen: screen.visibleFrame
        )
        let desired = PanelPlacement.clampedOrigin(
            CGPoint(x: ideal.x + dragOffset.width, y: ideal.y + dragOffset.height),
            panel: panel.frame.size,
            screen: screen.visibleFrame
        )
        let current = panel.frame.origin
        guard abs(current.x - desired.x) > 1 || abs(current.y - desired.y) > 1 else { return }
        adjustingFrame = true
        panel.setFrameOrigin(desired)
        adjustingFrame = false
        panel.orderFrontRegardless()
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handleKey(event)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 {
            if model.page != .list {
                model.page = .list
                panel.title = PanelPage.list.title
            } else {
                hide()
            }
            return nil
        }
        guard model.page == .list else { return event }
        switch event.keyCode {
        case 36, 76:
            if let item = model.selectedItem {
                paste(item)
                return nil
            }
        case 125:
            model.moveSelection(1)
            return nil
        case 126:
            model.moveSelection(-1)
            return nil
        case 51 where event.modifierFlags.contains(.option):
            if let item = model.selectedItem {
                model.delete(item)
                return nil
            }
        case 35 where event.modifierFlags.contains(.option):
            if let item = model.selectedItem {
                model.togglePin(item)
                return nil
            }
        default:
            break
        }
        return event
    }

    private func removeKeyMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private static let topLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
}
