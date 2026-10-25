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
            return "选中一条并贴上之后，或点击面板外部区域时，面板自动收起。"
        case .alwaysOnTop:
            return "面板留在所有窗口最上层，粘贴后也不关闭、不闪烁。适合边看聊天边连续点回复。"
        case .attachedToApp:
            return "贴在所选应用窗口旁边，并跟着那个窗口移动。粘贴会直接送进这个应用。"
        }
    }
}

public enum HotkeyCombo: String, CaseIterable, Sendable {
    case shiftCommandV
    case optionCommandV
    case controlCommandV
    case shiftCommandD
    case commandD
    case optionSpace

    public var menuLabel: String {
        switch self {
        case .shiftCommandV: return "⇧⌘V"
        case .optionCommandV: return "⌥⌘V"
        case .controlCommandV: return "⌃⌘V"
        case .shiftCommandD: return "⇧⌘D"
        case .commandD: return "⌘D"
        case .optionSpace: return "⌥Space"
        }
    }
}

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
    public static let defaultJevEndpoint = "https://openrouter.ai/api/alpha/decisions"
    public static let defaultAIEndpoint = "https://api.deepseek.com/v1/chat/completions"
    public static let defaultAIModel = "deepseek-chat"
    public static let defaultExcludedBundleIDs: [String] = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop"
    ]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isRecordingPaused: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.bool(forKey: Keys.isRecordingPaused)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.isRecordingPaused)
        }
    }

    public var excludedBundleIDs: [String] {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let saved = defaults.stringArray(forKey: Keys.excludedBundleIDs) {
                return saved
            }
            return Self.defaultExcludedBundleIDs
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.excludedBundleIDs)
        }
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

    public var showPreviewPane: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            if defaults.object(forKey: Keys.showPreviewPane) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.showPreviewPane)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.showPreviewPane)
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

    // MARK: - Smart Engine & Jev / IME / Action Settings

    public var enableTextExpander: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            if defaults.object(forKey: Keys.enableTextExpander) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.enableTextExpander)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.enableTextExpander)
        }
    }

    public var enableSmartReply: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            if defaults.object(forKey: Keys.enableSmartReply) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.enableSmartReply)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue, forKey: Keys.enableSmartReply)
        }
    }

    public var jevAPIKey: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.string(forKey: Keys.jevAPIKey) ?? ""
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.jevAPIKey)
        }
    }

    public var jevEndpoint: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            let val = defaults.string(forKey: Keys.jevEndpoint) ?? Self.defaultJevEndpoint
            return val.isEmpty ? Self.defaultJevEndpoint : val
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.jevEndpoint)
        }
    }

    public var aiAPIKey: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return defaults.string(forKey: Keys.aiAPIKey) ?? ""
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.aiAPIKey)
        }
    }

    public var aiEndpoint: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            let val = defaults.string(forKey: Keys.aiEndpoint) ?? Self.defaultAIEndpoint
            return val.isEmpty ? Self.defaultAIEndpoint : val
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.aiEndpoint)
        }
    }

    public var aiModelName: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            let val = defaults.string(forKey: Keys.aiModelName) ?? Self.defaultAIModel
            return val.isEmpty ? Self.defaultAIModel : val
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.aiModelName)
        }
    }

    /// Pluggable actions (built-in + user-created custom AI/Shell actions).
    public var actions: [ClipActionDescriptor] {
        get {
            lock.lock()
            defer { lock.unlock() }
            guard let data = defaults.data(forKey: Keys.actions),
                  let decoded = try? JSONDecoder().decode([ClipActionDescriptor].self, from: data),
                  !decoded.isEmpty else {
                return ClipActionEngine.defaultBuiltInActions
            }
            return decoded
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: Keys.actions)
            }
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
        static let showPreviewPane = "showPreviewPane"
        static let enableTextExpander = "enableTextExpander"
        static let enableSmartReply = "enableSmartReply"
        static let jevAPIKey = "jevAPIKey"
        static let jevEndpoint = "jevEndpoint"
        static let aiAPIKey = "aiAPIKey"
        static let aiEndpoint = "aiEndpoint"
        static let aiModelName = "aiModelName"
        static let actions = "clipActions"
        static let isRecordingPaused = "isRecordingPaused"
        static let excludedBundleIDs = "excludedBundleIDs"
    }

    private static func clampPanelOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultPanelOpacity }
        return min(1.0, max(0.55, value))
    }
}
