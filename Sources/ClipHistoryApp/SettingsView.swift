import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var hotkey: HotkeyCombo {
        didSet { persistHotkey() }
    }
    @Published var maxHistoryCount: Int {
        didSet {
            guard isReady else { return }
            settings.maxHistoryCount = maxHistoryCount
            onCleanupRulesChange?()
        }
    }
    @Published var maxAgeDays: Int {
        didSet {
            guard isReady else { return }
            settings.maxAgeDays = maxAgeDays
            onCleanupRulesChange?()
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { persistLaunchAtLogin() }
    }
    @Published var panelMode: PanelMode {
        didSet { persistPanelMode() }
    }
    @Published var attachedBundleID: String {
        didSet { persistAttachedApp() }
    }
    @Published var panelAccent: PanelAccent {
        didSet { persistPanelAccent() }
    }
    @Published var panelDensity: PanelDensity {
        didSet { persistPanelDensity() }
    }
    @Published var panelOpacity: Double {
        didSet { persistPanelOpacity() }
    }
    @Published var showPreviewPane: Bool {
        didSet { persistShowPreviewPane() }
    }

    // Smart Engine, Jev Model, IME Expander & Custom Actions
    @Published var enableTextExpander: Bool {
        didSet {
            guard isReady else { return }
            settings.enableTextExpander = enableTextExpander
        }
    }
    @Published var enableSmartReply: Bool {
        didSet {
            guard isReady else { return }
            settings.enableSmartReply = enableSmartReply
        }
    }
    @Published var jevAPIKey: String {
        didSet {
            guard isReady else { return }
            settings.jevAPIKey = jevAPIKey
        }
    }
    @Published var jevEndpoint: String {
        didSet {
            guard isReady else { return }
            settings.jevEndpoint = jevEndpoint
        }
    }
    @Published var aiAPIKey: String {
        didSet {
            guard isReady else { return }
            settings.aiAPIKey = aiAPIKey
        }
    }
    @Published var aiEndpoint: String {
        didSet {
            guard isReady else { return }
            settings.aiEndpoint = aiEndpoint
        }
    }
    @Published var aiModelName: String {
        didSet {
            guard isReady else { return }
            settings.aiModelName = aiModelName
        }
    }
    @Published var actions: [ClipActionDescriptor] {
        didSet {
            guard isReady else { return }
            settings.actions = actions
        }
    }
    @Published var isRecordingPaused: Bool {
        didSet {
            guard isReady else { return }
            settings.isRecordingPaused = isRecordingPaused
            onPauseStateChange?(isRecordingPaused)
        }
    }
    @Published var excludedBundleIDs: [String] {
        didSet {
            guard isReady else { return }
            settings.excludedBundleIDs = excludedBundleIDs
        }
    }

    @Published var appChoices: [KnownApp] = []
    @Published var accessibilityTrusted = false
    @Published var accessibilityMessage = ""
    @Published var launchMessage: String?

    private let settings: AppSettings
    private var isReady = false
    var onHotkeyChange: ((HotkeyCombo) -> Void)?
    var onDisplayChange: (() -> Void)?
    var onCleanupRulesChange: (() -> Void)?
    var onPauseStateChange: ((Bool) -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        hotkey = settings.hotkey
        maxHistoryCount = settings.maxHistoryCount
        maxAgeDays = settings.maxAgeDays
        launchAtLogin = settings.launchAtLogin
        panelMode = settings.panelMode
        attachedBundleID = settings.attachedBundleID
        panelAccent = settings.panelAccent
        panelDensity = settings.panelDensity
        panelOpacity = settings.panelOpacity
        showPreviewPane = settings.showPreviewPane
        enableTextExpander = settings.enableTextExpander
        enableSmartReply = settings.enableSmartReply
        jevAPIKey = settings.jevAPIKey
        jevEndpoint = settings.jevEndpoint
        aiAPIKey = settings.aiAPIKey
        aiEndpoint = settings.aiEndpoint
        aiModelName = settings.aiModelName
        actions = settings.actions
        isRecordingPaused = settings.isRecordingPaused
        excludedBundleIDs = settings.excludedBundleIDs
        refreshAccess()
        appChoices = KnownApps.choices(including: attachedBundleID)
        isReady = true
    }

    func refreshAccess() {
        let status = PasteService.AccessibilityStatus.current
        accessibilityTrusted = status.trusted
        accessibilityMessage = status.message
    }

    func refreshApps() {
        appChoices = KnownApps.choices(including: attachedBundleID)
    }

    var enabledActions: [ClipActionDescriptor] {
        actions.filter(\.isEnabled)
    }

    func addCustomAction(
        title: String,
        symbolName: String,
        kind: ClipActionKind,
        payload: String,
        pasteAfterRun: Bool
    ) {
        let item = ClipActionDescriptor(
            id: "custom_\(UUID().uuidString.prefix(8))",
            title: title,
            symbolName: symbolName,
            kind: kind,
            payload: payload,
            isEnabled: true,
            pasteAfterRun: pasteAfterRun
        )
        actions.append(item)
    }

    func updateCustomAction(
        id: String,
        title: String,
        symbolName: String,
        kind: ClipActionKind,
        payload: String,
        pasteAfterRun: Bool
    ) {
        guard let idx = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[idx].title = title
        actions[idx].symbolName = symbolName
        actions[idx].kind = kind
        actions[idx].payload = payload
        actions[idx].pasteAfterRun = pasteAfterRun
    }

    func removeAction(id: String) {
        actions.removeAll { $0.id == id }
    }

    func resetDefaultActions() {
        actions = ClipActionEngine.defaultBuiltInActions
    }

    func addExcludedBundleID(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !excludedBundleIDs.contains(trimmed) else { return }
        excludedBundleIDs.append(trimmed)
    }

    func removeExcludedBundleID(_ bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }

    func databaseFileSizeLabel() -> String {
        guard let dbPath = try? AppPaths.databasePath() else { return "0 B" }
        let walPath = dbPath + "-wal"
        let fm = FileManager.default
        let dbBytes = (try? fm.attributesOfItem(atPath: dbPath)[.size] as? Int) ?? 0
        let walBytes = (try? fm.attributesOfItem(atPath: walPath)[.size] as? Int) ?? 0
        let total = max(0, dbBytes + walBytes)
        return ClipItem.formatByteCount(total)
    }

    private func persistHotkey() {
        guard isReady else { return }
        settings.hotkey = hotkey
        onHotkeyChange?(hotkey)
    }

    private func persistLaunchAtLogin() {
        guard isReady else { return }
        settings.launchAtLogin = launchAtLogin
        do {
            let service = SMAppService.mainApp
            if launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
            launchMessage = nil
        } catch {
            launchMessage = "登录项设置失败：\(error.localizedDescription)"
        }
    }

    private func persistPanelMode() {
        guard isReady else { return }
        settings.panelMode = panelMode
        onDisplayChange?()
    }

    private func persistAttachedApp() {
        guard isReady else { return }
        settings.attachedBundleID = attachedBundleID
        onDisplayChange?()
    }

    private func persistPanelAccent() {
        guard isReady else { return }
        settings.panelAccent = panelAccent
        onDisplayChange?()
    }

    private func persistPanelDensity() {
        guard isReady else { return }
        settings.panelDensity = panelDensity
        onDisplayChange?()
    }

    private func persistPanelOpacity() {
        guard isReady else { return }
        settings.panelOpacity = panelOpacity
        onDisplayChange?()
    }

    private func persistShowPreviewPane() {
        guard isReady else { return }
        settings.showPreviewPane = showPreviewPane
        onDisplayChange?()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var store: Store? = nil
    var onToast: ((String) -> Void)? = nil
    var onReload: (() -> Void)? = nil

    @State private var dbSizeLabel: String = ""

    var body: some View {
        Form {
            if !model.accessibilityTrusted {
                accessibilitySection
            }

            Section {
                Toggle("暂停记录剪贴板（复制密码或敏感内容时开启）", isOn: $model.isRecordingPaused)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("隐私过滤应用（在这些应用中按 ⌘C 不会记录到历史）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(model.appChoices) { app in
                                if !model.excludedBundleIDs.contains(app.bundleID) {
                                    Button("\(app.name) (\(app.bundleID))") {
                                        model.addExcludedBundleID(app.bundleID)
                                    }
                                }
                            }
                        } label: {
                            Label("添加排除应用", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }

                    FlowExcludedAppsView(
                        bundleIDs: model.excludedBundleIDs,
                        onRemove: { id in model.removeExcludedBundleID(id) }
                    )
                }
            } header: {
                sectionHeader("隐私保护与敏感应用过滤", "lock.shield")
            }

            Section {
                Picker("显示方式", selection: $model.panelMode) {
                    ForEach(PanelMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(model.panelMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.panelMode == .attachedToApp {
                    Picker("吸附到", selection: $model.attachedBundleID) {
                        Text("请选择").tag("")
                        ForEach(model.appChoices) { app in
                            Text(app.name).tag(app.bundleID)
                        }
                    }
                }
                Toggle("开启右侧实时预览与动作分栏（⌘Y）", isOn: $model.showPreviewPane)
            } header: {
                sectionHeader("面板与布局", "rectangle.split.2x1")
            }

            Section {
                Picker("呼出 / 收起面板", selection: $model.hotkey) {
                    ForEach(HotkeyCombo.allCases, id: \.self) { combo in
                        Text(combo.menuLabel).tag(combo)
                    }
                }
                Text("推荐使用 ⇧⌘V 或 ⌥⌘V。⌘D 会占用浏览器收藏或访达“制作副本”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("登录时启动", isOn: $model.launchAtLogin)
                if let launchMessage = model.launchMessage {
                    Text(launchMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                sectionHeader("快捷键与启动", "command")
            }

            Section {
                Picker("强调色", selection: $model.panelAccent) {
                    ForEach(PanelAccent.allCases, id: \.self) { accent in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 10, height: 10)
                            Text(accent.title)
                        }
                        .tag(accent)
                    }
                }
                Picker("内容密度", selection: $model.panelDensity) {
                    ForEach(PanelDensity.allCases, id: \.self) { density in
                        Text(density.title).tag(density)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("面板透明度")
                        Spacer()
                        Text("\(Int((model.panelOpacity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $model.panelOpacity, in: 0.55...1.0, step: 0.01)
                }
            } header: {
                sectionHeader("外观", "paintbrush.pointed")
            }

            Section {
                Picker("最多保留历史", selection: $model.maxHistoryCount) {
                    ForEach([50, 100, 200, 500, 1000], id: \.self) { count in
                        Text("\(count) 条").tag(count)
                    }
                }
                Picker("超过天数删除", selection: $model.maxAgeDays) {
                    Text("关闭").tag(0)
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                }
                LabeledContent("本地数据库体积") {
                    HStack(spacing: 8) {
                        Text(dbSizeLabel.isEmpty ? model.databaseFileSizeLabel() : dbSizeLabel)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button("压缩瘦身") {
                            try? store?.vacuum()
                            dbSizeLabel = model.databaseFileSizeLabel()
                            onToast?("已完成数据库压缩与碎片整理")
                        }
                        .controlSize(.small)
                    }
                }
                if store != nil {
                    HStack(spacing: 8) {
                        Button {
                            exportBackupFile()
                        } label: {
                            Label("导出快捷回复与配置备份…", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            importBackupFile()
                        } label: {
                            Label("从备份导入…", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            } header: {
                sectionHeader("自动清理与数据备份", "sparkles")
            }

            Section {
                Toggle("开启智能推荐回复与自动归档（Local N-gram + Jev 引擎）", isOn: $model.enableSmartReply)
                Toggle("开启全局输入法短码联动（在任意输入框敲出 ;dz 自动展开）", isOn: $model.enableTextExpander)

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 翻译与自定义指令 API Key（可选 · 支持 DeepSeek / OpenAI 兼容接口）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField(
                        "",
                        text: $model.aiAPIKey,
                        prompt: Text("未配置时自动使用内置免配置极速翻译引擎")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI 接口地址")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField(
                            "",
                            text: $model.aiEndpoint,
                            prompt: Text("https://api.deepseek.com/v1/chat/completions")
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("模型名称")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField(
                            "",
                            text: $model.aiModelName,
                            prompt: Text("deepseek-chat")
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 140)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Jev 模型 API Key（可选 · TypeSafe System-One 70ms 极速决策）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField(
                        "",
                        text: $model.jevAPIKey,
                        prompt: Text("未填写时默认使用本地离线 N-gram 引擎")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Jev 决策接口地址")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField(
                        "",
                        text: $model.jevEndpoint,
                        prompt: Text("https://openrouter.ai/api/alpha/decisions")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                }
            } header: {
                sectionHeader("智能决策 (Jev) · 翻译与输入法联动", "bolt.badge.clock")
            }

            if model.accessibilityTrusted {
                accessibilitySection
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshAccess()
            model.refreshApps()
            dbSizeLabel = model.databaseFileSizeLabel()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            model.refreshAccess()
        }
    }

    private func exportBackupFile() {
        guard let store else { return }
        let savePanel = NSSavePanel()
        savePanel.title = "导出剪贴板快捷回复与配置备份"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmm"
        savePanel.nameFieldStringValue = "ClipHistory-Backup-\(fmt.string(from: Date())).json"
        savePanel.canCreateDirectories = true
        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                let data = try store.exportBackup(actions: model.actions)
                try data.write(to: url, options: .atomic)
                onToast?("已导出备份：\(url.lastPathComponent)")
            } catch {
                onToast?("导出失败：\(error.localizedDescription)")
            }
        }
    }

    private func importBackupFile() {
        guard let store else { return }
        let openPanel = NSOpenPanel()
        openPanel.title = "选择要导入的 ClipHistory 备份文件 (.json)"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                let result = try store.importBackup(data)
                if let importedActions = result.actions, !importedActions.isEmpty {
                    model.actions = importedActions
                }
                dbSizeLabel = model.databaseFileSizeLabel()
                onReload?()
                onToast?("成功导入 \(result.importedCount) 条记录与动作配置")
            } catch {
                onToast?("导入失败：\(error.localizedDescription)")
            }
        }
    }

    private var accessibilitySection: some View {
        Section {
            LabeledContent("状态") {
                StatusPill(ok: model.accessibilityTrusted)
            }
            Text(model.accessibilityMessage)
                .font(.caption)
                .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
            Text(Bundle.main.bundlePath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            HStack {
                Button("打开系统设置") {
                    PasteService.requestAccessibilityAccess()
                }
                Button("在 Finder 中显示") {
                    PasteService.revealCurrentApplication()
                }
                if !model.accessibilityTrusted {
                    Button("重新启动") {
                        PasteService.relaunch()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } header: {
            sectionHeader("辅助功能权限", "accessibility")
        }
    }

    private func sectionHeader(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct StatusPill: View {
    let ok: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(ok ? "已授权" : "未授权")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ok ? Color.green : Color.orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill((ok ? Color.green : Color.orange).opacity(0.14))
        )
    }
}

private struct FlowExcludedAppsView: View {
    let bundleIDs: [String]
    var onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(bundleIDs, id: \.self) { id in
                    HStack(spacing: 4) {
                        Text(KnownApps.displayName(for: id))
                            .font(.system(size: 11, weight: .medium))
                        Button {
                            onRemove(id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
        }
    }
}
