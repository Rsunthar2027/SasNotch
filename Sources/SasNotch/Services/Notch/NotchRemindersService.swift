// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import AppKit
import EventKit

/// A reminder in the island's Today list.
struct NotchReminder: Identifiable, Equatable {
    let id: String
    let title: String
    let list: String
    let due: Date?
    /// The time of day was set, not just the day.
    let hasTime: Bool
    let overdue: Bool
    let color: NotchCalendarColor
}

/// The Reminders app's Today list for the Calendar page: open reminders due
/// today or overdue, as Reminders' own Today list shows them. A reminder can
/// be ticked off from the island. Main thread only, like the island.
final class NotchRemindersService: ObservableObject, @unchecked Sendable {
    static let shared = NotchRemindersService()

    @Published private(set) var reminders: [NotchReminder] = []
    @Published private(set) var access = EKEventStore.authorizationStatus(for: .reminder)
    @Published private(set) var requesting = false

    private let store = EKEventStore()
    private var observers: [NSObjectProtocol] = []
    private var running = false

    private init() {}

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchCalendarSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchRemindersEnabled)
    }

    var hasAccess: Bool { access == .fullAccess }

    func syncWithPreferences() {
        Self.isEnabled() ? start() : stop()
    }

    func start() {
        access = EKEventStore.authorizationStatus(for: .reminder)
        guard !running else { refresh(); return }
        running = true
        for name in [Notification.Name.EKEventStoreChanged, NSApplication.didBecomeActiveNotification,
                     .NSCalendarDayChanged, .NSSystemClockDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.refresh()
            })
        }
        refresh()
    }

    func stop() {
        running = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if !reminders.isEmpty { reminders = [] }
    }

    func requestAccess() {
        guard !requesting else { return }
        requesting = true
        store.requestFullAccessToReminders { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requesting = false
                self.access = EKEventStore.authorizationStatus(for: .reminder)
                self.refresh()
            }
        }
    }

    func refresh() {
        access = EKEventStore.authorizationStatus(for: .reminder)
        guard running, hasAccess else {
            if !reminders.isEmpty { reminders = [] }
            return
        }
        let now = Date()
        let calendar = Calendar.current
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday,
                                                             calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] found in
            let items = NotchRemindersSupport.today(found ?? [], now: now, calendar: calendar)
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                if self.reminders != items { self.reminders = items }
            }
        }
    }

    /// Ticks a reminder off in Reminders itself.
    func complete(_ reminder: NotchReminder) {
        guard hasAccess, let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        do {
            try store.save(item, commit: true)
            reminders.removeAll { $0.id == reminder.id }
        } catch {
            refresh()
        }
    }

    func openRemindersApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
        NSWorkspace.shared.open(url)
    }
}

enum NotchRemindersSupport {
    /// Open reminders due by the end of today, overdue first, then by time,
    /// with reminders due "today" without a time after the timed ones.
    static func today(_ found: [EKReminder], now: Date, calendar: Calendar) -> [NotchReminder] {
        let startOfToday = calendar.startOfDay(for: now)
        let items: [NotchReminder] = found.compactMap { reminder in
            guard !reminder.isCompleted, let components = reminder.dueDateComponents,
                  let due = calendar.date(from: components) else { return nil }
            let hasTime = components.hour != nil
            let overdue = hasTime ? due < now : due < startOfToday
            let tint = reminder.calendar?.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
            return NotchReminder(id: reminder.calendarItemIdentifier,
                                 title: reminder.title?.isEmpty == false ? reminder.title! : "Untitled",
                                 list: reminder.calendar?.title ?? "", due: due, hasTime: hasTime,
                                 overdue: overdue,
                                 color: tint.map { NotchCalendarColor(red: $0.redComponent, green: $0.greenComponent,
                                                                      blue: $0.blueComponent) } ?? .fallback)
        }
        return order(items)
    }

    static func order(_ items: [NotchReminder]) -> [NotchReminder] {
        items.sorted { a, b in
            if a.overdue != b.overdue { return a.overdue }
            if a.hasTime != b.hasTime { return a.hasTime }
            if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}

/// Reminders wording, added by SasNotch. English for now.
enum RemindersText {
    static let title = "Reminders"
    static let today = "Due today"
    static let none = "Nothing due today"
    static let allow = "Show today's reminders"
    static let allowButton = "Allow"
    static let denied = "Reminders access is off."
    static let openSettings = "Open Settings"
    static let overdue = "Overdue"
    static let complete = "Mark as completed"
    static let settingsToggle = "Show today's reminders"
    static let settingsCaption = "Lists open reminders due today, and overdue ones, below your calendar. Tick one off to complete it in Reminders."
}
