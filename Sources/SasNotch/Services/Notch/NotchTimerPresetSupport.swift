// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// A named countdown the Timer tab starts in one tap. Every way in, the
/// initializer and the decoder alike, leaves the name and the length valid.
struct NotchTimerPreset: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let minutes: Int

    init(id: String = UUID().uuidString, name: String, minutes: Int) {
        self.id = id
        self.name = NotchTimerPresets.validatedName(name)
        self.minutes = NotchTimerPresets.validatedMinutes(minutes)
    }

    var isBuiltIn: Bool { NotchTimerPresets.isBuiltIn(id) }

    private enum CodingKeys: String, CodingKey { case id, name, minutes }

    /// A preset needs an id and a whole number of minutes. A missing or odd
    /// name falls back like a typed one; anything else is not a preset.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "empty preset id")
        }
        let name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.init(id: id, name: name, minutes: try container.decode(Int.self, forKey: .minutes))
    }
}

/// The presets the Timer tab offers: three built in, which never change and
/// are never stored, then the user's own, saved as JSON.
enum NotchTimerPresets {
    /// The timer's own range, so a preset never asks for a countdown the
    /// ruler could not set.
    static let minuteRange = 1...180
    /// Long enough for a real name, short enough for the island's top row.
    static let nameLimit = 24
    /// Enough for anyone's routine while the menu stays a menu.
    static let customLimit = 12

    static let builtIns = [
        NotchTimerPreset(id: "builtin.focus", name: TimerPresetText.focus, minutes: 25),
        NotchTimerPreset(id: "builtin.break", name: TimerPresetText.breakName, minutes: 5),
        NotchTimerPreset(id: "builtin.deepWork", name: TimerPresetText.deepWork, minutes: 45),
    ]

    static func isBuiltIn(_ id: String) -> Bool { builtIns.contains { $0.id == id } }

    /// One line, trimmed and cut to the limit; nothing left reads "Timer".
    static func validatedName(_ raw: String) -> String {
        let line = raw.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(line.prefix(nameLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? TimerPresetText.fallbackName : name
    }

    static func validatedMinutes(_ raw: Int) -> Int {
        min(minuteRange.upperBound, max(minuteRange.lowerBound, raw))
    }

    /// Minutes as typed: the leading digits, so "25 min" reads 25, held to
    /// the range. Nil when the text starts with no digit at all.
    static func minutes(from text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix { ("0"..."9").contains($0) }
        guard !digits.isEmpty else { return nil }
        // Too many digits for an Int is still a long time.
        return validatedMinutes(Int(digits) ?? minuteRange.upperBound)
    }

    // MARK: Storage

    /// Whatever is stored, the result is a list the menu can show: bad JSON,
    /// another type or an older shape decode as no presets, a broken entry
    /// is skipped on its own, and an id that repeats or names a built-in
    /// preset keeps only its first valid use.
    static func decode(_ data: Data?) -> [NotchTimerPreset] {
        guard let data, !data.isEmpty,
              let entries = try? JSONDecoder().decode([LossyPreset].self, from: data) else { return [] }
        var seen = Set(builtIns.map(\.id))
        var presets: [NotchTimerPreset] = []
        for preset in entries.compactMap(\.preset) where presets.count < customLimit {
            if seen.insert(preset.id).inserted { presets.append(preset) }
        }
        return presets
    }

    /// Only the user's own presets are written; the built-in ones stay in code.
    static func encode(_ presets: [NotchTimerPreset]) -> Data {
        let custom = Array(presets.filter { !$0.isBuiltIn }.prefix(customLimit))
        return (try? JSONEncoder().encode(custom)) ?? Data()
    }

    static func custom(in defaults: UserDefaults = .standard) -> [NotchTimerPreset] {
        decode(defaults.data(forKey: DefaultsKey.notchTimerPresets))
    }

    static func all(in defaults: UserDefaults = .standard) -> [NotchTimerPreset] {
        builtIns + custom(in: defaults)
    }

    static func save(_ presets: [NotchTimerPreset], in defaults: UserDefaults = .standard) {
        defaults.set(encode(presets), forKey: DefaultsKey.notchTimerPresets)
    }

    // MARK: Editing

    static func canAdd(to presets: [NotchTimerPreset]) -> Bool {
        presets.filter { !$0.isBuiltIn }.count < customLimit
    }

    /// The list with `preset` saved: an edit stays where it was, a new one
    /// goes last while there is room. A built-in preset cannot be changed.
    static func saving(_ preset: NotchTimerPreset, in presets: [NotchTimerPreset]) -> [NotchTimerPreset] {
        guard !preset.isBuiltIn else { return presets }
        var result = presets
        if let index = result.firstIndex(where: { $0.id == preset.id }) {
            result[index] = preset
        } else if canAdd(to: result) {
            result.append(preset)
        }
        return result
    }

    /// The list without `id`. Built-in presets stay.
    static func deleting(_ id: String, from presets: [NotchTimerPreset]) -> [NotchTimerPreset] {
        guard !isBuiltIn(id) else { return presets }
        return presets.filter { $0.id != id }
    }

    /// One entry that may fail on its own without failing the list.
    private struct LossyPreset: Decodable {
        let preset: NotchTimerPreset?
        init(from decoder: Decoder) throws { preset = try? NotchTimerPreset(from: decoder) }
    }
}

/// Timer preset wording added by SasNotch. English for now.
enum TimerPresetText {
    static let focus = "Focus"
    static let breakName = "Break"
    static let deepWork = "Deep Work"
    static let fallbackName = "Timer"
    static let presets = "Presets"
    static let presetsHint = "Start a preset, or save your own"
    static let newPreset = "New Preset…"
    static let editPreset = "Edit Preset"
    static let newTitle = "New Timer Preset"
    static let editTitle = "Edit Timer Preset"
    static let message = "A name and a length from 1 to 180 minutes."
    static let name = "Name"
    static let minutes = "Minutes"
    static let save = "Save"
    static let delete = "Delete"
    static func menuTitle(_ name: String, _ length: String) -> String { "\(name) · \(length)" }
}
