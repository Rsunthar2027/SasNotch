// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

enum NotchTimerPresetTests {
    static func run(_ suite: TestSuite) {
        builtInContracts(suite)
        validationContracts(suite)
        typedMinutesContracts(suite)
        codingContracts(suite)
        corruptDataContracts(suite)
        storageContracts(suite)
        editingContracts(suite)
        sessionLabelContracts(suite)
    }

    private static func json(_ text: String) -> Data { Data(text.utf8) }

    private static func builtInContracts(_ suite: TestSuite) {
        let builtIns = NotchTimerPresets.builtIns
        suite.expect(builtIns.map(\.name) == ["Focus", "Break", "Deep Work"]
                     && builtIns.map(\.minutes) == [25, 5, 45],
                     "the built-in presets are Focus 25, Break 5 and Deep Work 45 minutes, in that order")
        suite.expect(builtIns.allSatisfy(\.isBuiltIn) && Set(builtIns.map(\.id)).count == builtIns.count,
                     "each built-in preset has its own fixed id")
        suite.expect(!NotchTimerPreset(name: "Reading", minutes: 20).isBuiltIn,
                     "a new preset is the user's own")
        withDefaults("all") { defaults in
            suite.expect(NotchTimerPresets.all(in: defaults) == builtIns,
                         "with nothing saved the menu offers just the built-in presets")
        }
    }

    private static func validationContracts(_ suite: TestSuite) {
        suite.expect(NotchTimerPresets.validatedName("  Reading \n") == "Reading", "a name is trimmed")
        suite.expect(NotchTimerPresets.validatedName("") == "Timer"
                     && NotchTimerPresets.validatedName(" \n\t  ") == "Timer",
                     "an empty or blank name falls back to Timer")
        suite.expect(NotchTimerPresets.validatedName("Deep\nWork\tblock") == "Deep Work block",
                     "a name is kept to one line")
        let long = NotchTimerPresets.validatedName(String(repeating: "a", count: 40))
        suite.expect(long.count == NotchTimerPresets.nameLimit, "a long name is cut to the limit")
        let spaced = NotchTimerPresets.validatedName(String(repeating: "b", count: 23) + "   tail")
        suite.expect(spaced == String(repeating: "b", count: 23), "a cut name loses the space it ends on")
        suite.expect(NotchTimerPreset(name: "  ", minutes: 10).name == "Timer",
                     "the initializer validates the name too")

        let minutes = [(Int.min, 1), (-5, 1), (0, 1), (1, 1), (25, 25), (180, 180), (181, 180), (Int.max, 180)]
        suite.expect(minutes.allSatisfy { NotchTimerPresets.validatedMinutes($0.0) == $0.1 },
                     "a preset lasts from 1 to 180 minutes")
        suite.expect(NotchTimerPreset(name: "Long", minutes: 500).minutes == 180
                     && NotchTimerPreset(name: "Short", minutes: 0).minutes == 1,
                     "the initializer holds the length to the range")
        suite.expect(NotchTimerPresets.minuteRange.upperBound * 60 == Int(NotchTimerSupport.timerLimit)
                     && [-3, 0, 1, 90, 180, 900].allSatisfy {
                         NotchTimerPresets.validatedMinutes($0) == NotchTimerSupport.timerMinutes($0)
                     },
                     "presets keep the timer's own 180 minute cap")
    }

    private static func typedMinutesContracts(_ suite: TestSuite) {
        let cases: [(String, Int?)] = [
            ("25", 25), (" 30 ", 30), ("25 min", 25), ("0", 1), ("999", 180),
            ("99999999999999999999999", 180), ("", nil), ("   ", nil), ("abc", nil), ("-5", nil),
        ]
        for (text, expected) in cases {
            suite.expect(NotchTimerPresets.minutes(from: text) == expected,
                         "typed minutes \"\(text)\" read as \(expected.map(String.init) ?? "nothing")")
        }
    }

    private static func codingContracts(_ suite: TestSuite) {
        let custom = [NotchTimerPreset(id: "a", name: "Reading", minutes: 20),
                      NotchTimerPreset(id: "b", name: "Tea", minutes: 3)]
        suite.expect(NotchTimerPresets.decode(NotchTimerPresets.encode(custom)) == custom,
                     "custom presets survive an encode and decode unchanged")
        suite.expect(NotchTimerPresets.decode(NotchTimerPresets.encode(NotchTimerPresets.builtIns + custom)) == custom,
                     "the built-in presets are never stored")
        let many = (0..<20).map { NotchTimerPreset(id: "p\($0)", name: "P\($0)", minutes: $0 + 1) }
        suite.expect(NotchTimerPresets.decode(NotchTimerPresets.encode(many)) == Array(many.prefix(NotchTimerPresets.customLimit)),
                     "no more presets are stored than the menu holds")
        suite.expect(NotchTimerPresets.decode(NotchTimerPresets.encode([])) == [],
                     "an empty list stays empty")
        let future = json(#"[{"id":"x","name":"Run","minutes":30,"color":"red","version":3}]"#)
        suite.expect(NotchTimerPresets.decode(future) == [NotchTimerPreset(id: "x", name: "Run", minutes: 30)],
                     "fields a later version adds are ignored")
    }

    private static func corruptDataContracts(_ suite: TestSuite) {
        let unreadable: [(String, Data?)] = [
            ("nothing", nil), ("empty data", Data()), ("bytes", Data([0xFF, 0x00, 0x13, 0x37])),
            ("cut JSON", json(#"[{"id":"a","name":"A","min"#)), ("an object", json(#"{"id":"a","minutes":5}"#)),
            ("a string", json(#""Focus""#)), ("a number", json("25")), ("null", json("null")),
            ("not presets", json(#"[1, "x", null, true, []]"#)),
        ]
        for (name, data) in unreadable {
            suite.expect(NotchTimerPresets.decode(data).isEmpty, "\(name) decodes as no presets")
        }

        let mixed = json("""
            [{"id":"a","name":"A","minutes":10},
             {"id":"b"},
             {"name":"no id","minutes":5},
             {"id":"","minutes":5},
             {"id":"   ","minutes":5},
             {"id":"c","name":"  ","minutes":999},
             {"id":"d","name":"Fraction","minutes":12.5},
             {"id":"e","name":"Text","minutes":"15"},
             {"id":"f","minutes":7},
             {"id":"g","name":42,"minutes":8},
             {"id":"a","name":"Again","minutes":11},
             {"id":"builtin.focus","name":"Shadow","minutes":50},
             42]
            """)
        suite.expect(NotchTimerPresets.decode(mixed) == [
            NotchTimerPreset(id: "a", name: "A", minutes: 10),
            NotchTimerPreset(id: "c", name: "Timer", minutes: 180),
            NotchTimerPreset(id: "f", name: "Timer", minutes: 7),
            NotchTimerPreset(id: "g", name: "Timer", minutes: 8),
        ], "a broken entry, a repeated id or a built-in id is skipped on its own and the rest are made valid")
    }

    private static func storageContracts(_ suite: TestSuite) {
        let registered = Defaults.registeredDefaults[DefaultsKey.notchTimerPresets] as? Data
        suite.expect(registered == Data(), "custom presets default to none")
        suite.expect(NotchTimerPresets.decode(registered).isEmpty, "the registered default decodes as no presets")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchTimerPresets),
                     "custom presets travel in settings backup")

        withDefaults("storage") { defaults in
            suite.expect(NotchTimerPresets.custom(in: defaults).isEmpty, "nothing saved reads as no presets")
            let saved = [NotchTimerPreset(id: "a", name: "Reading", minutes: 20)]
            NotchTimerPresets.save(saved, in: defaults)
            suite.expect(NotchTimerPresets.custom(in: defaults) == saved
                         && NotchTimerPresets.all(in: defaults) == NotchTimerPresets.builtIns + saved,
                         "saved presets follow the built-in ones")
            defaults.set(Data("not json".utf8), forKey: DefaultsKey.notchTimerPresets)
            suite.expect(NotchTimerPresets.custom(in: defaults).isEmpty, "corrupt stored data reads as no presets")
            defaults.set("a string", forKey: DefaultsKey.notchTimerPresets)
            suite.expect(NotchTimerPresets.custom(in: defaults).isEmpty, "a value of another type reads as no presets")
            defaults.set(42, forKey: DefaultsKey.notchTimerPresets)
            suite.expect(NotchTimerPresets.all(in: defaults) == NotchTimerPresets.builtIns,
                         "the built-in presets stay whatever is stored")
        }
    }

    private static func editingContracts(_ suite: TestSuite) {
        let reading = NotchTimerPreset(id: "a", name: "Reading", minutes: 20)
        let tea = NotchTimerPreset(id: "b", name: "Tea", minutes: 3)
        var list = NotchTimerPresets.saving(reading, in: [])
        list = NotchTimerPresets.saving(tea, in: list)
        suite.expect(list == [reading, tea], "a new preset goes last")
        let renamed = NotchTimerPreset(id: "a", name: "Novel", minutes: 35)
        suite.expect(NotchTimerPresets.saving(renamed, in: list) == [renamed, tea],
                     "an edit keeps the preset's place and changes its name and length")
        let focus = NotchTimerPresets.builtIns[0]
        let changedFocus = NotchTimerPreset(id: focus.id, name: "Mine", minutes: 50)
        suite.expect(NotchTimerPresets.saving(changedFocus, in: list) == list,
                     "a built-in preset cannot be changed")
        suite.expect(NotchTimerPresets.deleting("a", from: list) == [tea], "deleting removes only that preset")
        suite.expect(NotchTimerPresets.deleting(focus.id, from: NotchTimerPresets.builtIns + list)
                         == NotchTimerPresets.builtIns + list,
                     "a built-in preset cannot be deleted")
        suite.expect(NotchTimerPresets.deleting("missing", from: list) == list, "deleting an unknown id changes nothing")

        let full = (0..<NotchTimerPresets.customLimit).map { NotchTimerPreset(id: "p\($0)", name: "P\($0)", minutes: 10) }
        suite.expect(NotchTimerPresets.canAdd(to: list) && !NotchTimerPresets.canAdd(to: full),
                     "presets can be added until the menu is full")
        suite.expect(NotchTimerPresets.canAdd(to: NotchTimerPresets.builtIns + list),
                     "built-in presets do not count against the limit")
        suite.expect(NotchTimerPresets.saving(reading, in: full) == full,
                     "a full list takes no new preset")
        let edited = NotchTimerPreset(id: "p3", name: "Edited", minutes: 12)
        suite.expect(NotchTimerPresets.saving(edited, in: full)[3] == edited,
                     "a full list still takes an edit")
    }

    private static func sessionLabelContracts(_ suite: TestSuite) {
        let text = FeatureStrings.notchActivities(.enUS)
        var session = NotchTimerSession()
        let deepWork = NotchTimerPresets.builtIns[2]
        session.start(mode: .timer, minutes: deepWork.minutes, now: 100, label: deepWork.name)
        suite.expect(session.label == "Deep Work" && session.reading(at: 100) == 45 * 60,
                     "a preset starts a countdown of its length named after it")
        suite.expect(NotchTimerSupport.title(for: session, text: text) == "Deep Work",
                     "a labelled countdown shows its name in place of the phase")
        session.finishIfDue(at: 100 + 45 * 60)
        suite.expect(session.completed && session.label == "Deep Work", "a finished countdown keeps its name")
        session.cancel()
        suite.expect(session.label == nil && NotchTimerSupport.title(for: session, text: text) == text.timer,
                     "dismissing it clears the name")

        var plain = NotchTimerSession()
        plain.start(mode: .timer, minutes: 15, now: 0)
        suite.expect(plain.label == nil && NotchTimerSupport.title(for: plain, text: text) == text.phase(.timer),
                     "a countdown started from the ruler has no name")
        var blank = NotchTimerSession()
        blank.start(mode: .timer, minutes: 15, now: 0, label: "  \n")
        suite.expect(blank.label == nil, "a blank name is no name")
        var pomodoro = NotchTimerSession()
        pomodoro.start(mode: .pomodoro, minutes: 25, now: 0, label: "Focus")
        suite.expect(pomodoro.label == nil && NotchTimerSupport.title(for: pomodoro, text: text) == text.focus,
                     "only a plain countdown takes a name")
        var stopwatch = NotchTimerSession()
        stopwatch.start(mode: .stopwatch, minutes: 0, now: 0, label: "Run")
        suite.expect(stopwatch.label == nil, "a stopwatch takes no name")
    }

    private static func withDefaults(_ name: String, _ body: (UserDefaults) -> Void) {
        let domain = "com.sasnotch.tests.timer-presets.\(name)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        body(defaults)
    }
}
