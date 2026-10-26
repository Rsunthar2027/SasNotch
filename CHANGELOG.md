# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- The island's Calendar page lists the reminders due today, and overdue ones, under your events. Tick one off to complete it in Reminders. Switch it off in Settings › Dynamic Island › Calendar.
- Reminders joins the first-launch permissions screen.

### Changed
- The installer window is a misty pine forest, with sasquatch footprints leading to the Applications folder.
- The README has a download button for the DMG and step-by-step help for the "Apple could not verify" warning.

## [1.0.0] - 2026-10-26

### Summary
First release of SasNotch: a Dynamic Island for the Mac notch with everyday utilities built in. Requires an Apple Silicon Mac with macOS 14 or later.

### Added
- Island opens on hover after 100 ms and closes when the pointer leaves. A click pins it open; click the pin, click outside or press Esc to close it. Two-finger swipe down opens it, swipe up closes it.
- Music controls with album art, a live visualizer, lyrics and the up-next queue.
- Timers, stopwatch and Pomodoro; calendar events; notifications; download progress; AI agent usage.
- Mirror tab with a live camera preview. The camera stops when the island closes or the tab changes.
- Notices for volume, brightness, charging, Bluetooth devices, Focus changes and camera or microphone use.
- Lock screen widgets: music, timers, calendar, battery while charging, and weather from Open-Meteo.
- Keep Awake with 15 minutes to 8 hours or until turned off, from the island and the menu bar.
- Per-app volume mixer with boost, system monitor, app switcher with live thumbnails, window snapping, Dock previews, clipboard history, text snippets, Finder cut and paste, file shelf, color picker and app uninstaller.
- Island shape settings: width, height and corner radius at rest and open, plus Minimalistic and Standard modes. Liquid Glass on macOS 26; a blurred background on macOS 14 and 15.
- One-screen setup that asks for each permission with its own button.
- Menu bar menu with Settings, Pause Island, Keep Awake, Launch at Login, Check for Updates and Quit.
- Automatic updates through Sparkle, signed with an EdDSA key.

### Credits
SasNotch is derived from [Vorssaint](https://github.com/vorssaint/vorssaint-utils) and [Atoll](https://github.com/Ebullioscopic/Atoll), which builds on [Boring.Notch](https://github.com/TheBoredTeam/boring.notch). All are GPL-3.0.
