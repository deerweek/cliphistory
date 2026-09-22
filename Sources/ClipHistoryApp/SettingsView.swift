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
        }
    }
    @Published var maxAgeDays: Int {
        didSet {
            guard isReady else { return }
            settings.maxAgeDays = maxAgeDays
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
    @Published var appChoices: [KnownApp] = []
    @Published var accessibilityTrusted = false
    @Published var accessibilityMessage = ""
    @Published var launchMessage: String?

    private let settings: AppSettings
    private var isReady = false
    var onHotkeyChange: ((HotkeyCombo) -> Void)?
    var onDisplayChange: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        hotkey = settings.hotkey
        maxHistoryCount = settings.maxHistoryCount
        maxAgeDays = settings.maxAgeDays
        launchAtLogin = settings.launchAtLogin
        panelMode = settings.panelMode
        attachedBundleID = settings.attachedBundleID
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
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
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
                    Text("列表里有微信、X、WhatsApp 和常见浏览器。正在运行的其他应用也会出现。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                sectionHeader("面板", "rectangle.on.rectangle")
            }

            Section {
                Picker("弹出面板", selection: $model.hotkey) {
                    ForEach(HotkeyCombo.allCases, id: \.self) { combo in
                        Text(combo.menuLabel).tag(combo)
                    }
                }
                Text("⌘D 会占用访达的“制作副本”。需要避开时改用 ⇧⌘D 或 ⇧⌘V。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeader("快捷键", "command")
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
                Text("置顶项和快捷回复不会被自动删除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeader("自动清理", "sparkles")
            }

            Section {
                Toggle("登录时启动", isOn: $model.launchAtLogin)
                if let launchMessage = model.launchMessage {
                    Text(launchMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                sectionHeader("启动", "power")
            }

            Section {
                LabeledContent("状态") {
                    StatusPill(ok: model.accessibilityTrusted)
                }
                Text("请在系统设置里勾选下面路径对应的这一份应用。旧版本或其他位置的“剪贴板记录”授权不会自动套用到当前副本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.accessibilityMessage)
                    .font(.caption)
                    .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                Text(Bundle.main.bundlePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知") · PID \(ProcessInfo.processInfo.processIdentifier)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                sectionHeader("辅助功能", "accessibility")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshAccess()
            model.refreshApps()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            model.refreshAccess()
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
