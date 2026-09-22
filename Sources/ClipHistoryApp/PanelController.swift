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
    /// Destination captured before the panel takes focus.  Looking up the
    /// frontmost application at row-click time can return this app instead of
    /// the chat/editor where the user actually wants the paste.
    private var pasteTarget: NSRunningApplication?

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
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "剪贴板记录"
        // Chromeless floating look: let the material content fill the full
        // height under a transparent, text-less title bar. PanelView reserves a
        // top inset so content never sits under the traffic-light buttons.
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
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

    func show(page: PanelPage = .list, makeKey: Bool = true, capturePasteTarget: Bool = true) {
        if page == .list, capturePasteTarget {
            // Capture before makeKeyAndOrderFront/NSApp.activate below.
            // In attached mode the configured app is a stronger signal than
            // whatever happened to be frontmost while opening the menu.
            pasteTarget = preferredPasteTarget() ?? pasteService.capturePasteTarget()
        }
        model.page = page
        if page == .list {
            model.category = nil
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
        // The panel is a non-activating window, but AppKit can leave this
        // accessory process as the active application for one run-loop turn.
        // Explicitly relinquish activation before the target receives ⌘V.
        NSApp.deactivate()
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
        // Use the process captured when the panel opened.  If the user opened
        // the panel from an attached-app mode, preferredPasteTarget() remains
        // a fallback for the case where that app restarted between opening
        // and selecting an item.
        let captured = pasteTarget.flatMap { $0.isTerminated ? nil : $0 }
        let preferred = captured ?? preferredPasteTarget() ?? pasteService.capturePasteTarget()
        pasteTarget = nil
        let restorePanel = settings.panelMode != .dismissAfterPaste
        if restorePanel {
            temporarilyHideForPaste()
        } else {
            hide()
        }
        if item.contentType == .image, let data = item.imageData {
            pasteService.pasteImage(data, preferredApp: preferred)
        } else {
            pasteService.paste(item.body, preferredApp: preferred)
        }
        if restorePanel {
            // PasteService waits for the destination to activate and may retry
            // for about a second. Restore afterwards so the panel never steals
            // the destination's key window before ⌘V is delivered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, !self.userDismissed,
                      self.settings.panelMode != .dismissAfterPaste else { return }
                self.show(page: .list, makeKey: false, capturePasteTarget: false)
            }
        }
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

    private func temporarilyHideForPaste() {
        stopFollowing()
        panel.orderOut(nil)
        removeKeyMonitor()
        NSApp.deactivate()
    }

    private func ensureVisible(makeKey: Bool) {
        if panel.isVisible {
            if settings.panelMode == .attachedToApp {
                followAttachedWindow()
            } else {
                panel.orderFrontRegardless()
            }
            return
        }
        show(page: model.page, makeKey: makeKey)
    }

    private func applyLevel() {
        switch settings.panelMode {
        case .dismissAfterPaste:
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        case .alwaysOnTop:
            panel.isFloatingPanel = true
            panel.level = Self.topLevel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        case .attachedToApp:
            // An attached panel belongs to the target application's normal
            // window stack. The old assistiveTechHighWindow level and
            // canJoinAllSpaces made it float above every other app.
            panel.isFloatingPanel = false
            panel.level = .normal
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
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
        guard let target = WindowLocator.mainWindow(bundleID: bundleID),
              let screen = screen(containing: target.frame) else {
            model.attachStatus = "\(name) 没有打开，或还没允许辅助功能"
            return
        }
        model.attachStatus = "吸附在\(name)旁边"
        let ideal = PanelPlacement.snappedOrigin(
            panel: panel.frame.size,
            target: target.frame,
            screen: screen.visibleFrame
        )
        let desired = PanelPlacement.clampedOrigin(
            CGPoint(x: ideal.x + dragOffset.width, y: ideal.y + dragOffset.height),
            panel: panel.frame.size,
            screen: screen.visibleFrame
        )
        let current = panel.frame.origin
        if abs(current.x - desired.x) > 1 || abs(current.y - desired.y) > 1 {
            adjustingFrame = true
            panel.setFrameOrigin(desired)
            adjustingFrame = false
        }
        orderAttachedPanel(above: target.windowNumber)
    }

    /// Keep the panel immediately above the configured app's main window,
    /// while leaving windows from other applications above it. A CG window
    /// id is unavailable when the Accessibility fallback is used, in which
    /// case normal-level ordering still gives the expected app-scoped stack.
    private func orderAttachedPanel(above windowNumber: CGWindowID?) {
        guard settings.panelMode == .attachedToApp else { return }
        if let windowNumber {
            panel.order(.above, relativeTo: Int(windowNumber))
        } else {
            panel.orderFront(nil)
        }
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
        // ⌘1–9 pastes the Nth visible item directly (no mouse needed).
        if event.modifierFlags.contains(.command), let index = Self.digitIndex(for: event.keyCode) {
            if index < model.items.count {
                paste(model.items[index])
                return nil
            }
        }
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

    /// Maps a number-row key code (1–9) to a 0-based list index.
    private static func digitIndex(for keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 0
        case 19: return 1
        case 20: return 2
        case 21: return 3
        case 23: return 4
        case 22: return 5
        case 26: return 6
        case 28: return 7
        case 25: return 8
        default: return nil
        }
    }
}
