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

public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private let defaults: UserDefaults
    private let lock = NSLock()

    public static let defaultMaxHistoryCount = 200

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
    }
}
