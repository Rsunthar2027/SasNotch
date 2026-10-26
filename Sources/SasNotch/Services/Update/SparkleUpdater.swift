// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import AppKit
import Sparkle

/// Sparkle 2 behind UpdateService. Releases are found through the appcast in
/// the latest GitHub release and verified with the EdDSA key in Info.plist,
/// so updates work without an Apple Developer ID. Sparkle shows its own
/// windows for the release notes, download and relaunch.
final class SparkleUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = SparkleUpdater()

    private var controller: SPUStandardUpdaterController?

    /// A build is set up for updates when it carries a feed and a public key.
    /// The local Developer build never updates itself.
    static var isConfigured: Bool {
        guard !AppInfo.isDeveloperBuild,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, !feed.isEmpty,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty
        else { return false }
        return true
    }

    func start(automaticChecks: Bool) {
        guard Self.isConfigured else { return }
        if controller == nil {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self,
                                                      userDriverDelegate: nil)
        }
        controller?.updater.automaticallyChecksForUpdates = automaticChecks
    }

    /// Sparkle's own check, with its window, for the menu and the About page.
    func checkForUpdates() {
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = UpdateText.unavailableTitle
            alert.informativeText = UpdateText.unavailableMessage
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func checkInBackground() {
        controller?.updater.checkForUpdatesInBackground()
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        DispatchQueue.main.async { UpdateService.shared.sparkleFound(version: version) }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        DispatchQueue.main.async { UpdateService.shared.sparkleFoundNothing() }
    }
}

/// Update wording, added by SasNotch. English for now.
enum UpdateText {
    static let unavailableTitle = "Updates are not set up in this build"
    static let unavailableMessage = "This copy of SasNotch was built without an update feed. Download the latest release from GitHub, or build from source."
}
