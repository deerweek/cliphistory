import AppKit
import ImageIO
import SwiftUI

/// High-performance in-memory thumbnail, preview & source-app icon cache so scrolling
/// through history never decodes multi-megabyte PNGs or hits disk on the main thread.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let thumbCache = NSCache<NSNumber, NSImage>()
    private let previewCache = NSCache<NSNumber, NSImage>()
    private let appIconCache = NSCache<NSString, NSImage>()
    private var negativeAppLookup = Set<String>()
    private let lock = NSLock()

    private init() {
        thumbCache.countLimit = 180
        previewCache.countLimit = 40
        appIconCache.countLimit = 120
    }

    func thumbnail(for id: Int64, data: Data, maxPixelSize: Int = 120) -> NSImage? {
        let key = NSNumber(value: id)
        if let cached = thumbCache.object(forKey: key) {
            return cached
        }
        guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) ?? NSImage(data: data) else {
            return nil
        }
        thumbCache.setObject(image, forKey: key)
        return image
    }

    func previewImage(for id: Int64, data: Data, maxPixelSize: Int = 960) -> NSImage? {
        let key = NSNumber(value: id)
        if let cached = previewCache.object(forKey: key) {
            return cached
        }
        guard let image = Self.downsample(data: data, maxPixelSize: maxPixelSize) ?? NSImage(data: data) else {
            return nil
        }
        previewCache.setObject(image, forKey: key)
        return image
    }

    /// Resolves a `sourceApp` display name (e.g. "微信", "Safari", "系统截屏") to its authentic macOS app icon.
    func appIcon(forSourceApp sourceApp: String?) -> NSImage? {
        guard let raw = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let cacheKey = raw as NSString
        if let cached = appIconCache.object(forKey: cacheKey) {
            return cached
        }
        lock.lock()
        let isKnownMissing = negativeAppLookup.contains(raw)
        lock.unlock()
        if isKnownMissing {
            return nil
        }

        if let resolved = Self.resolveAppIcon(named: raw) {
            appIconCache.setObject(resolved, forKey: cacheKey)
            return resolved
        } else {
            lock.lock()
            negativeAppLookup.insert(raw)
            lock.unlock()
            return nil
        }
    }

    private static let knownBundleIDsByName: [String: String] = [
        "微信": "com.tencent.xinWeChat",
        "wechat": "com.tencent.xinWeChat",
        "企业微信": "com.tencent.WeWorkMac",
        "qq": "com.tencent.qq",
        "飞书": "com.electron.lark",
        "lark": "com.electron.lark",
        "钉钉": "com.alibaba.DingTalkMac",
        "safari": "com.apple.Safari",
        "safari浏览器": "com.apple.Safari",
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "arc": "company.thebrowser.Browser",
        "firefox": "org.mozilla.firefox",
        "microsoft edge": "com.microsoft.edgemac",
        "brave": "com.brave.Browser",
        "终端": "com.apple.Terminal",
        "terminal": "com.apple.Terminal",
        "iterm2": "com.googlecode.iterm2",
        "iterm": "com.googlecode.iterm2",
        "warp": "dev.warp.Warp-Stable",
        "访达": "com.apple.finder",
        "finder": "com.apple.finder",
        "备忘录": "com.apple.Notes",
        "notes": "com.apple.Notes",
        "信息": "com.apple.MobileSMS",
        "messages": "com.apple.MobileSMS",
        "邮件": "com.apple.mail",
        "mail": "com.apple.mail",
        "预览": "com.apple.Preview",
        "preview": "com.apple.Preview",
        "系统截屏": "com.apple.screencaptureui",
        "截屏": "com.apple.screencaptureui",
        "xcode": "com.apple.dt.Xcode",
        "code": "com.microsoft.VSCode",
        "visual studio code": "com.microsoft.VSCode",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "telegram": "ru.keepcoder.Telegram",
        "whatsapp": "net.whatsapp.WhatsApp",
        "x": "com.atebits.Tweetie2"
    ]

    private static func resolveAppIcon(named name: String) -> NSImage? {
        let workspace = NSWorkspace.shared
        let lowered = name.lowercased()

        // 1. Check currently running applications first
        if let running = workspace.runningApplications.first(where: {
            $0.localizedName?.lowercased() == lowered || $0.bundleIdentifier?.lowercased() == lowered
        }), let icon = running.icon {
            return icon
        }

        // 2. Check known bundle ID mapping
        if let bundleID = knownBundleIDsByName[lowered],
           let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            return workspace.icon(forFile: url.path)
        }

        // 3. Check if `name` itself is a bundle ID
        if name.contains("."),
           let url = workspace.urlForApplication(withBundleIdentifier: name) {
            return workspace.icon(forFile: url.path)
        }

        // 4. Check standard macOS application directories
        let candidatePaths = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app",
            "/System/Library/CoreServices/\(name).app"
        ]
        for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
            return workspace.icon(forFile: path)
        }

        return nil
    }

    private static func downsample(data: Data, maxPixelSize: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: - User appearance

/// User-adjustable appearance values passed through the SwiftUI environment.
struct PanelThemeContext {
    let accent: Color
    let density: PanelDensity
    let opacity: Double

    static var `default`: PanelThemeContext {
        PanelThemeContext(accent: .accentColor, density: .comfortable, opacity: 0.92)
    }

    var spacingScale: CGFloat {
        switch density {
        case .compact: return 0.82
        case .comfortable: return 1.0
        case .spacious: return 1.20
        }
    }

    func spacing(_ base: CGFloat) -> CGFloat {
        (base * spacingScale).rounded()
    }

    var rowVerticalPadding: CGFloat {
        switch density {
        case .compact: return 6
        case .comfortable: return 9
        case .spacious: return 12
        }
    }

    var rowBodyLineLimit: Int {
        switch density {
        case .compact: return 1
        case .comfortable: return 2
        case .spacious: return 3
        }
    }

    var selectedFill: Color { accent.opacity(0.15) }

    var selectedGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.20), accent.opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct PanelThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = PanelThemeContext.default
}

extension EnvironmentValues {
    var clipHistoryTheme: PanelThemeContext {
        get { self[PanelThemeEnvironmentKey.self] }
        set { self[PanelThemeEnvironmentKey.self] = newValue }
    }
}

extension PanelAccent {
    var color: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        }
    }
}

enum Theme {
    /// Concentric corner radius hierarchy aligned with Apple macOS Sequoia guidelines.
    enum Radius {
        static let window: CGFloat = 16
        static let container: CGFloat = 12
        static let card: CGFloat = 10
        static let control: CGFloat = 9
        static let glyph: CGFloat = 8
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    /// Hairline separators, softer than a full-strength divider.
    static var hairline: Color { Color(nsColor: .separatorColor).opacity(0.42) }
    /// Specular top-edge highlight gradient for glassmorphic cards & search bar.
    static var specularStroke: LinearGradient {
        LinearGradient(
            colors: [Color.primary.opacity(0.14), Color.primary.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    /// Fill for inset controls such as the Spotlight command bar.
    static var controlFill: Color { Color(nsColor: .textBackgroundColor).opacity(0.62) }
    /// Subtle surface for preview cards and code blocks.
    static var cardSurface: Color { Color.primary.opacity(0.042) }
    /// Elevated surface for grouped cards in Settings / Action Studio.
    static var elevatedCardSurface: Color { Color(nsColor: .controlBackgroundColor).opacity(0.58) }
    /// Row background on hover.
    static var rowHover: Color { Color.primary.opacity(0.052) }
    /// Row background when selected.
    static var rowSelected: Color { Color.accentColor.opacity(0.15) }
    /// Subtle tint used behind kind glyphs.
    static func glyphTint(_ base: Color) -> Color { base.opacity(0.15) }
}

// MARK: - Reusable Apple-Grade Components

/// A rounded, softly-lit icon tile with an optional bottom-right macOS source app icon badge.
struct KindGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 34
    var sourceApp: String? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.18), tint.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [tint.opacity(0.32), tint.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )

            if let appIcon = ThumbnailCache.shared.appIcon(forSourceApp: sourceApp) {
                SourceAppCornerBadge(icon: appIcon)
                    .offset(x: 3, y: 3)
            }
        }
    }
}

/// Crisp 15×15 real macOS application icon badge overlaid on the bottom-right corner of row artwork.
struct SourceAppCornerBadge: View {
    let icon: NSImage
    var size: CGFloat = 15

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: size + 2, height: size + 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
    }
}

/// Apple System Settings style rounded-square gradient icon tile for section headers.
struct SettingsSectionIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.54, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: tint.opacity(0.25), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
    }
}

/// Live color swatch tile when a copied string is a valid Hex color (`#3B82F6`).
struct ColorSwatchTile: View {
    let r: Double
    let g: Double
    let b: Double
    var size: CGFloat = 34
    var sourceApp: String? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                .fill(Color(red: r, green: g, blue: b))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Color(red: r, green: g, blue: b).opacity(0.32), radius: 4, y: 1.5)

            if let appIcon = ThumbnailCache.shared.appIcon(forSourceApp: sourceApp) {
                SourceAppCornerBadge(icon: appIcon)
                    .offset(x: 3, y: 3)
            }
        }
    }
}

/// Small capsule tag (e.g. "回复", "置顶", "代码") with restrained Apple native styling.
struct Badge: View {
    @Environment(\.clipHistoryTheme) private var theme

    let text: String
    var symbol: String? = nil
    var tint: Color? = nil
    var filled: Bool = true

    var body: some View {
        let resolvedTint = tint ?? theme.accent
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 9.5, weight: filled ? .semibold : .medium))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(filled ? resolvedTint : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(filled ? resolvedTint.opacity(0.13) : Color.primary.opacity(0.048))
        )
        .overlay(
            Capsule()
                .strokeBorder(filled ? resolvedTint.opacity(0.24) : Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

/// Tactile Apple-style keyboard keycap hint, e.g. ↑↓ 选择.
struct ShortcutHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .shadow(color: .black.opacity(0.06), radius: 0.5, y: 0.75)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Borderless icon button with a soft glassmorphic hover highlight.
struct IconButton: View {
    let symbol: String
    var help: String = ""
    var role: ButtonRole? = nil
    var isActive: Bool = false
    var activeTint: Color = .accentColor
    var size: CGFloat = 26
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.47, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.easeOut(duration: 0.12)) {
                hovering = hover
            }
        }
        .help(help)
    }

    private var foregroundColor: Color {
        if role == .destructive && hovering {
            return .red
        }
        if isActive {
            return activeTint
        }
        return hovering ? .primary : .secondary
    }

    private var backgroundColor: Color {
        if role == .destructive && hovering {
            return Color.red.opacity(0.12)
        }
        if isActive {
            return activeTint.opacity(0.14)
        }
        return hovering ? Color.primary.opacity(0.075) : .clear
    }

    private var borderColor: Color {
        if isActive {
            return activeTint.opacity(0.28)
        }
        return hovering ? Color.primary.opacity(0.10) : .clear
    }
}

/// Floating feedback toast shown when copying, pinning, or saving items.
struct ToastCapsule: View {
    let symbol: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7.5)
        .background(
            Capsule()
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.20), radius: 12, y: 5)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.primary.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
    }
}
