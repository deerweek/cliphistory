import SwiftUI

/// Shared visual language for the panel. Keeping tokens in one place makes the
/// UI feel cohesive ("high-end") while staying easy to tune.
enum Theme {
    enum Radius {
        static let window: CGFloat = 12
        static let card: CGFloat = 10
        static let control: CGFloat = 8
        static let glyph: CGFloat = 7
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
    static var hairline: Color { Color(nsColor: .separatorColor).opacity(0.65) }
    /// Fill for inset controls such as the search field.
    static var controlFill: Color { Color(nsColor: .textBackgroundColor).opacity(0.6) }
    /// Row background on hover.
    static var rowHover: Color { Color.primary.opacity(0.06) }
    /// Row background when selected.
    static var rowSelected: Color { Color.accentColor.opacity(0.16) }
    /// Subtle tint used behind kind glyphs.
    static func glyphTint(_ base: Color) -> Color { base.opacity(0.16) }
}

// MARK: - Reusable components

/// A rounded, tinted icon tile — gives list rows a crisp, premium anchor.
struct KindGlyph: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.glyph, style: .continuous)
                    .fill(Theme.glyphTint(tint))
            )
    }
}

/// Small capsule tag (e.g. "回复", "置顶").
struct Badge: View {
    let text: String
    var tint: Color = .accentColor
    var filled: Bool = true

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(filled ? tint : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(filled ? tint.opacity(0.16) : Color.primary.opacity(0.06))
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
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Borderless icon button with a soft hover highlight.
struct IconButton: View {
    let symbol: String
    var help: String = ""
    var role: ButtonRole? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(role == .destructive && hovering ? Color.red : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
