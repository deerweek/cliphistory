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
    private var appliedPreviewPane: Bool?
    private var pasteTarget: NSRunningApplication?
    private var hasCustomUserPosition = false
    private var lastPositionedScreen: NSScreen?
    private var actionTask: Task<Void, Never>?
    private var isSequentialPasting = false

    var isVisible: Bool { panel.isVisible }
    var onHotkeyChange: ((HotkeyCombo) -> Void)?
    var onCleanupRulesChange: (() -> Void)?
    var onSnippetError: ((String) -> Void)?

    init(store: Store, pasteService: PasteService, settings: AppSettings) {
        self.model = PanelModel(store: store)
        self.settings = settings
        self.pasteService = pasteService
        self.settingsModel = SettingsModel(settings: settings)
        let initialWidth: CGFloat = settings.showPreviewPane ? 780 : 520
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: 570),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.title = "剪贴板记录"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = CGFloat(settings.panelOpacity)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.minSize = NSSize(width: 460, height: 500)
        panel.standardWindowButton(.closeButton)?.isHidden = true
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
            onPasteRawText: { [weak self] text, itemID in
                self?.pasteRawText(text, itemID: itemID)
            },
            onCopyOnly: { [weak self] item in
                self?.copyOnly(item)
            },
            onCopyRawText: { [weak self] text in
                self?.copyRawText(text)
            },
            onTranslateItem: { [weak self] item, pasteImmediately in
                self?.translateItem(item, pasteImmediately: pasteImmediately)
            },
            onRunAction: { [weak self] action, item in
                self?.runClipAction(action, on: item)
            },
            onRecognizeImageText: { [weak self] item in
                self?.recognizeImageText(item)
            },
            onExportImage: { [weak self] item in
                self?.exportImage(item)
            },
            onSaveItem: { [weak self] id, title, body, kind, triggerCode, smartTag in
                self?.saveItem(
                    id: id,
                    title: title,
                    body: body,
                    kind: kind,
                    triggerCode: triggerCode,
                    smartTag: smartTag
                )
            },
            onClearUnpinned: { [weak self] in
                self?.model.clearUnpinned()
            },
            onClose: { [weak self] in
                self?.hide()
            },
            onPageChange: { [weak self] page in
                guard let self else { return }
                self.panel.title = page.title
                self.syncWindowSizeForLayout(animated: true)
            }
        )
        panel.contentView = NSHostingView(rootView: root)
    }

    func handleExternalAppActivated(_ app: NSRunningApplication) {
        guard !FrontAppTracker.isSelf(app), !app.isTerminated else { return }
        if settings.panelMode == .attachedToApp, let attached = preferredPasteTarget() {
            pasteTarget = attached
            model.updatePasteTarget(attached)
        } else {
            pasteTarget = app
            model.updatePasteTarget(app)
        }
    }

    private func resolvedPasteTarget() -> NSRunningApplication? {
        if settings.panelMode == .attachedToApp, let attached = preferredPasteTarget(), !attached.isTerminated {
            return attached
        }
        if let front = pasteService.frontmostOtherApp(), !front.isTerminated {
            return front
        }
        if let captured = pasteTarget, !captured.isTerminated {
            return captured
        }
        return preferredPasteTarget()
    }

    func openComposerForNewSnippet() {
        pasteTarget = resolvedPasteTarget() ?? pasteService.capturePasteTarget()
        model.updatePasteTarget(pasteTarget)
        model.openNewSnippet()
        show(page: .composer, makeKey: true, capturePasteTarget: false)
    }

    func openActionStudio() {
        pasteTarget = resolvedPasteTarget() ?? pasteService.capturePasteTarget()
        model.updatePasteTarget(pasteTarget)
        show(page: .actions, makeKey: true, capturePasteTarget: false)
    }

    func handleNewlyCopiedItem(_ item: ClipItem) {
        model.handleNewlyCopiedItem(item)
    }

    func show(page: PanelPage = .list, makeKey: Bool = true, capturePasteTarget: Bool = true) {
        if capturePasteTarget {
            pasteTarget = preferredPasteTarget() ?? pasteService.capturePasteTarget()
            model.updatePasteTarget(pasteTarget)
        }
        model.page = page
        if page == .list {
            model.reload()
            model.requestSearchFocus()
        }
        userDismissed = false
        model.refreshAccess()
        panel.title = page.title
        syncWindowSizeForLayout(animated: false)
        if !panel.isVisible, settings.panelMode != .attachedToApp {
            positionOnActiveScreen()
        }
        applyLevel()
        applyAppearance()
        if makeKey {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
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
        NSApp.deactivate()
    }

    func toggleFromHotkey() {
        if isVisible {
            if model.page != .list {
                show(page: .list, makeKey: true)
            } else if !panel.isKeyWindow {
                show(page: .list, makeKey: true)
            } else {
                hide()
            }
            return
        }
        show(page: .list, makeKey: true)
    }

    func toggleFromStatusItem() {
        if isVisible && model.page == .list {
            hide()
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
        let previewChanged = appliedPreviewPane != settings.showPreviewPane
        appliedPreviewPane = settings.showPreviewPane
        if previewChanged {
            syncWindowSizeForLayout(animated: true)
        }

        applyLevel()
        applyAppearance()
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
            if let preferred = preferredPasteTarget() {
                pasteTarget = preferred
                model.updatePasteTarget(preferred)
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

    func copyOnly(_ item: ClipItem) {
        if item.contentType == .image, let data = item.imageData {
            pasteService.copyImageOnly(data)
        } else {
            let expanded = ClipActionEngine.expandTemplateVariables(
                in: item.body,
                currentClipboard: NSPasteboard.general.string(forType: .string)
            )
            pasteService.copyOnly(expanded)
        }
        try? model.store.recordUse(id: item.id)
        model.reload()
        model.showToast("已复制到系统剪贴板", symbol: "doc.on.doc.fill")
    }

    func copyRawText(_ text: String) {
        pasteService.copyOnly(text)
        model.showToast("已复制结果到剪贴板", symbol: "doc.on.doc.fill")
    }

    func pasteRawText(_ text: String, itemID: Int64? = nil) {
        let preferred = resolvedPasteTarget()
        let keepPanelVisible = settings.panelMode != .dismissAfterPaste

        if let itemID {
            try? model.store.recordUse(id: itemID)
            if itemID == model.recommendedReply?.id {
                model.dismissRecommendedReply()
            }
        }
        if !keepPanelVisible {
            pasteTarget = nil
            hide()
        } else {
            NSApp.deactivate()
        }
        pasteService.paste(text, preferredApp: preferred)
        if keepPanelVisible {
            let targetName = preferred?.localizedName ?? "目标应用"
            model.reload()
            model.showToast("已粘贴到 \(targetName)", symbol: "paperplane.fill")
        }
    }

    func paste(_ item: ClipItem) {
        let preferred = resolvedPasteTarget()
        let keepPanelVisible = settings.panelMode != .dismissAfterPaste

        try? model.store.recordUse(id: item.id)
        if item.id == model.recommendedReply?.id {
            model.dismissRecommendedReply()
        }

        if !keepPanelVisible {
            pasteTarget = nil
            hide()
        } else {
            NSApp.deactivate()
        }

        if item.contentType == .image, let data = item.imageData {
            pasteService.pasteImage(data, preferredApp: preferred)
        } else {
            let expanded = ClipActionEngine.expandTemplateVariables(
                in: item.body,
                currentClipboard: NSPasteboard.general.string(forType: .string)
            )
            pasteService.paste(expanded, preferredApp: preferred)
        }

        if keepPanelVisible {
            let targetName = preferred?.localizedName ?? "目标应用"
            model.reload()
            model.showToast("已粘贴到 \(targetName)", symbol: "paperplane.fill")
        }
    }

    /// Pastes the selected item into the target app without closing the panel and advances selection to the next item (`⇧↵`).
    func pasteAndAdvance(_ item: ClipItem) {
        let preferred = resolvedPasteTarget()
        try? model.store.recordUse(id: item.id)
        if item.id == model.recommendedReply?.id {
            model.dismissRecommendedReply()
        }

        isSequentialPasting = true
        NSApp.deactivate()

        if item.contentType == .image, let data = item.imageData {
            pasteService.pasteImage(data, preferredApp: preferred)
        } else {
            let expanded = ClipActionEngine.expandTemplateVariables(
                in: item.body,
                currentClipboard: NSPasteboard.general.string(forType: .string)
            )
            pasteService.paste(expanded, preferredApp: preferred)
        }

        let targetName = preferred?.localizedName ?? "目标应用"
        model.reload()
        model.moveSelection(1)
        model.showToast("已连贴到 \(targetName) · 已下移至下一条 (⇧↵)", symbol: "arrow.down.doc.fill")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self else { return }
            if self.panel.isVisible {
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)
            }
            self.isSequentialPasting = false
        }
    }

    func recognizeImageText(_ item: ClipItem) {
        guard item.contentType == .image, let data = item.imageData else { return }
        actionTask?.cancel()
        model.isRunningAction = true
        model.showToast("正在识别图中文字 (OCR)…", symbol: "text.viewfinder")

        let storeRef = model.store
        actionTask = Task { @MainActor in
            defer { self.model.isRunningAction = false }
            do {
                let recognized = try await SmartService.shared.recognizeTextInImage(data)
                guard !Task.isCancelled else { return }
                let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    self.model.showToast("未在图片中识别到清晰文字", symbol: "exclamationmark.circle")
                    return
                }
                try? storeRef.updateImageOCRText(id: item.id, ocrText: trimmed)
                self.model.reload()
                self.model.translatedText = trimmed
                self.model.translatedForItemID = item.id
                self.pasteService.copyOnly(trimmed)
                self.model.showToast("已识别并复制图中文字", symbol: "text.viewfinder")
            } catch {
                guard !Task.isCancelled else { return }
                self.model.showToast("OCR 识别失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func exportImage(_ item: ClipItem) {
        guard item.contentType == .image, let data = item.imageData else { return }
        let savePanel = NSSavePanel()
        savePanel.title = "导出剪贴板图片"
        savePanel.nameFieldStringValue = "剪贴板图片-\(item.id).png"
        savePanel.canCreateDirectories = true
        isSequentialPasting = true
        let response = savePanel.runModal()
        isSequentialPasting = false
        if response == .OK, let url = savePanel.url {
            do {
                try data.write(to: url, options: .atomic)
                model.showToast("已导出图片：\(url.lastPathComponent)", symbol: "square.and.arrow.down.fill")
            } catch {
                model.showToast("导出失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: - Instant Translate & Pluggable Action Execution

    func translateItem(_ item: ClipItem, pasteImmediately: Bool) {
        guard item.contentType == .text else { return }
        actionTask?.cancel()
        model.isRunningAction = true
        model.showToast("正在智能翻译…", symbol: "character.bubble.fill")

        actionTask = Task { @MainActor in
            defer { self.model.isRunningAction = false }
            do {
                let translated = try await SmartService.shared.translate(item.body)
                guard !Task.isCancelled else { return }
                self.model.translatedText = translated
                self.model.translatedForItemID = item.id
                if pasteImmediately {
                    self.pasteRawText(translated, itemID: item.id)
                } else if self.model.selectedID == item.id {
                    self.model.showToast("翻译完成，可按 ⌘T 直接粘贴", symbol: "checkmark.circle.fill")
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.model.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func runClipAction(_ action: ClipActionDescriptor, on item: ClipItem) {
        guard item.contentType != .image else { return }
        actionTask?.cancel()
        model.isRunningAction = true
        actionTask = Task { @MainActor in
            defer { self.model.isRunningAction = false }
            do {
                let output = try await SmartService.shared.executeAction(action, on: item.body)
                guard !Task.isCancelled else { return }
                self.model.translatedText = output
                self.model.translatedForItemID = item.id
                if action.pasteAfterRun {
                    self.pasteRawText(output, itemID: item.id)
                } else {
                    self.copyRawText(output)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.model.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        userDismissed = true
        stopFollowing()
        removeKeyMonitor()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isSequentialPasting else { return }
        if settings.panelMode == .dismissAfterPaste,
           model.page == .list,
           panel.isVisible {
            hide()
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !adjustingFrame else { return }
        if settings.panelMode == .attachedToApp {
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
        } else if panel.isVisible {
            hasCustomUserPosition = true
            lastPositionedScreen = panel.screen
        }
    }

    private func syncWindowSizeForLayout(animated: Bool) {
        let wantsWide = settings.showPreviewPane
        let targetWidth: CGFloat = wantsWide ? max(panel.frame.width, 780) : 520
        panel.minSize = NSSize(width: wantsWide ? 700 : 460, height: 520)
        guard abs(panel.frame.width - targetWidth) > 20 else { return }
        var frame = panel.frame
        let oldWidth = frame.size.width
        frame.size.width = targetWidth
        frame.origin.x += (oldWidth - targetWidth) / 2
        if let screen = panel.screen ?? NSScreen.main {
            frame.origin = PanelPlacement.clampedOrigin(
                frame.origin,
                panel: frame.size,
                screen: screen.visibleFrame
            )
        }
        adjustingFrame = true
        panel.setFrame(frame, display: true, animate: animated)
        adjustingFrame = false
    }

    private func saveItem(
        id: Int64?,
        title: String,
        body: String,
        kind: ItemKind,
        triggerCode: String?,
        smartTag: SmartArchiveTag
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let id {
                let updated = try model.store.updateItem(
                    id: id,
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    body: body,
                    kind: kind,
                    triggerCode: triggerCode,
                    smartTag: smartTag
                )
                model.editingItem = nil
                model.page = .list
                panel.title = PanelPage.list.title
                model.reload()
                if !model.items.contains(where: { $0.id == updated.id }) {
                    model.category = nil
                    model.smartTagFilter = nil
                }
                model.selectedID = updated.id
                model.requestScrollToSelection()
                model.showToast("已保存修改", symbol: "checkmark.circle.fill")
            } else {
                let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedBody.isEmpty else { return }
                let created = try model.store.addSnippet(
                    title: trimmedTitle.isEmpty ? nil : trimmedTitle,
                    body: body,
                    triggerCode: triggerCode,
                    smartTag: smartTag
                )
                model.editingItem = nil
                model.page = .list
                panel.title = PanelPage.list.title
                model.reload()
                if !model.items.contains(where: { $0.id == created.id }) {
                    model.category = nil
                    model.smartTagFilter = nil
                    model.query = ""
                }
                model.selectedID = created.id
                model.requestScrollToSelection()
                model.showToast("已添加快捷回复", symbol: "text.bubble.fill")
            }
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
            if settings.panelMode == .attachedToApp {
                followAttachedWindow()
            } else {
                panel.orderFrontRegardless()
            }
            return
        }
        show(page: model.page, makeKey: makeKey)
    }

    private func applyAppearance() {
        panel.alphaValue = CGFloat(settings.panelOpacity)
        panel.isOpaque = false
        panel.backgroundColor = .clear
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
            panel.isFloatingPanel = false
            panel.level = .normal
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        }
    }

    private func positionOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        let screen = activeScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = panel.frame.size

        let desiredOrigin: NSPoint
        if hasCustomUserPosition, lastPositionedScreen == activeScreen {
            desiredOrigin = PanelPlacement.clampedOrigin(panel.frame.origin, panel: size, screen: screen)
        } else {
            let centered = NSPoint(
                x: screen.midX - size.width / 2,
                y: screen.midY - size.height / 2 + 28
            )
            desiredOrigin = PanelPlacement.clampedOrigin(centered, panel: size, screen: screen)
            lastPositionedScreen = activeScreen
        }
        adjustingFrame = true
        panel.setFrameOrigin(desiredOrigin)
        adjustingFrame = false
    }

    private func startFollowing() {
        followTimer?.invalidate()
        followAttachedWindow()
        let timer = Timer(timeInterval: 0.30, repeats: true) { [weak self] _ in
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
        // Do not intercept keys while the user is actively composing Chinese/IME marked text.
        if let textView = panel.firstResponder as? NSTextView, textView.hasMarkedText() {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Esc: Two-stage dismissal (clear search/filters first if active, else navigate back or hide)
        if event.keyCode == 53 {
            if model.page != .list {
                model.editingItem = nil
                model.page = .list
                panel.title = PanelPage.list.title
            } else if !model.query.isEmpty || model.category != nil || model.smartTagFilter != nil {
                model.query = ""
                model.category = nil
                model.smartTagFilter = nil
            } else {
                hide()
            }
            return nil
        }

        // Global panel shortcuts
        if flags == .command {
            switch event.keyCode {
            case 13: // ⌘W Close Panel
                hide()
                return nil
            case 43: // ⌘, Settings
                model.page = (model.page == .settings) ? .list : .settings
                return nil
            case 45: // ⌘N New Snippet
                model.openNewSnippet()
                return nil
            case 16 where model.page == .list: // ⌘Y Toggle Preview Pane
                settingsModel.showPreviewPane.toggle()
                return nil
            case 17 where model.page == .list: // ⌘T Translate & Paste
                if let item = model.selectedItem {
                    if model.translatedForItemID == item.id, let translated = model.translatedText {
                        pasteRawText(translated, itemID: item.id)
                    } else {
                        translateItem(item, pasteImmediately: true)
                    }
                    return nil
                }
            case 15 where model.page == .list: // ⌘R Paste Recommended Reply
                if settings.enableSmartReply, let recommended = model.recommendedReply {
                    paste(recommended)
                    return nil
                }
            default:
                break
            }
        }

        guard model.page == .list else { return event }

        // Tab / Shift+Tab cycles categories
        if event.keyCode == 48 {
            if flags.contains(.shift) {
                model.cycleCategory(-1)
            } else {
                model.cycleCategory(1)
            }
            return nil
        }

        // ⌘1–9 pastes the Nth visible item directly (⌥⌘1–9 copies only).
        if flags.contains(.command), let index = Self.digitIndex(for: event.keyCode) {
            if index < model.items.count {
                if flags.contains(.option) {
                    copyOnly(model.items[index])
                } else {
                    paste(model.items[index])
                }
                return nil
            }
        }

        // ⌘C copies the selected item (unless the user explicitly selected text inside the read-only preview pane)
        if flags == .command, event.keyCode == 8 {
            if let textView = panel.firstResponder as? NSTextView,
               !textView.isEditable,
               textView.selectedRange().length > 0 {
                return event
            }
            if let item = model.selectedItem {
                copyOnly(item)
                return nil
            }
        }

        // ⌘E edits the selected item
        if flags == .command, event.keyCode == 14 {
            if let item = model.selectedItem {
                model.openEdit(item)
                return nil
            }
        }

        switch event.keyCode {
        case 36, 76: // Return / Enter
            if let item = model.selectedItem {
                if flags.contains(.option) {
                    copyOnly(item)
                } else if flags.contains(.shift) {
                    pasteAndAdvance(item)
                } else {
                    paste(item)
                }
                return nil
            }
        case 125: // Down arrow
            model.moveSelection(1)
            return nil
        case 126: // Up arrow
            model.moveSelection(-1)
            return nil
        case 51 where flags.contains(.option): // ⌥⌫ Delete
            if let item = model.selectedItem {
                model.delete(item)
                return nil
            }
        case 35 where flags.contains(.option): // ⌥P Pin
            if let item = model.selectedItem {
                model.togglePin(item)
                return nil
            }
        case 1 where flags.contains(.option): // ⌥S Convert to Snippet
            if let item = model.selectedItem {
                model.convertToSnippet(item)
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
