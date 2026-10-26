// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Modified for SasNotch by SasNotch contributors, 2026

import AppKit

/// Run the production launch gates, close callbacks and completion writes with
/// isolated preferences and an explicit queue. No app windows become visible.
enum UpdateIntroFlowTests {
    enum AppInfo {
        static var version = "3.4.0"
        static var isBeta: Bool { version.contains("beta") }
        static var isDeveloperBuild = false
    }
    enum UserDefaults { static var standard: Foundation.UserDefaults! }
    enum DispatchQueue {
        static var main = Queue()
        final class Queue {
            var jobs: [() -> Void] = []
            func async(execute action: @escaping () -> Void) { jobs.append(action) }
            func drain() {
                for _ in 0..<20 where !jobs.isEmpty { jobs.removeFirst()() }
            }
        }
    }
    enum WindowActivationPolicy {
        static var retention = WindowActivationRetention()
        static var history: [Int] = []
        static func retain() {
            _ = retention.retain()
            history.append(retention.count)
        }
        static func release() {
            _ = retention.release()
            history.append(retention.count)
        }
    }
    final class SecureInputMonitor {
        static let shared = SecureInputMonitor()
        func setSettingsWindowOpen(_ open: Bool) {}
    }
    class Fixture {
        var settingsWindow: NSWindow?
        var settingsKeepsAppRegular = false
        var onboardingWindow: NSWindow?
        var supportIntroWindow: NSWindow?
        var supportIntroCanClose = false
        var supportIntroIsReview = false
        var updateHighlightsWindow: NSWindow?
        var updateHighlightsIsReview = false
        var updateShowcaseWindow: NSWindow?
        var updatePreviewWindow: NSWindow?
        var whatsNewWindow: NSWindow?
        var whatsNewIsReview = false
        var updateWindowsKeepingAppRegular = Set<ObjectIdentifier>()
        var settingsFloatsForWhatsNew = false
        var configureUpdateWindow: ((NSWindow) -> Void)?
        /// Whether the update touches anything this Mac uses.
        var whatsNewHasContent = true
        var isTerminating = false
        var shown: [String] = []
        func saveSettingsWindowSize(_ window: NSWindow) {}
        func markUpdateShowcaseIntroSeenIfCurrentUpdate() {}
        func markUpdateShowcaseIntroSeen() {}
        func showUpdateShowcaseIntroIfNeeded() -> Bool { false }
        func showBrightnessUpdatePromptIfNeeded() { shown.append("finished") }
        func showUpdateHighlights(isReview: Bool = false) {
            updateHighlightsIsReview = isReview
            updateHighlightsWindow = NSWindow()
            shown.append("tour")
        }
        @discardableResult
        func showWhatsNew(from previous: String, includeUnreleased: Bool = false, isReview: Bool = false) -> Bool {
            guard whatsNewHasContent || isReview else { return false }
            whatsNewIsReview = isReview
            whatsNewWindow = NSWindow()
            configureUpdateWindow?(whatsNewWindow!)
            shown.append("whatsNew \(previous)")
            return true
        }
        func showSupportUpdateIntro(isReview: Bool = false) {
            guard !isTerminating, isReview || !AppInfo.isBeta else { return }
            supportIntroIsReview = isReview
            supportIntroWindow = NSPanel()
            configureUpdateWindow?(supportIntroWindow!)
            shown.append("support")
        }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.sasnotch.tests.update-intros.\(UUID().uuidString)"
        UserDefaults.standard = Foundation.UserDefaults(suiteName: domain)!
        defer {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard = nil
        }
        func reset(_ version: String) -> Host {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            AppInfo.version = version
            DispatchQueue.main = DispatchQueue.Queue()
            WindowActivationPolicy.retention = WindowActivationRetention()
            WindowActivationPolicy.history = []
            let host = Host()
            host.configureUpdateWindow = { [weak host] window in host?.keepUpdateWindowReachable(window) }
            return host
        }
        func close(_ window: NSWindow?, in host: Host) {
            guard let window else { suite.expect(false, "the expected intro exists"); return }
            host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
            DispatchQueue.main.drain()
            suite.expect(DispatchQueue.main.jobs.isEmpty, "intro transitions settle without a loop")
        }
        // SasNotch shows only its own What's New after an update: the upstream
        // tour, showcase and support invitations are never presented.
        for version in ["1.0.0", "1.0.1", "1.1.0-beta.1"] {
            let host = reset(version)
            host.presentUpdateIntros()
            suite.expect(host.shown.isEmpty, "\(version) opens no tour, showcase or support window on launch")
        }
        let quittingReview = reset("1.0.0")
        quittingReview.showWhatsNew(from: "0.9.0", includeUnreleased: true, isReview: true)
        quittingReview.isTerminating = true
        close(quittingReview.whatsNewWindow, in: quittingReview)
        suite.expect(quittingReview.shown == ["whatsNew 0.9.0"], "quitting during review never opens another window")

        runWindowReachability(suite, reset: reset, close: close)
        runWhatsNew(suite, domain: domain, reset: reset, close: close)
    }

    private static func runWindowReachability(_ suite: TestSuite, reset: (String) -> Host,
                                              close: (NSWindow?, Host) -> Void) {
        let host = reset("1.0.1")
        host.showWhatsNew(from: "1.0.0", isReview: true)
        let notes = host.whatsNewWindow!
        host.keepUpdateWindowReachable(notes)
        suite.expect(WindowActivationPolicy.retention.count == 1,
                     "reopening the same window retains Dock presence only once")
        suite.expect(notes.level == .floating && notes.level.rawValue < NSWindow.Level.modalPanel.rawValue,
                     "What's New floats above ordinary windows without using a modal or overlay level")
        suite.expect(!notes.hidesOnDeactivate && !notes.canHide
                        && notes.collectionBehavior.contains(.participatesInCycle)
                        && !notes.collectionBehavior.contains(.ignoresCycle),
                     "What's New stays visible and participates in window cycling")
        host.settingsWindow = NSWindow()
        host.settingsWindow!.level = .floating
        host.settingsFloatsForWhatsNew = true
        close(notes, host)
        suite.expect(WindowActivationPolicy.retention.count == 0 && host.updateWindowsKeepingAppRegular.isEmpty,
                     "closing What's New restores the menu-bar-only lifecycle")
        suite.expect(host.settingsWindow?.level == .normal && !host.settingsFloatsForWhatsNew,
                     "closing What's New restores any temporarily raised Settings window")
        suite.expect(host.supportIntroWindow == nil, "no support window follows What's New")
    }

    private static func runWhatsNew(_ suite: TestSuite, domain: String, reset clear: (String) -> Host,
                                     close: (NSWindow?, Host) -> Void) {
        let pendingKey = DefaultsKey.whatsNewPendingVersion
        // The app registers this switch as on; the test domain has no
        // registered defaults, and registering one would outlive this suite.
        func reset(_ version: String) -> Host {
            let host = clear(version)
            UserDefaults.standard.set(true, forKey: DefaultsKey.releaseNotesOnUpdate)
            return host
        }
        func launch(_ host: Host, previous: String?) {
            // The launch reads the last version before it overwrites it.
            host.queueWhatsNewIfNeeded(previousVersion: previous)
            UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
            host.presentUpdateIntros()
        }

        let stable = reset("1.0.1")
        launch(stable, previous: "1.0.0")
        suite.expect(stable.shown == ["whatsNew 1.0.0"], "an update opens What's New")
        close(stable.whatsNewWindow, stable)
        suite.expect(stable.shown == ["whatsNew 1.0.0"], "nothing else follows What's New")
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil
                        && UserDefaults.standard.string(forKey: DefaultsKey.whatsNewSeenVersion) == "1.0.1",
                     "closing What's New consumes the update")
        suite.expect(UserDefaults.standard.string(forKey: DefaultsKey.whatsNewKnownFeatures)
                        == WhatsNewInfo.knownFeaturesValue,
                     "closing What's New records the features this version has")
        let relaunch = Host()
        launch(relaunch, previous: "1.0.1")
        suite.expect(relaunch.shown.isEmpty, "What's New never repeats for the same update")

        let beta = reset("1.1.0-beta.1")
        launch(beta, previous: "1.0.1")
        suite.expect(beta.shown == ["whatsNew 1.0.1"], "beta updates open What's New too")

        let interrupted = reset("1.0.1")
        launch(interrupted, previous: "1.0.0")
        interrupted.isTerminating = true
        close(interrupted.whatsNewWindow, interrupted)
        suite.expect(interrupted.shown == ["whatsNew 1.0.0"]
                        && UserDefaults.standard.string(forKey: pendingKey) == "1.0.0",
                     "quitting during What's New keeps it for the next launch and opens nothing else")
        AppInfo.version = "1.0.2"
        let secondUpdate = Host()
        launch(secondUpdate, previous: "1.0.1")
        suite.expect(secondUpdate.shown == ["whatsNew 1.0.0"],
                     "a second update before the window was read keeps the older start")

        let skippedStart = reset("1.0.1")
        // A start that does not finish queues the update but opens nothing.
        skippedStart.queueWhatsNewIfNeeded(previousVersion: "1.0.0")
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
        let nextStart = Host()
        launch(nextStart, previous: "1.0.1")
        suite.expect(nextStart.shown.first == "whatsNew 1.0.0", "an interrupted start still shows What's New later")

        let downgraded = reset("1.0.1")
        launch(downgraded, previous: "1.0.0")
        AppInfo.version = "1.0.0"
        let older = Host()
        older.queueWhatsNewIfNeeded(previousVersion: "1.0.1")
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil, "a downgrade drops the waiting window")

        for previous in [nil, "", "dev", "1.0.1", "1.1.0"] as [String?] {
            let host = reset("1.0.1")
            host.queueWhatsNewIfNeeded(previousVersion: previous)
            suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil,
                         "no update from \(previous ?? "nil") queues nothing")
        }

        let developer = reset("1.0.1")
        AppInfo.isDeveloperBuild = true
        developer.queueWhatsNewIfNeeded(previousVersion: "1.0.0")
        AppInfo.isDeveloperBuild = false
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "the Developer build never queues What's New on its own")

        let nothingForYou = reset("1.0.2")
        nothingForYou.whatsNewHasContent = false
        launch(nothingForYou, previous: "1.0.0")
        suite.expect(nothingForYou.shown.isEmpty && UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "an update with nothing for this Mac skips What's New and consumes it")

        let optedOut = reset("1.0.2")
        UserDefaults.standard.set(false, forKey: DefaultsKey.releaseNotesOnUpdate)
        launch(optedOut, previous: "1.0.0")
        suite.expect(optedOut.shown.isEmpty && UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "with What's New turned off the update counts as read")

        let fresh = reset("1.0.2")
        fresh.markOnboardingComplete()
        // A backup made on an older version restores that version's marker.
        fresh.queueWhatsNewIfNeeded(previousVersion: "1.0.0")
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "restoring an older backup after onboarding is not an update")

        let onboarding = reset("1.0.1")
        UserDefaults.standard.set("1.0.0", forKey: pendingKey)
        onboarding.markOnboardingComplete()
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == "1.0.0",
                     "reviewing the intro leaves a waiting What's New alone")

        for version in ["1.1.0-beta.2", "1.1.0", "1.2.0"] {
            let review = reset(version)
            let before = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
            review.showWhatsNew(from: "1.0.1", includeUnreleased: true, isReview: true)
            close(review.whatsNewWindow, review)
            suite.expect(review.shown == ["whatsNew 1.0.1"] && review.supportIntroWindow == nil,
                         "closing a changelog preview opens nothing else")
            suite.expect(NSDictionary(dictionary: before).isEqual(
                            to: UserDefaults.standard.persistentDomain(forName: domain) ?? [:]),
                         "a preview never consumes automatic launch markers")
        }
    }
}
