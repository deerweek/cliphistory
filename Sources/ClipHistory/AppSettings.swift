import Foundation

public enum PanelMode: String, CaseIterable, Sendable {
    case dismissAfterPaste
    case alwaysOnTop
    case attachedToApp

    public var title: String {
        switch self {
        case .dismissAfterPaste: return "粘贴后关闭"
        case .alwaysOnTop: return "始终置顶"
        case .attachedToApp: return "吸附到应用"
        }
    }

    public var detail: String {
        switch self {
        case .dismissAfterPaste:
            return "选中一条并贴上之后，面板自动收起。"
        case .alwaysOnTop:
            return "面板留在所有窗口最上层，粘贴后也不关闭。适合边看聊天边点回复。"
        case .attachedToApp:
            return "贴在所选应用窗口旁边，并跟着那个窗口移动。粘贴会进到这个应用。"
        }
    }
}

public enum HotkeyCombo: String, CaseIterable, Sendable {
    case commandD
    case shiftCommandD
    case shiftCommandV

    public var menuLabel: String {
        switch self {
        case .commandD: return "⌘D"
        case .shiftCommandD: return "⇧⌘D"
        case .shiftCommandV: return "⇧⌘V"
        }
    }
}

/// Accent used by the panel's visual theme.
///
/// The value is stored as a string in `UserDefaults` so adding a new accent
/// remains backwards compatible with existing installations.
public enum PanelAccent: String, CaseIterable, Sendable {
    case system
    case blue
    case purple
    case green
    case orange
    case pink

    public var title: String {
        switch self {
        case .system: return "系统"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .green: return "绿色"
        case .orange: return "橙色"
        case .pink: return "粉色"
        }
    }
}

/// Controls how much content is shown in each history row.
public enum PanelDensity: String, CaseIterable, Sendable {
    case compact
    case comfortable
    case spacious

    public var title: String {
        switch self {
        case .compact: return "紧凑"
        case .comfortable: return "舒适"
        case .spacious: return "宽松"
        }
    }
}

public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private let defaults: UserDefaults
    private let lock = NSLock()

    public static let defaultMaxHistoryCount = 200
    public static let defaultPanelOpacity = 0.92

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hotkey: HotkeyCombo {
        get {
            lock.lock()
            defer { lock.unlock() }
            let raw = defaults.string(forKey: Keys.hotkey) ?? HotkeyCombo.commandD.rawValue
            return HotkeyCombo(rawValue: raw) ?? .commandD
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue.rawValue, forKey: Keys.hotkey)
        }
    }

    public var maxHistoryCount: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            if defaults.object(forKey: Keys.maxHistoryCount) == nil {
                return Self.defaultMaxHistoryCount
            }
            return max(1, defaults.integer(forKey: Keys.maxHistoryCount))
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(max(1, newValue), forKey: Keys.maxHistoryCount)
        }
    }

    /// 0 means age-based cleanup is off.
    public var maxAgeDays: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return max(0, defaults.integer(forKey: Keys.maxAgeDays))
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(max(0, newValue), forKey: Keys.maxAgeDays)
        }
    }

    public var panelMode: PanelMode {
        get {
            lock.lock()
            defer { lock.unlock() }
            let raw = defaults.string(forKey: Keys.panelMode) ?? PanelMode.dismissAfterPaste.rawValue
            return PanelMode(rawValue: raw) ?? .dismissAfterPaste
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue.rawValue, forKey: Keys.panelMode)
        }
    }

    public var attachedBundleID: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.string(forKey: Keys.attachedBundleID) ?? ""
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.attachedBundleID)
        }
    }

    public var panelAccent: PanelAccent {
        get {
            lock.lock()
            defer { lock.unlock() }
            let raw = defaults.string(forKey: Keys.panelAccent) ?? PanelAccent.system.rawValue
            return PanelAccent(rawValue: raw) ?? .system
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue.rawValue, forKey: Keys.panelAccent)
        }
    }

    public var panelDensity: PanelDensity {
        get {
            lock.lock()
            defer { lock.unlock() }
            let raw = defaults.string(forKey: Keys.panelDensity) ?? PanelDensity.comfortable.rawValue
            return PanelDensity(rawValue: raw) ?? .comfortable
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue.rawValue, forKey: Keys.panelDensity)
        }
    }

    /// Panel opacity in the inclusive range 0.55...1.0.
    ///
    /// Older versions did not persist this value, so a missing or invalid
    /// value falls back to the current default. Clamping on both read and
    /// write keeps preferences safe even if they are edited externally.
    public var panelOpacity: Double {
        get {
            lock.lock()
            defer { lock.unlock() }
            guard let value = defaults.object(forKey: Keys.panelOpacity) as? NSNumber else {
                return Self.defaultPanelOpacity
            }
            return Self.clampPanelOpacity(value.doubleValue)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(Self.clampPanelOpacity(newValue), forKey: Keys.panelOpacity)
        }
    }

    public var launchAtLogin: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            if defaults.object(forKey: Keys.launchAtLogin) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.launchAtLogin)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.launchAtLogin)
        }
    }

    public var cleanupMaxHistory: Int { maxHistoryCount }

    public var cleanupMaxAgeDays: Int? {
        let days = maxAgeDays
        return days > 0 ? days : nil
    }

    private enum Keys {
        static let hotkey = "hotkey"
        static let maxHistoryCount = "maxHistoryCount"
        static let maxAgeDays = "maxAgeDays"
        static let launchAtLogin = "launchAtLogin"
        static let panelMode = "panelMode"
        static let attachedBundleID = "attachedBundleID"
        static let panelAccent = "panelAccent"
        static let panelDensity = "panelDensity"
        static let panelOpacity = "panelOpacity"
    }

    private static func clampPanelOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultPanelOpacity }
        return min(1.0, max(0.55, value))
    }
}
