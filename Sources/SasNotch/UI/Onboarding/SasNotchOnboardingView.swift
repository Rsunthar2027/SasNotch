// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import AppKit
import EventKit
import SwiftUI

/// SasNotch's first launch: one screen that says what each permission is for
/// and asks for it with one button. Grants show up as they happen, without a
/// relaunch where macOS allows it. Everything stays changeable in Settings.
struct SasNotchOnboardingView: View {
    var onFinish: () -> Void

    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var reminders = NotchRemindersService.shared
    @State private var pollingDemand = UUID()
    @State private var music: Permissions.AutomationStatus = .notDeterminable
    @State private var askingMusic = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(spacing: 10) {
                        row(.accessibility)
                        row(.screenRecording)
                        row(.camera)
                        row(.calendar)
                        row(.reminders)
                        row(.music)
                        row(.notifications)
                    }
                    Text(OnboardingText.footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(28)
            }
            Divider()
            HStack {
                Text(OnboardingText.hoverHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(OnboardingText.done, action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(16)
        }
        .frame(width: 560, height: 640)
        .onAppear {
            // Onboarding explains the permission trip itself.
            PermissionGuideOverlay.suppressed = true
            permissions.setActivePermissionSurface(pollingDemand, visible: true)
            permissions.refresh()
            refreshMusic()
        }
        .onDisappear {
            PermissionGuideOverlay.suppressed = false
            permissions.setActivePermissionSurface(pollingDemand, visible: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            refreshMusic()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            BrandBadge(size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(OnboardingText.title).font(.title.bold())
                Text(OnboardingText.subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    enum Item {
        case accessibility, screenRecording, camera, calendar, reminders, music, notifications
    }

    private func row(_ item: Item) -> some View {
        let state = state(of: item)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(of: item))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title(of: item)).font(.headline)
                Text(reason(of: item))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch state {
            case .granted:
                Label(OnboardingText.allowed, systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout.weight(.semibold))
                    .frame(minWidth: 96, alignment: .trailing)
            case .denied:
                Button(OnboardingText.openSettings) { openSettings(for: item) }
                    .frame(minWidth: 96, alignment: .trailing)
            case .missing:
                Button(OnboardingText.allow) { request(item) }
                    .buttonStyle(.borderedProminent)
                    .disabled(item == .music && askingMusic)
                    .frame(minWidth: 96, alignment: .trailing)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .accessibilityElement(children: .contain)
    }

    private enum GrantState { case granted, denied, missing }

    private func state(of item: Item) -> GrantState {
        switch item {
        case .accessibility: return permissions.accessibility ? .granted : .missing
        case .screenRecording: return permissions.screenRecording ? .granted : .missing
        case .camera:
            switch permissions.camera {
            case .granted: return .granted
            case .denied: return .denied
            default: return .missing
            }
        case .calendar:
            switch permissions.calendarAccess {
            case .fullAccess: return .granted
            case .denied, .restricted: return .denied
            default: return .missing
            }
        case .reminders:
            switch reminders.access {
            case .fullAccess: return .granted
            case .denied, .restricted: return .denied
            default: return .missing
            }
        case .music:
            switch music {
            case .granted: return .granted
            case .denied: return .denied
            default: return .missing
            }
        case .notifications:
            switch permissions.notifications {
            case .granted: return .granted
            case .denied: return .denied
            default: return .missing
            }
        }
    }

    private func request(_ item: Item) {
        switch item {
        case .accessibility: permissions.requestAccessibility()
        case .screenRecording: permissions.requestScreenRecording()
        case .camera: permissions.requestCamera()
        case .calendar: permissions.requestCalendar()
        case .reminders: reminders.requestAccess()
        case .notifications:
            Notifier.requestPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { permissions.refresh() }
        case .music:
            askingMusic = true
            permissions.requestMusicAutomation { status in
                askingMusic = false
                music = status
            }
        }
    }

    private func openSettings(for item: Item) {
        switch item {
        case .accessibility: permissions.openAccessibilitySettings()
        case .screenRecording: permissions.openScreenRecordingSettings()
        case .camera: permissions.openCameraSettings()
        case .calendar: permissions.openCalendarSettings()
        case .reminders: reminders.openSettings()
        case .music: permissions.openAutomationSettings()
        case .notifications: permissions.openNotificationSettings()
        }
    }

    /// Music answers only while it runs; a closed Music keeps the last answer.
    private func refreshMusic() {
        DispatchQueue.global(qos: .utility).async {
            let status = Permissions.automationStatus(for: .music)
            DispatchQueue.main.async {
                if status != .notDeterminable { music = status }
            }
        }
    }

    private func symbol(of item: Item) -> String {
        switch item {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .camera: return "web.camera"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .music: return "music.note"
        case .notifications: return "bell.badge"
        }
    }

    private func title(of item: Item) -> String {
        switch item {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .camera: return "Camera"
        case .calendar: return "Calendar"
        case .reminders: return "Reminders"
        case .music: return "Music"
        case .notifications: return "Notifications"
        }
    }

    private func reason(of item: Item) -> String {
        switch item {
        case .accessibility:
            return "Volume and brightness keys in the island, window snapping, the app switcher and Finder cut and paste."
        case .screenRecording:
            return "Live window thumbnails in the app switcher and Dock previews, and screenshots."
        case .camera:
            return "The Mirror tab. The camera runs only while the Mirror is open and turns off when the island closes."
        case .calendar:
            return "Your next events in the island and on the lock screen. Events never leave your Mac."
        case .reminders:
            return "Reminders due today, under your calendar in the island. Tick them off from there."
        case .music:
            return "Shuffle and track details for the Music app. Playback controls work without it."
        case .notifications:
            return "Timer alerts, finished downloads and other notices from SasNotch."
        }
    }
}

/// Onboarding wording, added by SasNotch. English for now.
enum OnboardingText {
    static let title = "Welcome to SasNotch"
    static let subtitle = "Your notch, with superpowers. Each permission below is optional: allow only what you want to use."
    static let allow = "Allow"
    static let allowed = "Allowed"
    static let openSettings = "Open Settings"
    static let done = "Start Using SasNotch"
    static let hoverHint = "Hover over the notch to open the island. Click it to pin it open."
    static let footnote = "You can change any of these later in System Settings › Privacy & Security, and turn any feature on or off in SasNotch Settings. Screen Recording may need SasNotch to reopen before it takes effect."
}
