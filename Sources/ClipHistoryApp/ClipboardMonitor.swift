import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    var onChange: (() -> Void)?
    var onItemRecorded: ((ClipItem) -> Void)?

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

    private static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "heic", "bmp"
    ]

    init(store: Store, settings: AppSettings) {
        self.store = store
        self.settings = settings
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        captureCurrent(isInitialStartup: true)
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
        captureCurrent(isInitialStartup: false)
    }

    private func currentSourceApp() -> (name: String?, bundleID: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              !FrontAppTracker.isSelf(app) else {
            return (nil, nil)
        }
        return (app.localizedName, app.bundleIdentifier)
    }

    private func captureCurrent(isInitialStartup: Bool) {
        lastChangeCount = pasteboard.changeCount
        guard !settings.isRecordingPaused else { return }
        guard !containsIgnoredType() else { return }

        let (sourceName, sourceBundleID) = isInitialStartup ? (nil, nil) : currentSourceApp()
        if let sourceBundleID, settings.excludedBundleIDs.contains(sourceBundleID) {
            return
        }
        let sourceApp = sourceName

        // 1. If the user copied an image file in Finder, record the actual image
        if let fileImage = imageFromCopiedFileURL() {
            recordImage(fileImage, sourceApp: sourceApp, isInitialStartup: isInitialStartup)
            return
        }

        // 2. Prefer meaningful text while preserving leading indentation
        if let raw = pasteboard.string(forType: .string),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let preserved = Self.preserveIndentationTrimmingNewlines(raw)
            let clipped = String(preserved.prefix(200_000))
            if isInitialStartup, (try? store.hasHistoryItem(body: clipped)) == true {
                return
            }
            recordText(clipped, sourceApp: sourceApp, notifySmartEngine: !isInitialStartup)
        } else if let image = imageFromPasteboard() {
            recordImage(image, sourceApp: sourceApp, isInitialStartup: isInitialStartup)
        }
    }

    static func preserveIndentationTrimmingNewlines(_ raw: String) -> String {
        var result = raw[...]
        while let first = result.first, first.isNewline {
            result = result.dropFirst()
        }
        while let last = result.last, last.isNewline {
            result = result.dropLast()
        }
        let output = String(result)
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? raw.trimmingCharacters(in: .whitespacesAndNewlines)
            : output
    }

    private func recordText(_ text: String, sourceApp: String?, notifySmartEngine: Bool) {
        do {
            let item = try store.recordHistory(text, sourceApp: sourceApp)
            try cleanup()
            onChange?()
            if notifySmartEngine {
                onItemRecorded?(item)
            }
        } catch {
            NSLog("剪贴板记录存储失败：\(error)")
        }
    }

    private func recordImage(_ image: NSImage, sourceApp: String?, isInitialStartup: Bool = false) {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else { return }
        guard png.count <= 12_000_000 else { return }
        if isInitialStartup, (try? store.hasImageItem(data: png)) == true {
            return
        }
        do {
            let item = try store.recordImage(png, width: rep.pixelsWide, height: rep.pixelsHigh, sourceApp: sourceApp)
            try cleanup()
            onChange?()
            onItemRecorded?(item)
            // Automatically index OCR text in the background so screenshots are searchable by text
            let itemID = item.id
            let storeRef = store
            Task { [weak self] in
                if let ocrText = try? await SmartService.shared.recognizeTextInImage(png),
                   !ocrText.isEmpty {
                    try? storeRef.updateImageOCRText(id: itemID, ocrText: ocrText)
                    await MainActor.run {
                        self?.onChange?()
                    }
                }
            }
        } catch {
            NSLog("剪贴板图片存储失败：\(error)")
        }
    }

    func runCleanupNow() {
        try? cleanup()
        onChange?()
    }

    private func cleanup() throws {
        try store.cleanup(
            maxHistory: settings.cleanupMaxHistory,
            maxAgeDays: settings.cleanupMaxAgeDays
        )
    }

    private func imageFromCopiedFileURL() -> NSImage? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL],
        urls.count == 1,
        let fileURL = urls.first else {
            return nil
        }
        let ext = fileURL.pathExtension.lowercased()
        guard Self.imageFileExtensions.contains(ext) else { return nil }
        return NSImage(contentsOf: fileURL)
    }

    private func imageFromPasteboard() -> NSImage? {
        let imageTypes: Set<NSPasteboard.PasteboardType> = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg")
        ]
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
