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

    func writeImageWithoutRecording(_ data: Data) {
        pasteboard.clearContents()
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        } else {
            pasteboard.setData(data, forType: .png)
        }
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

        // Prefer meaningful text; fall back to an image (e.g. screenshots, or
        // images copied from a browser, which carry no usable string).
        if let raw = pasteboard.string(forType: .string),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            recordText(String(text.prefix(200_000)))
        } else if let image = imageFromPasteboard() {
            recordImage(image)
        }
    }

    private func recordText(_ text: String) {
        do {
            try store.recordHistory(text)
            try cleanup()
            onChange?()
        } catch {
            NSLog("剪贴板记录存储失败：\(error)")
        }
    }

    private func recordImage(_ image: NSImage) {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return }
        // Skip very large images to keep the local DB lean.
        guard png.count <= 12_000_000 else { return }
        do {
            try store.recordImage(png, width: rep.pixelsWide, height: rep.pixelsHigh)
            try cleanup()
            onChange?()
        } catch {
            NSLog("剪贴板图片存储失败：\(error)")
        }
    }

    private func cleanup() throws {
        try store.cleanup(
            maxHistory: settings.cleanupMaxHistory,
            maxAgeDays: settings.cleanupMaxAgeDays
        )
    }

    private func imageFromPasteboard() -> NSImage? {
        let imageTypes: Set<NSPasteboard.PasteboardType> = [.png, .tiff]
        guard let types = pasteboard.types, types.contains(where: { imageTypes.contains($0) }) else {
            return nil
        }
        if let objects = pasteboard.readObjects(forClasses: [NSImage.self], options: nil),
           let image = objects.first as? NSImage {
            return image
        }
        return nil
    }

    private func containsIgnoredType() -> Bool {
        guard let types = pasteboard.types else { return false }
        return types.contains { Self.ignoredTypes.contains($0.rawValue) }
    }
}
