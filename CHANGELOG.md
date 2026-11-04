# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-11-03

### Removed
- The Watch feature, its island section and its ⌥⌘O shortcut. Its saved settings are cleared on first launch.

### Added
- Timer presets. A Presets menu under the island timer's clock starts Focus (25 min), Break (5 min) or Deep Work (45 min), and you can add, rename, retime and delete your own: up to 12, from 1 to 180 minutes.
- Selfies in Mirror. A camera button copies the frame on screen to the clipboard, flipped like the preview. A switch in Settings › Dynamic Island › Mirror also saves each one to Downloads.
- A Terminal tab, off by default, under Advanced features (⌥⌘X). It runs one command at a time in your login shell and refuses sudo, su and doas. There's no PTY, so vim, top and anything that asks for input still need Terminal.
- A charge limit notice next to the island's battery settings: off by default, 50–100%, 80% to start. At the limit the island shows a notice and a notification tells you to unplug. SasNotch can't stop your Mac from charging.
- A layered app icon with dark and tinted versions for macOS 26.
- A What's new link next to an available update in Settings, to its notes on the website.

### Changed
- New installs start with a simpler setup: 12 core tiles that stay on, 12 more tools with a switch each, the first four on, and everything else in a collapsed Advanced section. Macs updating from an earlier version keep what they have installed and are asked once whether to switch. Reset to recommended setup is on the Features page.
- On macOS 26 the open island, its tiles and its buttons use Apple's Liquid Glass, Clear by default or Regular, with black only over the camera housing. Reduce Transparency, Increase Contrast and Reduce Motion are each respected.
- Macs on macOS 26 move to Liquid Glass once and are told. A Mac set up on an older macOS is asked once after it upgrades. Before macOS 26 nothing changes.
- With no input, a closed island reads the window list once a second instead of four times. In a debug build, mean CPU went from 0.61% to 0.39%.
- The camera prompt now says a photo is taken only when you press the selfie button.

## [1.1.0] - 2026-10-26

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
