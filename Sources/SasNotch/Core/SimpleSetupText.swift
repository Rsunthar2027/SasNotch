// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

/// English-only strings for the simpler default setup: the Features page's
/// three sections, the locked island tiles, the reset button and the one-time
/// offer to people who set SasNotch up before it existed.
enum SimpleSetupText {
    static let coreTitle = "Island"
    static let coreCaption = "The island's 12 tiles. They stay installed; each tile's own settings can still hide it."
    static let moreTitle = "More tools"
    static let moreCaption = "Turn on the ones you want. Each keeps its settings when turned off."
    static let advancedTitle = "Advanced features"
    static let advancedCaption = "Everything else, installed only when you choose it."
    static let expanded = "Expanded"
    static let collapsed = "Collapsed"
    static let locked = "Always installed"
    static let lockedHelp = "Part of the island's core tiles, so it stays installed."

    static let resetButton = "Reset to recommended setup"
    static let resetCaption = "The island's tiles plus Window switcher, Window layout, Keep awake and Displays."
    static let resetConfirmTitle = "Reset to the recommended setup?"
    static let resetConfirmMessage = "The island's tiles, Window switcher, Window layout, Keep awake and Displays stay installed and switched on. Everything else is uninstalled. No feature loses its settings, and each comes back with one click."
    static let resetConfirm = "Reset"
    static let cancel = "Cancel"

    static let offerTitle = "SasNotch now has a simpler default setup. Switch to it?"
    static let offerMessage = "The island's 12 tiles, Window switcher, Window layout, Keep awake and Displays are installed and switched on. Everything else is uninstalled but keeps its settings, so it comes back as you left it. You can change this later in Settings → Features."
    static let offerSwitch = "Switch to new setup"
    static let offerKeep = "Keep my current setup"
}
