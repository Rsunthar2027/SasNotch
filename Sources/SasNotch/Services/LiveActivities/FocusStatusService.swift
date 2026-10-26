// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024-2026 Atoll Contributors
// Copyright (C) 2026 SasNotch contributors
//
// Focus detection follows Atoll's DoNotDisturbManager (Ebullioscopic/Atoll,
// GPL-3.0-or-later): the system's Do Not Disturb distributed notifications,
// checked against the Focus assertions file when it can be read.

import AppKit
import Combine

/// Whether a Focus is on, and a way to turn it on or off from the island.
///
/// macOS has no public API to set a Focus, so the toggle runs a Shortcut the
/// person makes once with the Shortcuts app's "Set Focus" action. Detection
/// needs no permission; reading the starting state needs Full Disk Access,
/// and without it the state is learned from the first change.
/// Main thread only, like the island it reports to.
final class FocusStatusService: ObservableObject {
    static let shared = FocusStatusService()

    /// Nil until the state is known.
    @Published private(set) var isActive: Bool?

    static let enabledNotification = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let disabledNotification = Notification.Name("_NSDoNotDisturbDisabledNotification")
    static let defaultShortcutName = "SasNotch Focus"

    private let center = DistributedNotificationCenter.default()
    private var observing = false

    private init() {}

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchFocusEnabled)
    }

    static func shortcutName(in defaults: UserDefaults = .standard) -> String {
        let saved = defaults.string(forKey: DefaultsKey.notchFocusShortcut)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultShortcutName : saved
    }

    func syncWithPreferences() {
        Self.isEnabled() ? start() : stop()
    }

    func start() {
        guard !observing else { return }
        observing = true
        center.addObserver(self, selector: #selector(focusEnabled), name: Self.enabledNotification,
                           object: nil, suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(focusDisabled), name: Self.disabledNotification,
                           object: nil, suspensionBehavior: .deliverImmediately)
        if isActive == nil { isActive = Self.readAssertions() }
    }

    func stop() {
        guard observing else { return }
        observing = false
        center.removeObserver(self, name: Self.enabledNotification, object: nil)
        center.removeObserver(self, name: Self.disabledNotification, object: nil)
    }

    @objc private func focusEnabled(_ notification: Notification) {
        DispatchQueue.main.async { self.apply(true) }
    }

    @objc private func focusDisabled(_ notification: Notification) {
        DispatchQueue.main.async { self.apply(false) }
    }

    private func apply(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        NotchService.shared.show(NotchNotice(event: .focus,
                                             title: active ? FocusText.on : FocusText.off,
                                             detail: active ? FocusText.silenced : "",
                                             symbol: active ? "moon.fill" : "moon"))
    }

    /// The Focus assertions macOS keeps while a Focus is on. Unreadable
    /// without Full Disk Access, which leaves the state unknown.
    static func readAssertions(
        at url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    ) -> Bool? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return FocusSupport.isActive(assertions: data)
    }

    /// Runs the Focus shortcut. When it is missing, explains how to make it.
    func toggle() {
        let name = Self.shortcutName()
        Task.detached(priority: .userInitiated) {
            let ran = Self.runShortcut(named: name)
            if !ran { DispatchQueue.main.async { Self.explainShortcut(named: name) } }
        }
    }

    private static func runShortcut(named name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func explainShortcut(named name: String) {
        let alert = NSAlert()
        alert.messageText = FocusText.setupTitle
        alert.informativeText = String(format: FocusText.setupMessage, name)
        alert.addButton(withTitle: FocusText.openShortcuts)
        alert.addButton(withTitle: FocusText.notNow)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Focus wording, added by SasNotch. English for now.
enum FocusText {
    static let title = "Focus"
    static let on = "Focus on"
    static let off = "Focus off"
    static let silenced = "Notifications silenced"
    static let setupTitle = "Set up the Focus shortcut"
    static let setupMessage = "macOS lets apps turn Focus on and off only through Shortcuts. In the Shortcuts app, make a shortcut named “%@” with the “Set Focus” action set to turn Do Not Disturb on or off (or Toggle), then click Focus in the island again."
    static let openShortcuts = "Open Shortcuts"
    static let notNow = "Not Now"
    static let settingsToggle = "Show Focus changes"
    static let settingsCaption = "Shows when a Focus turns on or off. Clicking Focus in the island runs the shortcut named below."
    static let shortcutField = "Shortcut name"
}
