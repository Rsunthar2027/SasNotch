// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// The menu bar's Pause: switches the island off and remembers that it was
/// on, so Resume brings it back. It survives a relaunch, as the island's own
/// switch does, and turning the island on in Settings ends the pause.
enum IslandPause {
    static func isPaused(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.islandPaused) && !defaults.bool(forKey: DefaultsKey.notchEnabled)
    }

    static func toggle(in defaults: UserDefaults = .standard) {
        if isPaused(in: defaults) {
            defaults.set(false, forKey: DefaultsKey.islandPaused)
            defaults.set(true, forKey: DefaultsKey.notchEnabled)
        } else if defaults.bool(forKey: DefaultsKey.notchEnabled) {
            defaults.set(true, forKey: DefaultsKey.islandPaused)
            defaults.set(false, forKey: DefaultsKey.notchEnabled)
        }
        NotchService.shared.syncWithPreferences()
    }
}

/// Menu bar wording, added by SasNotch. English for now.
enum MenuText {
    static let pause = "Pause Island"
    static let resume = "Resume Island"
}
