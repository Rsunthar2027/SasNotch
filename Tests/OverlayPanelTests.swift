// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Modified for SasNotch by SasNotch contributors, 2026

import AppKit

/// AppKit describes a non-activating panel as a system dialog, which tiling
/// window managers track and list on whichever space is current. The shared
/// panel class is compiled here and created deferred, so no window is shown;
/// each floating surface's own file is read for the class it builds.
enum OverlayPanelTests {
    static func run(_ suite: TestSuite) {
        // The Clipboard History window keeps a title bar strip to drag it by.
        for style: NSWindow.StyleMask in [[.borderless, .nonactivatingPanel],
                                          [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]] {
            let overlay = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                                       styleMask: style, backing: .buffered, defer: true)
            suite.expect(overlay.accessibilitySubrole() == .unknown,
                         "a floating overlay describes itself as an undescribed window, so window managers skip it")
            suite.expect(overlay.accessibilityRole() == .window && overlay.isAccessibilityElement(),
                         "a floating overlay stays an accessible window for assistive technology")
        }

        // HUDs, previews, pickers and the menu's positioning helper: none is a
        // document window, and each floats over other apps' windows.
        let surfaces = [
            "Sources/SasNotch/App/AppDelegate.swift",
            "Sources/SasNotch/UI/PermissionGuideOverlay.swift",
            "Sources/SasNotch/UI/QuitProtection/QuitProtectionHUD.swift",
            "Sources/SasNotch/Services/QuickTools/QuickToolHUD.swift",
            "Sources/SasNotch/Services/QuickTools/QuickLauncherService.swift",
            "Sources/SasNotch/Services/QuickTools/CameraPreviewService.swift",
            "Sources/SasNotch/Services/QuickTools/RecentCaptureService.swift",
            "Sources/SasNotch/Services/QuickTools/ScreenshotSelectionController.swift",
            "Sources/SasNotch/Services/QuickTools/ScreenshotQuickPreviewController.swift",
            "Sources/SasNotch/Services/QuickTools/ScreenshotPinController.swift",
            "Sources/SasNotch/Services/QuickTools/QRResultController.swift",
            "Sources/SasNotch/Services/QuickTools/ScratchpadService.swift",
            "Sources/SasNotch/Services/Snippets/SnippetLibraryService.swift",
            "Sources/SasNotch/Services/Clipboard/ClipboardHistoryService.swift",
            "Sources/SasNotch/Services/CommandBar/CommandBarService.swift",
            "Sources/SasNotch/Services/Switcher/AppSwitcher.swift",
            "Sources/SasNotch/Services/RadialMenu/RadialMenuService.swift",
            "Sources/SasNotch/Services/RadialMenu/RadialNowPlayingService.swift",
            "Sources/SasNotch/Services/DockPreview/DockPreviewService.swift",
            "Sources/SasNotch/Services/WindowLayout/WindowLayoutService.swift",
            "Sources/SasNotch/Services/DiskImageInstaller/DiskImageInstallerService.swift",
            "Sources/SasNotch/Services/Finder/FinderCutPaste.swift",
            "Sources/SasNotch/Services/Display/BrightnessOSD.swift",
            "Sources/SasNotch/Services/CleaningMode/CleaningModeManager.swift",
            "Sources/SasNotch/Services/Recorder/RecorderIndicator.swift",
        ]
        for path in surfaces {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(source.range(of: #"\bOverlayPanel\(contentRect|:\s*OverlayPanel\b"#,
                                      options: .regularExpression) != nil
                         && !source.contains("NSPanel(contentRect")
                         && source.range(of: #"class \w+:\s*NSPanel\b"#, options: .regularExpression) == nil,
                         "\(path) builds its floating panels as overlays, which window managers do not list")
        }
    }
}
