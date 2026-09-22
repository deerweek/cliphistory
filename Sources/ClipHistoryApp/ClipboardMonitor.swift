import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    var onChange: (() -> Void)?

    private let store: Store
    private let settings: AppSettings
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    private static let ignoredTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "com.agilebits.onepassword",
        "com.typeit4me.clipping",
        "de.petermaurer.TransientPasteboardType",
        "Pasteboard generator type",
        "net.antelle.keeweb"
    ]

    init(store: Store, settings: AppSettings) {
        self.store = store
        self.settings = settings
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        captureCurrent()
    }

    func writeWithoutRecording(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        captureCurrent()
    }

    private func captureCurrent() {
        lastChangeCount = pasteboard.changeCount
        guard !containsIgnoredType() else { return }
        guard let raw = pasteboard.string(forType: .string) else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let clipped = String(text.prefix(200_000))
        do {
            try store.recordHistory(clipped)
            try store.cleanup(
                maxHistory: settings.cleanupMaxHistory,
                maxAgeDays: settings.cleanupMaxAgeDays
            )
            onChange?()
        } catch {
            NSLog("剪贴板记录存储失败：\(error)")
        }
    }

    private func containsIgnoredType() -> Bool {
        guard let types = pasteboard.types else { return false }
        return types.contains { Self.ignoredTypes.contains($0.rawValue) }
    }
}
