// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import AppKit

/// Names a timer preset and sets its length in a small dialog just above the
/// island, as the Scratchpad page renames a pad. The island keeps no text
/// field of its own for this: it gives up the keyboard whenever it closes.
enum NotchTimerPresetEditor {
    enum Outcome: Equatable {
        case save(NotchTimerPreset)
        case delete
        case cancel
    }

    /// Edits `preset`, or makes a new one starting at `minutes`. Only the
    /// user's own presets come here, so Delete is there whenever one is edited.
    static func run(editing preset: NotchTimerPreset?, minutes: Int, above island: NSWindow?) -> Outcome {
        let form = Form(name: preset?.name ?? "", minutes: preset?.minutes ?? minutes)
        let alert = NSAlert()
        alert.messageText = preset == nil ? TimerPresetText.newTitle : TimerPresetText.editTitle
        alert.informativeText = TimerPresetText.message
        alert.accessoryView = form.view
        alert.addButton(withTitle: TimerPresetText.save)
        // Escape cancels in every language.
        alert.addButton(withTitle: L10n.shared.s.mediaCancel).keyEquivalent = "\u{1b}"
        if preset != nil {
            alert.addButton(withTitle: TimerPresetText.delete).hasDestructiveAction = true
        }
        alert.window.initialFirstResponder = form.nameField
        switch NotchIslandAlert.run(alert, above: island) {
        case .alertFirstButtonReturn:
            return .save(NotchTimerPreset(id: preset?.id ?? UUID().uuidString,
                                          name: form.nameField.stringValue, minutes: form.minutes))
        case .alertThirdButtonReturn:
            return .delete
        default:
            return .cancel
        }
    }

    /// The name, and the minutes as a field with a stepper beside it that
    /// follow each other.
    private final class Form: NSObject, NSTextFieldDelegate {
        let nameField: NSTextField
        let view: NSView
        private let minutesField: NSTextField
        private let stepper = NSStepper()

        init(name: String, minutes: Int) {
            let range = NotchTimerPresets.minuteRange
            let start = NotchTimerPresets.validatedMinutes(minutes)
            nameField = NSTextField(string: name)
            nameField.placeholderString = TimerPresetText.fallbackName
            nameField.setAccessibilityLabel(TimerPresetText.name)
            minutesField = NSTextField(string: String(start))
            minutesField.alignment = .right
            minutesField.setAccessibilityLabel(TimerPresetText.minutes)
            stepper.minValue = Double(range.lowerBound)
            stepper.maxValue = Double(range.upperBound)
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.integerValue = start
            stepper.setAccessibilityLabel(TimerPresetText.minutes)

            let minutesRow = NSStackView(views: [minutesField, stepper])
            minutesRow.spacing = 4
            let grid = NSGridView(views: [
                [NSTextField(labelWithString: TimerPresetText.name), nameField],
                [NSTextField(labelWithString: TimerPresetText.minutes), minutesRow],
            ])
            grid.rowSpacing = 8
            grid.columnSpacing = 8
            grid.rowAlignment = .firstBaseline
            grid.column(at: 0).xPlacement = .trailing
            NSLayoutConstraint.activate([
                nameField.widthAnchor.constraint(equalToConstant: 180),
                minutesField.widthAnchor.constraint(equalToConstant: 52),
            ])
            grid.frame = NSRect(origin: .zero, size: grid.fittingSize)
            view = grid
            super.init()
            minutesField.delegate = self
            stepper.target = self
            stepper.action = #selector(stepped(_:))
        }

        /// What the field reads, or the stepper's value when it reads no number.
        var minutes: Int {
            NotchTimerPresets.minutes(from: minutesField.stringValue) ?? stepper.integerValue
        }

        @objc private func stepped(_ sender: NSStepper) {
            minutesField.stringValue = String(sender.integerValue)
        }

        func controlTextDidChange(_ notification: Notification) {
            if let value = NotchTimerPresets.minutes(from: minutesField.stringValue) {
                stepper.integerValue = value
            }
        }
    }
}
