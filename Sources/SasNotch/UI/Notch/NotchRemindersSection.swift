// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import SwiftUI

/// Today's reminders under the calendar: overdue first, then by time. A
/// click on the circle completes the reminder in Reminders; the title opens
/// the Reminders app.
struct NotchRemindersSection: View {
    @ObservedObject private var reminders = NotchRemindersService.shared
    @ObservedObject private var l10n = L10n.shared
    /// Rows shown before the list scrolls, so the calendar keeps its room.
    var visibleRows = 4
    private let rowHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { reminders.start() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist").font(.system(size: 11, weight: .semibold))
            Text(RemindersText.title).font(.system(size: 12, weight: .semibold))
            if reminders.hasAccess, !reminders.reminders.isEmpty {
                Text("\(reminders.reminders.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            if reminders.hasAccess {
                Text(RemindersText.today).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var content: some View {
        if !reminders.hasAccess {
            access
        } else if reminders.reminders.isEmpty {
            Text(RemindersText.none)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: rowHeight, alignment: .leading)
        } else {
            let rows = min(reminders.reminders.count, visibleRows)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(reminders.reminders) { row($0) }
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: CGFloat(rows) * (rowHeight + 2))
        }
    }

    private var access: some View {
        HStack(spacing: 8) {
            Text(reminders.access == .denied || reminders.access == .restricted
                 ? RemindersText.denied : RemindersText.allow)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 4)
            if reminders.access == .denied || reminders.access == .restricted {
                Button(RemindersText.openSettings, action: reminders.openSettings)
                    .buttonStyle(NotchButtonStyle(cornerRadius: 8))
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Button(RemindersText.allowButton, action: reminders.requestAccess)
                    .buttonStyle(NotchButtonStyle(cornerRadius: 8))
                    .font(.system(size: 11, weight: .semibold))
                    .disabled(reminders.requesting)
            }
        }
        .frame(height: rowHeight)
    }

    private func row(_ reminder: NotchReminder) -> some View {
        HStack(spacing: 8) {
            Button { reminders.complete(reminder) } label: {
                Circle()
                    .strokeBorder(reminder.color.color, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .contentShape(Circle().inset(by: -4))
            }
            .buttonStyle(.plain)
            .help(RemindersText.complete)
            .accessibilityLabel(RemindersText.complete + ": " + reminder.title)

            Button { reminders.openRemindersApp() } label: {
                HStack(spacing: 6) {
                    Text(reminder.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    trailing(reminder)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .frame(height: rowHeight)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder private func trailing(_ reminder: NotchReminder) -> some View {
        if reminder.overdue {
            Text(reminder.hasTime ? reminder.due.map { Self.time($0) } ?? RemindersText.overdue : RemindersText.overdue)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.red.opacity(0.9))
        } else if reminder.hasTime, let due = reminder.due {
            Text(Self.time(due))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
