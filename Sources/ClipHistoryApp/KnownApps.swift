import AppKit

struct KnownApp: Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

enum KnownApps {
    static let presets: [KnownApp] = [
        KnownApp(bundleID: "com.tencent.xinWeChat", name: "微信"),
        KnownApp(bundleID: "com.atebits.Tweetie2", name: "X"),
        KnownApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"),
        KnownApp(bundleID: "com.apple.Safari", name: "Safari"),
        KnownApp(bundleID: "com.google.Chrome", name: "Chrome"),
        KnownApp(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge"),
        KnownApp(bundleID: "company.thebrowser.Browser", name: "Arc"),
        KnownApp(bundleID: "org.mozilla.firefox", name: "Firefox"),
        KnownApp(bundleID: "com.brave.Browser", name: "Brave")
    ]

    static func choices(including bundleID: String = "") -> [KnownApp] {
        var apps = presets
        var seen = Set(presets.map(\.bundleID))
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in running {
            guard let id = app.bundleIdentifier, !seen.contains(id) else { continue }
            if id == Bundle.main.bundleIdentifier { continue }
            seen.insert(id)
            apps.append(KnownApp(bundleID: id, name: app.localizedName ?? id))
        }
        if !bundleID.isEmpty, !seen.contains(bundleID) {
            apps.insert(KnownApp(bundleID: bundleID, name: displayName(for: bundleID)), at: 0)
        }
        return apps
    }

    static func displayName(for bundleID: String) -> String {
        if let preset = presets.first(where: { $0.bundleID == bundleID }) {
            return preset.name
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? bundleID
    }
}
