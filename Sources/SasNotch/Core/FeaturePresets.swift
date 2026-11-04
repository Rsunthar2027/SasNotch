// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Modified for SasNotch by SasNotch contributors, 2026

import Foundation

/// One-click starting points for the Features hub. A preset is a shape, not a
/// prison: applying one installs and engages its features and uninstalls the
/// rest, except the island's locked core tiles, which every preset keeps.
/// Nothing is deleted — every feature keeps its settings and comes back with
/// one click, exactly like any hub install.
enum FeaturePreset: String, CaseIterable, Identifiable {
    case essential, windows, battery

    var id: String { rawValue }

    /// A clean install starts from the recommended Essential set before any
    /// feature binding runs, written out for every feature so the registered
    /// defaults (which describe an updating Mac's install) never apply to it.
    /// It already has the simpler setup, so it is never offered it. Updates
    /// keep every existing availability choice, and an interrupted setup
    /// keeps the selection already applied on its purpose step.
    static func prepareFirstRunAvailability(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: DefaultsKey.hasOnboarded),
              defaults.integer(forKey: DefaultsKey.onboardingStep) == 0
        else { return }
        let selected = FeaturePreset.essential.features
        for feature in AppFeature.allCases {
            defaults.set(selected.contains(feature), forKey: feature.availabilityKey)
        }
        defaults.set(true, forKey: DefaultsKey.simpleSetupOfferAnswered)
    }

    /// Whether the installed features are exactly the recommended setup, so
    /// offering it would change nothing.
    static func isRecommendedSetup(isAvailable: (AppFeature) -> Bool) -> Bool {
        AppFeature.allCases.allSatisfy { isAvailable($0) == essential.features.contains($0) }
    }

    /// The features the preset keeps installed.
    var features: Set<AppFeature> {
        switch self {
        case .essential:
            // SasNotch's recommended setup: the island's core tiles and the
            // first four of the tools beside them. The other tools and every
            // advanced feature wait on the Features page.
            return Set(AppFeature.coreIslandFeatures + AppFeature.recommendedTools)
        case .windows:
            return [.switcher, .windowLayout, .dockPreview, .dockClick, .windowMaximizer]
        case .battery:
            // The lean monitor: battery, memory pressure and the processor,
            // with nothing that listens to input events.
            return [.monitorCPU, .monitorMemory, .monitorPower]
        }
    }

    /// Enable keys switched on along with the install, so the preset's
    /// features actually work instead of arriving as more toggles to find.
    /// Presets whose features are on-demand need none.
    var enableKeys: [String] {
        switch self {
        case .essential:
            // Every core tile shows, and the four tools work, from the start.
            return [DefaultsKey.notchEnabled, DefaultsKey.clipboardHistoryEnabled, DefaultsKey.shelfEnabled,
                    DefaultsKey.notchCalendarEnabled, DefaultsKey.notchNotificationsEnabled,
                    DefaultsKey.notchTimerEnabled, DefaultsKey.notchDownloadsEnabled, DefaultsKey.notchAgentsEnabled,
                    DefaultsKey.switcherEnabled, DefaultsKey.windowLayoutShortcutsEnabled,
                    DefaultsKey.brightnessControlEnabled]
        case .battery:
            return []
        case .windows:
            return [DefaultsKey.switcherEnabled,
                    DefaultsKey.dockPreviewEnabled,
                    DefaultsKey.dockClickMinimize,
                    DefaultsKey.windowMaximizeEnabled]
        }
    }

    var symbolName: String {
        switch self {
        case .essential: return "star.fill"
        case .windows: return "macwindow.on.rectangle"
        case .battery: return "battery.75percent"
        }
    }
}

/// The honest, curated cost label each feature earns in the hub: what the
/// feature keeps alive WHILE IT IS ON. Uninstalled features load nothing at
/// all, which is the hub's own promise. Static by design — pretending to
/// measure per-feature cost live would be theater.
enum FeatureEnergyProfile: String {
    /// Nothing at rest: on-demand tools, shortcut-driven actions and
    /// system-notification listeners.
    case idle
    /// A mouse event tap (scrolls, clicks or pointer moves).
    case mouse
    /// A pointer gesture that works with either a trackpad or mouse.
    case pointer
    /// A keyboard event tap.
    case keyboard
    /// Both input taps.
    case inputs
    /// Samples or polls on an interval while active or visible.
    case periodic
}

extension AppFeature {
    var energyProfile: FeatureEnergyProfile {
        switch self {
        case .scrollInverter, .scrollHorizontal, .focusFollowsMouse, .smoothScroll, .linearScroll, .windowMaximizer, .middleClick,
             .mouseNavigation, .mouseButtonShortcuts, .mouseClickDebounce,
             .dockPreview, .dockClick, .shelf:
            return .mouse
        case .keyboardDebounce, .finderCutPaste, .finderRename, .quitWindowProtection, .musicBlock:
            return .keyboard
        // The switcher's tap also takes clicks and scrolls, and the Super key
        // stamps its modifiers on mouse presses from a second tap.
        case .switcher, .superKey, .textSnippets, .autoQuit:
            return .inputs
        case .windowLayout:
            let edgeSnapRuns = UserDefaults.standard.bool(forKey: DefaultsKey.windowEdgeSnapEnabled)
                && !WindowEdgeSnapZone.enabledZones(
                    from: UserDefaults.standard.string(
                        forKey: DefaultsKey.windowEdgeSnapDisabledZones)
                ).isEmpty
            let pointerTapRuns = UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureEnabled)
                || edgeSnapRuns
            let modifierTapRuns = UserDefaults.standard.bool(forKey: DefaultsKey.windowDirectionalEnabled)
                && UserDefaults.standard.string(forKey: DefaultsKey.windowDirectionalShortcut)
                    .flatMap(WindowDirectionalTrigger.init(storageValue:))
                    .map { if case .modifiers = $0 { return true }; return false } == true
            if modifierTapRuns { return .inputs }
            return pointerTapRuns ? .pointer : .idle
        case .radialMenu:
            // A side button or the trackpad tap on any wheel keeps an input
            // tap running; shortcut-only costs nothing at rest.
            return RadialMenuSupport.opensFromMouseOrTrackpad(
                UserDefaults.standard.data(forKey: DefaultsKey.radialMenuProfiles))
                ? .mouse : .idle
        case .notchNotifications, .notchGestures, .notchTimer, .notchQueue, .notchDownloads: return .idle
        // A command's pipes are read only while it runs; nothing waits between commands.
        case .notchTerminal: return .idle
        // A blink every few seconds and a visit every few minutes, both
        // drawn by Core Animation, with one timer waiting for the next visit.
        case .notchMascot: return .periodic
        case .notchAccessories: return .periodic
        // Log changes arrive as file events; a timer keeps countdowns and
        // limits current while the section is on.
        case .notch, .notchCalendar, .notchLyrics, .notchLiveEqualizer, .notchAgents: return .periodic
        case .clipboardHistory, .urlCleaner, .extraBrightness,
             .monitorCPU, .monitorGPU, .monitorMemory,
             .monitorNetwork, .monitorDisk, .monitorPower, .connectedDevices:
            return .periodic
        case .mixer:
            return UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
                ? .keyboard : .idle
        case .brightness:
            // Following the pointer, the overlay and a finer step answer the
            // brightness keys from a tap. Like Accessibility, the island's own
            // notices are counted under the island.
            let defaults = UserDefaults.standard
            return defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled)
                || defaults.bool(forKey: DefaultsKey.brightnessOSDEnabled)
                || BrightnessSupport.KeyStep.sanitized(
                    defaults.string(forKey: DefaultsKey.brightnessKeyStep)) != .standard
                ? .keyboard : .idle
        case .mouseAcceleration, .spacesOrder, .pastePlain, .soundOutputSwitcher, .audioPriority, .micMute,
             .bluetoothSleep, .keepAwake, .quickLauncher, .quickToggles, .colorPicker,
             .screenOCR, .cleaningMode, .mediaTools, .cleaner, .uninstaller, .homebrew, .screenshot,
             .cameraPreview, .scratchpad, .commandBar, .screenRecorder, .wallpaper, .fanControl,
             .diskImageInstaller, .killProcess, .portManager:
            return .idle
        case .appUpdates:
            // The list is on demand; only a background schedule keeps a timer.
            return AppUpdatesSupport.CheckFrequency.sanitized(
                UserDefaults.standard.string(forKey: DefaultsKey.appUpdatesCheckFrequency)) == .off
                ? .idle : .periodic
        }
    }
}
