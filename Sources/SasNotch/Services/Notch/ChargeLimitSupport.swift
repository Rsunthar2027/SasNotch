// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// Charge limit wording, added by SasNotch. English for now.
enum ChargeLimitText {
    static let title = "Charge limit"
    static let toggle = "Remind me to unplug"
    static let caption = "When the Mac is plugged in at or above this level, you get a notification and a battery notice, once per charge."
    static let limit = "Limit"
    static let limitation = "SasNotch can't stop your Mac from charging. It tells you when to unplug."
    static let openBatterySettings = "Open Battery Settings"
    static let notificationsOff = "Notifications for SasNotch are off in System Settings, so none will be posted."
    static let noticeTitle = "Time to unplug"
    static let notificationTitle = "Charge limit reached"

    static func notificationBody(percent: Int) -> String {
        "Battery at \(percent)%. Unplug to keep it at your limit."
    }
}

/// The settings and the System Settings pane behind the charge limit. It
/// only reads the charge macOS already reports; holding the charge at the
/// limit would mean writing to the battery controller, which SasNotch leaves
/// alone, so all it can do is say when to unplug.
enum ChargeLimitSupport {
    static let range = 50...100
    static let step = 5
    static let defaultLimit = 80
    /// How far below the limit the charge has to fall, still plugged in,
    /// before reaching the limit again is news.
    static let rearmMargin = 5

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchChargeLimitEnabled)
    }

    static func limit(in defaults: UserDefaults = .standard) -> Int {
        sanitizedLimit(defaults.object(forKey: DefaultsKey.notchChargeLimitPercent) as? Int ?? defaultLimit)
    }

    /// Onto the slider's scale: inside its range and on one of its steps.
    static func sanitizedLimit(_ value: Int) -> Int {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        let steps = (Double(clamped - range.lowerBound) / Double(step)).rounded()
        return range.lowerBound + Int(steps) * step
    }

    /// The Battery pane's identifier, which is also its address.
    static let batteryPaneIdentifier = "com.apple.Battery-Settings.extension"
    static let batteryPaneURL = URL(string: "x-apple.systempreferences:\(batteryPaneIdentifier)")

    /// Whether a pane's Info.plist is the Battery pane, saying it opens from
    /// its address, as every pane the Command Bar opens must.
    static func opensBatteryPane(info: [String: Any]) -> Bool {
        info["CFBundleIdentifier"] as? String == batteryPaneIdentifier
            && CommandBarSystemSettingsSupport.isOpenablePane(info: info)
    }

    /// Read once from the panes this Mac ships, so the button only appears
    /// where its own System Settings declares that address. The pane's usual
    /// file is tried before the whole folder.
    static let batteryPaneAvailable: Bool = {
        let root = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true)
        func opens(_ appex: URL) -> Bool {
            let plist = appex.appendingPathComponent("Contents/Info.plist")
            guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else { return false }
            return opensBatteryPane(info: info)
        }
        if opens(root.appendingPathComponent("PowerPreferences.appex")) { return true }
        let panes = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return panes.contains { $0.pathExtension == "appex" && opens($0) }
    }()
}

/// Whether reaching the limit is still news in this charging session.
///
/// It speaks once, on the first reading on power at or past the limit, then
/// keeps quiet until the charger comes out or the charge falls well below the
/// limit, so a Mac left plugged in is not told again with every percent.
struct ChargeLimitMonitor: Equatable {
    /// Cleared once it has spoken for this session.
    private(set) var armed = true

    /// Takes one reading; true when it is the one to tell the person about.
    /// Switched off, it forgets the session it spoke for.
    mutating func update(percent: Int?, onAC: Bool, limit: Int, enabled: Bool) -> Bool {
        guard enabled, onAC else { armed = true; return false }
        guard let percent else { return false }
        let limit = ChargeLimitSupport.sanitizedLimit(limit)
        if percent <= limit - ChargeLimitSupport.rearmMargin { armed = true }
        guard armed, percent >= limit else { return false }
        armed = false
        return true
    }
}
