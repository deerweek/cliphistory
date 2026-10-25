import AppKit
import ImageIO
import SwiftUI

/// High-performance in-memory thumbnail & image cache so scrolling through
/// image history never decodes multi-megabyte PNGs on the main thread.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let thumbCache = NSCache<NSNumber, NSImage>()
    private let previewCache = NSCache<NSNumber, NSImage>()

    private init() {
        thumbCache.countLimit = 150
        previewCache.countLimit = 30
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
        case .compact: return 0.80
        case .comfortable: return 1.0
        case .spacious: return 1.22
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

    var selectedFill: Color { accent.opacity(0.16) }
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
    enum Radius {
        static let window: CGFloat = 14
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
    static var hairline: Color { Color(nsColor: .separatorColor).opacity(0.55) }
    /// Fill for inset controls such as the search field.
    static var controlFill: Color { Color(nsColor: .textBackgroundColor).opacity(0.65) }
    /// Subtle surface for preview cards and code blocks.
    static var cardSurface: Color { Color.primary.opacity(0.045) }
    /// Row background on hover.
    static var rowHover: Color { Color.primary.opacity(0.055) }
    /// Row background when selected.
    static var rowSelected: Color { Color.accentColor.opacity(0.16) }
    /// Subtle tint used behind kind glyphs.
    static func glyphTint(_ base: Color) -> Color { base.opacity(0.15) }
}

// MARK: - Reusable components

/// A rounded, tinted icon tile — gives list rows a crisp, premium anchor.
struct KindGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                    .fill(Theme.glyphTint(tint))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                    .stroke(tint.opacity(0.20), lineWidth: 0.75)
            )
    }
}

/// Live color swatch tile when a copied string is a valid Hex color (`#3B82F6`).
struct ColorSwatchTile: View {
    let r: Double
    let g: Double
    let b: Double
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
            .fill(Color(red: r, green: g, blue: b))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                    .stroke(Color.primary.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color(red: r, green: g, blue: b).opacity(0.35), radius: 3, y: 1)
    }
}

/// Small capsule tag (e.g. "回复", "置顶", "代码").
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
                    .font(.system(size: 8.5, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(filled ? resolvedTint : .secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(filled ? resolvedTint.opacity(0.15) : Color.primary.opacity(0.06))
        )
    }
}

/// A single keyboard-shortcut hint, e.g. ↑↓ 选择.
struct ShortcutHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Borderless icon button with a soft hover highlight.
struct IconButton: View {
    let symbol: String
    var help: String = ""
    var role: ButtonRole? = nil
    var isActive: Bool = false
    var activeTint: Color = .accentColor
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foregroundColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(backgroundColor)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
        if isActive {
            return activeTint.opacity(0.15)
        }
        return hovering ? Color.primary.opacity(0.08) : .clear
    }
}

/// Floating feedback toast shown when copying, pinning, or saving items.
struct ToastCapsule: View {
    let symbol: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
        )
    }
}
