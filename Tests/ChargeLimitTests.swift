// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// The charge limit: its settings, the once-per-charge rule, and the Battery
/// pane it may offer. None of it touches the battery itself.
enum ChargeLimitTests {
    static func run(_ suite: TestSuite) {
        settings(suite)
        monitor(suite)
        wording(suite)
        batteryPane(suite)
        readOnly(suite)
    }

    private static func settings(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchChargeLimitEnabled] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.notchChargeLimitPercent] as? Int == 80
                     && SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchChargeLimitEnabled,
                                                                           DefaultsKey.notchChargeLimitPercent]),
                     "the charge limit starts off at 80% and travels with settings backups")
        suite.expect(ChargeLimitSupport.range == 50...100 && ChargeLimitSupport.step == 5
                     && ChargeLimitSupport.defaultLimit == 80 && ChargeLimitSupport.rearmMargin == 5,
                     "the slider runs from 50% to 100% in steps of 5")
        let scale = Array(stride(from: 50, through: 100, by: 5))
        suite.expect(scale.allSatisfy { ChargeLimitSupport.sanitizedLimit($0) == $0 },
                     "every step on the slider is kept as it is")
        suite.expect(ChargeLimitSupport.sanitizedLimit(82) == 80 && ChargeLimitSupport.sanitizedLimit(83) == 85
                     && ChargeLimitSupport.sanitizedLimit(49) == 50 && ChargeLimitSupport.sanitizedLimit(-10) == 50
                     && ChargeLimitSupport.sanitizedLimit(101) == 100 && ChargeLimitSupport.sanitizedLimit(.max) == 100
                     && ChargeLimitSupport.sanitizedLimit(.min) == 50,
                     "a stored limit off the scale lands on its nearest step inside the range")

        let domain = "com.sasnotch.tests.charge-limit"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(!ChargeLimitSupport.isEnabled(in: defaults) && ChargeLimitSupport.limit(in: defaults) == 80,
                     "with nothing saved the charge limit is off at 80%")
        defaults.set(true, forKey: DefaultsKey.notchChargeLimitEnabled)
        defaults.set(65, forKey: DefaultsKey.notchChargeLimitPercent)
        suite.expect(ChargeLimitSupport.isEnabled(in: defaults) && ChargeLimitSupport.limit(in: defaults) == 65,
                     "the saved switch and limit are read back")
        defaults.set(300, forKey: DefaultsKey.notchChargeLimitPercent)
        suite.expect(ChargeLimitSupport.limit(in: defaults) == 100, "a saved limit past 100% reads as 100%")
        defaults.set(12, forKey: DefaultsKey.notchChargeLimitPercent)
        suite.expect(ChargeLimitSupport.limit(in: defaults) == 50, "a saved limit under 50% reads as 50%")
        defaults.set("eighty", forKey: DefaultsKey.notchChargeLimitPercent)
        suite.expect(ChargeLimitSupport.limit(in: defaults) == 80, "an unreadable saved limit falls back to 80%")
    }

    /// Readings fed in order to one monitor; each answer says whether that
    /// reading was the one to tell the person about.
    private static func feed(_ monitor: inout ChargeLimitMonitor, _ readings: [(Int?, Bool)],
                             limit: Int = 80, enabled: Bool = true) -> [Bool] {
        readings.map { monitor.update(percent: $0.0, onAC: $0.1, limit: limit, enabled: enabled) }
    }

    private static func monitor(_ suite: TestSuite) {
        var charging = ChargeLimitMonitor()
        suite.expect(charging.armed, "a new monitor has not spoken yet")
        suite.expect(feed(&charging, [(77, true), (79, true), (80, true), (81, true), (90, true), (100, true)])
                     == [false, false, true, false, false, false],
                     "charging past the limit is told once, at the first reading that reaches it")
        suite.expect(!charging.armed, "having spoken, it waits for a new charging session")

        var jump = ChargeLimitMonitor()
        suite.expect(feed(&jump, [(78, true), (83, true), (84, true)]) == [false, true, false],
                     "a reading that skips past the limit still counts as reaching it")

        var onBattery = ChargeLimitMonitor()
        suite.expect(feed(&onBattery, [(95, false), (85, false), (80, false)]) == [false, false, false],
                     "on battery the limit is never news")

        var unplugged = ChargeLimitMonitor()
        suite.expect(feed(&unplugged, [(80, true), (82, false), (82, true), (83, true)]) == [true, false, true, false],
                     "unplugging starts a new charging session, so plugging back in above the limit is told again")

        var drop = ChargeLimitMonitor()
        suite.expect(feed(&drop, [(80, true), (76, true), (80, true)]) == [true, false, false],
                     "a dip of less than five points while plugged in is the same session")
        suite.expect(feed(&drop, [(75, true), (79, true), (80, true)]) == [false, false, true],
                     "falling five points below the limit while plugged in re-arms it")

        var launch = ChargeLimitMonitor()
        suite.expect(feed(&launch, [(100, true), (100, true)]) == [true, false],
                     "a first reading already past the limit on power is told once")

        var unknown = ChargeLimitMonitor()
        suite.expect(feed(&unknown, [(nil, true), (80, true), (nil, true), (nil, true), (81, true)])
                     == [false, true, false, false, false],
                     "a reading without a charge neither speaks nor re-arms")

        var off = ChargeLimitMonitor()
        suite.expect(feed(&off, [(85, true), (90, true)], enabled: false) == [false, false],
                     "switched off, the limit says nothing")
        var toggled = ChargeLimitMonitor()
        _ = feed(&toggled, [(80, true)])
        _ = feed(&toggled, [(82, true)], enabled: false)
        suite.expect(toggled.armed && feed(&toggled, [(82, true)]) == [true],
                     "switching it off and on again forgets the session it spoke for")

        var full = ChargeLimitMonitor()
        suite.expect(feed(&full, [(98, true), (99, true), (100, true)], limit: 100) == [false, false, true],
                     "a 100% limit is reached only at a full charge")
        var lowest = ChargeLimitMonitor()
        suite.expect(feed(&lowest, [(44, true), (49, true), (50, true)], limit: 50) == [false, false, true],
                     "a 50% limit is reached at 50%")

        var raised = ChargeLimitMonitor()
        suite.expect(feed(&raised, [(80, true), (82, true)]) == [true, false]
                     && feed(&raised, [(85, true), (90, true)], limit: 90) == [false, true],
                     "raising the limit well above the charge makes the new limit news")
        var lowered = ChargeLimitMonitor()
        suite.expect(feed(&lowered, [(80, true)]) == [true]
                     && feed(&lowered, [(81, true), (82, true)], limit: 60) == [false, false],
                     "lowering the limit after it spoke does not repeat the same advice")

        var offScale = ChargeLimitMonitor()
        suite.expect(feed(&offScale, [(84, true), (85, true)], limit: 83) == [false, true],
                     "a limit off the scale is read on its nearest step")
    }

    private static func wording(_ suite: TestSuite) {
        suite.expect(ChargeLimitText.notificationBody(percent: 80) == "Battery at 80%. Unplug to keep it at your limit."
                     && ChargeLimitText.notificationBody(percent: 87) == "Battery at 87%. Unplug to keep it at your limit.",
                     "the notification names the charge it was posted at")
        suite.expect(ChargeLimitText.limitation == "SasNotch can't stop your Mac from charging. It tells you when to unplug.",
                     "the settings say plainly that SasNotch cannot stop the charge")
    }

    private static func batteryPane(_ suite: TestSuite) {
        let settings: [String: Any] = [
            "allowsXAppleSystemPreferencesURLScheme": true,
            "legacyBundleIdentifier": ["com.apple.preference.battery", "com.apple.preferences.EnergySaverPrefPane"],
        ]
        // As macOS 26.3 ships the pane, PowerPreferences.appex.
        let shipped: [String: Any] = [
            "CFBundleIdentifier": "com.apple.Battery-Settings.extension",
            "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": "com.apple.Settings.extension.ui",
                                         "SettingsExtensionAttributes": settings],
        ]
        suite.expect(ChargeLimitSupport.opensBatteryPane(info: shipped),
                     "the Battery pane that says it opens from its address is offered")
        var other = shipped
        other["CFBundleIdentifier"] = "com.apple.Displays-Settings.extension"
        suite.expect(!ChargeLimitSupport.opensBatteryPane(info: other), "another pane is not the Battery pane")
        var closed = shipped
        closed["EXAppExtensionAttributes"] = ["SettingsExtensionAttributes": ["allowsXAppleSystemPreferencesURLScheme": false]]
        suite.expect(!ChargeLimitSupport.opensBatteryPane(info: closed) && !ChargeLimitSupport.opensBatteryPane(info: [:]),
                     "a Battery pane that does not answer to its address gets no button")
        suite.expect(ChargeLimitSupport.batteryPaneURL?.absoluteString
                     == "x-apple.systempreferences:com.apple.Battery-Settings.extension",
                     "the button opens the Battery pane by its identifier")
    }

    /// The limit only listens: nothing behind it writes to the battery's
    /// controller or asks the privileged fan helper for anything.
    private static func readOnly(_ suite: TestSuite) {
        let support = (try? String(contentsOfFile: "Sources/SasNotch/Services/Notch/ChargeLimitSupport.swift",
                                   encoding: .utf8)) ?? ""
        let service = (try? String(contentsOfFile: "Sources/SasNotch/Services/Notch/NotchService.swift",
                                   encoding: .utf8)) ?? ""
        let notice = service.components(separatedBy: "    private func chargeLimitNotice(").dropFirst().first?
            .components(separatedBy: "\n    }\n").first ?? ""
        suite.expect(!support.isEmpty && !notice.isEmpty, "the charge limit's sources are read back")
        let forbidden = ["smc", "fancontrol", "helper", "iopmassertion", "pmset"]
        suite.expect(forbidden.allSatisfy { !support.lowercased().contains($0) && !notice.lowercased().contains($0) },
                     "the charge limit reads the charge and posts a notification, nothing more")
        suite.expect(service.contains("powerSampler = PowerSampler(smc: nil)"),
                     "the island samples power without opening the SMC")
    }
}
