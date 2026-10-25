import ApplicationServices
import AppKit
import Foundation

/// IME-linked global typing expander.
/// Watches keystrokes in the background when enabled; when the user types a snippet's
/// `triggerCode` (e.g. `;dz`, `;fp`, `//mail`) in any app, it automatically erases
/// the trigger characters and pastes the expanded snippet (including `{{date}}` variables).
@MainActor
final class TextExpanderService {
    var onExpanded: ((ClipItem) -> Void)?

    private let store: Store
    private let settings: AppSettings
    private let pasteService: PasteService
    private var globalMonitor: Any?
    private var buffer = ""
    private var lastKeystrokeAt = Date.distantPast
    private var isExpanding = false

    init(store: Store, settings: AppSettings, pasteService: PasteService) {
        self.store = store
        self.settings = settings
        self.pasteService = pasteService
    }

    func start() {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleGlobalKeyDown(event)
            }
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        buffer = ""
    }

    private func handleGlobalKeyDown(_ event: NSEvent) {
        guard settings.enableTextExpander, !isExpanding else { return }
        guard PasteService.isTrusted(prompt: false) else { return }

        // Ignore when our own app is active
        if let front = NSWorkspace.shared.frontmostApplication,
           FrontAppTracker.isSelf(front) {
            buffer = ""
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Reset buffer on Command/Control/Option shortcuts
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            buffer = ""
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastKeystrokeAt) > 4.0 {
            buffer = ""
        }
        lastKeystrokeAt = now

        // Handle Backspace
        if event.keyCode == 51 {
            if !buffer.isEmpty {
                buffer.removeLast()
            }
            return
        }

        // Reset on Return, Tab, Escape, Space, or Arrow keys
        if [36, 76, 48, 53, 123, 124, 125, 126].contains(event.keyCode) {
            buffer = ""
            return
        }

        guard let chars = event.characters, !chars.isEmpty else { return }
        buffer.append(chars)
        if buffer.count > 24 {
            buffer = String(buffer.suffix(24))
        }

        checkTriggerMatch()
    }

    private func checkTriggerMatch() {
        guard buffer.count >= 2 else { return }
        guard let snippets = try? store.snippets(), !snippets.isEmpty else { return }

        let lowerBuffer = buffer.lowercased()
        let candidates = snippets.compactMap { item -> (ClipItem, String)? in
            guard let raw = item.triggerCode?.trimmingCharacters(in: .whitespacesAndNewlines),
                  raw.count >= 2 else { return nil }
            return (item, raw)
        }.sorted { $0.1.count > $1.1.count }

        guard let (matched, trigger) = candidates.first(where: { lowerBuffer.hasSuffix($0.1.lowercased()) }) else {
            return
        }

        buffer = ""
        expand(snippet: matched, triggerLength: trigger.count)
    }

    private func expand(snippet: ClipItem, triggerLength: Int) {
        guard let targetApp = NSWorkspace.shared.frontmostApplication,
              !FrontAppTracker.isSelf(targetApp) else { return }

        isExpanding = true
        let pid = targetApp.processIdentifier

        // 1. Delete the typed trigger code characters
        Self.postBackspaces(count: triggerLength, to: pid)

        // 2. Expand dynamic template placeholders ({{date}}, {{time}}, {{clipboard}})
        let previousClip = NSPasteboard.general.string(forType: .string)
        let expandedText = ClipActionEngine.expandTemplateVariables(
            in: snippet.body,
            currentClipboard: previousClip
        )

        // 3. Deliver the expanded text via PasteService after a brief 35ms settle for backspaces
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
            guard let self else { return }
            self.pasteService.paste(expandedText, preferredApp: targetApp)
            try? self.store.recordUse(id: snippet.id)
            self.onExpanded?(snippet)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.isExpanding = false
            }
        }
    }

    private static func postBackspaces(count: Int, to pid: pid_t) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState) ?? CGEventSource(stateID: .hidSystemState)
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x33), keyDown: true)
            down?.flags = []
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x33), keyDown: false)
            up?.flags = []
            if isFrontmost {
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
            } else {
                down?.postToPid(pid)
                up?.postToPid(pid)
            }
        }
    }
}
