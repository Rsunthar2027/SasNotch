// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// The move to Liquid Glass as the island's style on macOS 26. New installs
/// start on it. A Mac set up earlier is switched once, with a notice. One that
/// first ran on an older macOS is asked once instead, since its style was
/// chosen without glass on offer. Before macOS 26 nothing changes.
enum LiquidGlassMigration {
    enum Prompt: String {
        case notice
        case offer
    }

    /// Runs at launch, before the island reads its style, so an offer's answer
    /// isn't preceded by glass that then disappears.
    static func prepare(in defaults: UserDefaults, supportsGlass: Bool) {
        guard supportsGlass else {
            defaults.set(true, forKey: DefaultsKey.liquidGlassSeenBeforeSupport)
            return
        }
        guard !defaults.bool(forKey: DefaultsKey.liquidGlassMigrationHandled) else { return }
        defaults.set(true, forKey: DefaultsKey.liquidGlassMigrationHandled)
        guard defaults.bool(forKey: DefaultsKey.hasOnboarded)
                || defaults.bool(forKey: DefaultsKey.liquidGlassSeenBeforeSupport) else { return }
        let prompt: Prompt = defaults.bool(forKey: DefaultsKey.liquidGlassSeenBeforeSupport) ? .offer : .notice
        defaults.set(prompt == .notice, forKey: DefaultsKey.notchLiquidGlassEnabled)
        defaults.set(prompt.rawValue, forKey: DefaultsKey.liquidGlassPendingPrompt)
    }

    /// The prompt still to show, taken once: it is recorded as shown before it
    /// appears, so a quit or crash while it is up never shows it again.
    static func takePendingPrompt(in defaults: UserDefaults) -> Prompt? {
        let raw = defaults.string(forKey: DefaultsKey.liquidGlassPendingPrompt)
        defaults.removeObject(forKey: DefaultsKey.liquidGlassPendingPrompt)
        return raw.flatMap(Prompt.init(rawValue:))
    }
}

/// The one-time questions after an update, as the alerts that ask them. The
/// setup offer and the glass notice share one, since neither needs its own.
struct StartupPromptAlert: Equatable {
    enum Answer: Equatable {
        case switchSetup
        case useGlass
    }

    let title: String
    let message: String
    let confirm: String
    /// What the first button does; nil when it only dismisses.
    let answer: Answer?
    let decline: String?

    static func plan(offersSetup: Bool, glass: LiquidGlassMigration.Prompt?) -> [StartupPromptAlert] {
        var alerts: [StartupPromptAlert] = []
        if offersSetup {
            let message = glass == .notice
                ? SimpleSetupText.offerMessage + "\n\n" + LiquidGlassText.notice
                : SimpleSetupText.offerMessage
            alerts.append(StartupPromptAlert(title: SimpleSetupText.offerTitle, message: message,
                                             confirm: SimpleSetupText.offerSwitch, answer: .switchSetup,
                                             decline: SimpleSetupText.offerKeep))
        } else if glass == .notice {
            alerts.append(StartupPromptAlert(title: LiquidGlassText.noticeTitle, message: LiquidGlassText.noticeDetail,
                                             confirm: LiquidGlassText.ok, answer: nil, decline: nil))
        }
        if glass == .offer {
            alerts.append(StartupPromptAlert(title: LiquidGlassText.offerTitle, message: LiquidGlassText.offerMessage,
                                             confirm: LiquidGlassText.offerUse, answer: .useGlass,
                                             decline: LiquidGlassText.offerKeep))
        }
        return alerts
    }
}

/// English-only text for the move to Liquid Glass.
enum LiquidGlassText {
    static let noticeTitle = "SasNotch now uses Liquid Glass."
    static let noticeDetail = "Change it anytime in Settings › Appearance."
    static var notice: String { noticeTitle + " " + noticeDetail }
    static let ok = "OK"
    static let offerTitle = "Your Mac now supports Liquid Glass. Switch the island to it?"
    static let offerMessage = "Change it anytime in Settings › Appearance."
    static let offerUse = "Use Liquid Glass"
    static let offerKeep = "Keep my current style"
}
