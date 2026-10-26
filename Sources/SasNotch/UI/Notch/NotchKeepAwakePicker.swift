// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import SwiftUI

/// Keep Awake from the island: pick how long, see the time left, add time or
/// stop, without a trip to Settings. The Controls tile and the Keep Awake
/// circle both open it.
struct NotchKeepAwakePicker: View {
    var dismiss: () -> Void

    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var l10n = L10n.shared

    /// Minutes, with zero meaning until it is turned off, as KeepAwakeManager reads them.
    private var options: [(title: String, minutes: Int)] {
        let s = l10n.s
        return [(s.minutes15, 15), (s.minutes30, 30), (s.hour1, 60),
                (s.hours2, 120), (s.hours4, 240), (s.hours8, 480), (s.indefinitely, 0)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(awake.isActive ? .orange : .secondary)
                Text(l10n.s.keepAwakeTitle).font(.headline)
                Spacer(minLength: 8)
                status
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(options, id: \.minutes) { option in
                    let current = awake.isActive && awake.sessionMinutes == option.minutes
                        && (option.minutes == 0) == (awake.endDate == nil)
                    Button {
                        awake.activate(minutes: option.minutes)
                        dismiss()
                    } label: {
                        Text(option.title)
                            .font(.callout.weight(current ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 26)
                    }
                    .buttonStyle(.bordered)
                    .tint(current ? .orange : nil)
                    .accessibilityAddTraits(current ? .isSelected : [])
                }
            }
            if awake.isActive {
                HStack {
                    if awake.endDate != nil {
                        Button(KeepAwakeText.addThirty) { awake.extend(minutes: 30) }
                    }
                    Spacer()
                    Button(l10n.s.menuDisableAwake) {
                        awake.toggle()
                        dismiss()
                    }
                    .tint(.red)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private var status: some View {
        if awake.isActive {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(awake.endDate.map {
                    KeepAwakeText.left(NotchKeepAwakeSupport.compactText(until: $0, now: context.date,
                                                                         locale: Locale(identifier: l10n.language.rawValue)))
                } ?? KeepAwakeText.untilOff)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        } else {
            Text(KeepAwakeText.off).font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// Keep Awake wording added by SasNotch. English for now.
enum KeepAwakeText {
    static let addThirty = "+30 min"
    static let off = "Off"
    static let untilOff = "On until turned off"
    static func left(_ time: String) -> String { "\(time) left" }
    static let menuTitle = "Keep Awake"
    static let menuFor = "Keep Awake For"
}
