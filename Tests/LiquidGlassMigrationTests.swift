// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

enum LiquidGlassMigrationTests {
    static func run(_ suite: TestSuite) {
        migration(suite)
        plan(suite)
        suite.expect(NotchGlassText.requiresMacOS26 == "Requires macOS 26 or later.",
                     "before macOS 26 the setting says what it needs")
    }

    private static func withDefaults(_ body: (UserDefaults) -> Void) {
        let domain = "sasnotch.tests.glass-migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        body(defaults)
    }

    private static func migration(_ suite: TestSuite) {
        withDefaults { defaults in
            LiquidGlassMigration.prepare(in: defaults, supportsGlass: true)
            suite.expect(LiquidGlassMigration.takePendingPrompt(in: defaults) == nil
                         && defaults.object(forKey: DefaultsKey.notchLiquidGlassEnabled) == nil,
                         "a new install on macOS 26 starts on the default glass with no prompt")
        }
        withDefaults { defaults in
            defaults.set(true, forKey: DefaultsKey.hasOnboarded)
            defaults.set(false, forKey: DefaultsKey.notchLiquidGlassEnabled)
            defaults.set(false, forKey: DefaultsKey.notchTranslucentBackground)
            LiquidGlassMigration.prepare(in: defaults, supportsGlass: true)
            suite.expect(defaults.bool(forKey: DefaultsKey.notchLiquidGlassEnabled),
                         "an existing Mac on macOS 26 is switched to glass")
            suite.expect(defaults.object(forKey: DefaultsKey.notchTranslucentBackground) as? Bool == false,
                         "its other settings stay untouched")
            suite.expect(LiquidGlassMigration.takePendingPrompt(in: defaults) == .notice, "and it is told, once")
            suite.expect(LiquidGlassMigration.takePendingPrompt(in: defaults) == nil, "a prompt is taken only once")
            defaults.set(false, forKey: DefaultsKey.notchLiquidGlassEnabled)
            LiquidGlassMigration.prepare(in: defaults, supportsGlass: true)
            suite.expect(!defaults.bool(forKey: DefaultsKey.notchLiquidGlassEnabled)
                         && LiquidGlassMigration.takePendingPrompt(in: defaults) == nil,
                         "turning glass off afterwards sticks across launches")
        }
        withDefaults { defaults in
            defaults.set(true, forKey: DefaultsKey.hasOnboarded)
            defaults.set(true, forKey: DefaultsKey.notchTranslucentBackground)
            LiquidGlassMigration.prepare(in: defaults, supportsGlass: false)
            suite.expect(LiquidGlassMigration.takePendingPrompt(in: defaults) == nil
                         && defaults.object(forKey: DefaultsKey.notchLiquidGlassEnabled) == nil
                         && !defaults.bool(forKey: DefaultsKey.liquidGlassMigrationHandled),
                         "before macOS 26 nothing changes and nothing is shown")
            LiquidGlassMigration.prepare(in: defaults, supportsGlass: true)
            suite.expect(!defaults.bool(forKey: DefaultsKey.notchLiquidGlassEnabled),
                         "after upgrading macOS the old style stays until the answer")
            suite.expect(LiquidGlassMigration.takePendingPrompt(in: defaults) == .offer,
                         "after upgrading macOS the switch is offered, not made")
            LiquidGlassMigration.prepare(in: defaults, supportsGlass: true)
            suite.expect(LiquidGlassMigration.takePendingPrompt(in: defaults) == nil, "and offered only once")
        }
        withDefaults { defaults in
            LiquidGlassMigration.prepare(in: defaults, supportsGlass: false)
            LiquidGlassMigration.prepare(in: defaults, supportsGlass: true)
            suite.expect(LiquidGlassMigration.takePendingPrompt(in: defaults) == .offer,
                         "a Mac set up new before macOS 26 is also offered it after upgrading")
        }
        withDefaults { defaults in
            defaults.set("mirror", forKey: DefaultsKey.liquidGlassPendingPrompt)
            suite.expect(LiquidGlassMigration.takePendingPrompt(in: defaults) == nil
                         && defaults.string(forKey: DefaultsKey.liquidGlassPendingPrompt) == nil,
                         "an unreadable prompt shows nothing and is cleared")
        }
    }

    private static func plan(_ suite: TestSuite) {
        suite.expect(StartupPromptAlert.plan(offersSetup: false, glass: nil).isEmpty, "nothing to say shows nothing")
        let both = StartupPromptAlert.plan(offersSetup: true, glass: .notice)
        suite.expect(both.count == 1 && both[0].answer == .switchSetup
                     && both[0].title == "SasNotch now has a simpler default setup. Switch to it?"
                     && both[0].confirm == "Switch to new setup" && both[0].decline == "Keep my current setup"
                     && both[0].message.contains("SasNotch now uses Liquid Glass. Change it anytime in Settings › Appearance."),
                     "the setup offer and the glass notice share one sheet")
        let notice = StartupPromptAlert.plan(offersSetup: false, glass: .notice)
        suite.expect(notice.count == 1 && notice[0].answer == nil && notice[0].decline == nil
                     && notice[0].title + " " + notice[0].message
                        == "SasNotch now uses Liquid Glass. Change it anytime in Settings › Appearance.",
                     "the notice alone reads as written and only dismisses")
        let offer = StartupPromptAlert.plan(offersSetup: true, glass: .offer)
        suite.expect(offer.map(\.answer) == [.switchSetup, .useGlass]
                     && !offer[0].message.contains("Liquid Glass"),
                     "a real question about glass keeps its own alert")
    }
}
