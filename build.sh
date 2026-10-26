#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
# Modified for SasNotch by SasNotch contributors, 2026

# Builds SasNotch, assembles the .app bundle, signs it and (with --install)
# installs it into /Applications.
#
# The bundle is staged in a temporary directory outside ~/Documents: folders synced
# by File Provider gain xattrs (com.apple.provenance etc.) that invalidate codesign.
set -euo pipefail
cd "$(dirname "$0")"

# The icon catalog and the bundle are staged in temp dirs; sweep both however
# the script ends.
ICON_TMP=""
STAGE_TMP=""

cleanup() {
    [[ -n "$ICON_TMP" ]] && rm -rf "$ICON_TMP"
    [[ -n "$STAGE_TMP" ]] && rm -rf "$STAGE_TMP"
    return 0
}
trap cleanup EXIT
# zsh runs the EXIT trap when the script is hung up, but not when it is
# interrupted or terminated; route those through exit so a Ctrl-C partway
# into the build sweeps like any other ending.
trap 'exit 1' INT TERM HUP

# Flags: --dev builds the local-only "SasNotch (Developer)" variant (its own
# bundle id, so it coexists with the official app); --install puts it in /Applications.
DEV=0
INSTALL=0
TEST=0
TEST_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dev)     DEV=1 ;;
        --install) INSTALL=1 ;;
        --test)    TEST=1 ;;
        --test-suite=*) TEST=1; TEST_ARGS+=("--suite=${arg#*=}") ;;
        --list-tests) TEST=1; TEST_ARGS+=(--list) ;;
    esac
done

if (( DEV )); then
    APP_NAME="SasNotch (Developer)"
    EXECUTABLE="SasNotchDeveloper"
    APP_BUNDLE_ID="com.sasnotch.app.dev"
    BUILD_VARIANT_FLAGS=(-D SASNOTCH_DEVELOPMENT)
    APP_OPTIMIZATION_FLAGS=(-Onone)
    BUILD_CONFIGURATION="debug"
else
    APP_NAME="SasNotch"
    EXECUTABLE="SasNotch"
    APP_BUNDLE_ID="com.sasnotch.app"
    BUILD_VARIANT_FLAGS=()
    APP_OPTIMIZATION_FLAGS=(-O)
    BUILD_CONFIGURATION="release"
fi
FAN_HELPER_ID="$APP_BUNDLE_ID.fan-control"
# Now Playing is read through /usr/bin/perl loading this library; see
# Sources/NowPlayingAdapter. Staged under Contents/Frameworks, signed on its own.
NOW_PLAYING_ADAPTER_ID="$APP_BUNDLE_ID.now-playing"
NOW_PLAYING_ADAPTER="libSasNotchNowPlaying.dylib"
TARGET="arm64-apple-macosx14.0"
ENTITLEMENTS="Resources/SasNotch.entitlements"
LEGACY_IDENTITY="SasNotch Self-Signed"

developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' \
        | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true
}

# A find-identity listing also names certificates codesign then rejects (an
# expired one fails the build with errSecInternalComponent), and -v excludes
# every self-signed one; ask codesign itself with a throwaway copy of /bin/echo.
legacy_identity_installed() {
    local probe signed=1
    # A locked keychain still lists its identities but cannot sign with them,
    # and this one is locked after every reboot; unlock it before asking.
    security unlock-keychain -p sasnotch-signing \
        "$HOME/Library/Keychains/sasnotch-signing.keychain-db" 2>/dev/null || true
    probe="$(mktemp)"
    cp /bin/echo "$probe"
    /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$probe" \
        >/dev/null 2>&1 && signed=0
    rm -f "$probe"
    return $signed
}

# Any build that lands in /Applications needs a stable signature, not just the
# Developer one: macOS ties Accessibility and Screen Recording grants to the
# exact binary hash, so an ad-hoc rebuild orphans them while System Settings
# keeps showing them as granted, and no new prompt ever appears. A plain
# --install strands them under the released bundle id, on the app the user
# actually relies on. When no identity is installed, create the stable local one
# up front instead of falling through to ad-hoc — setup-signing.sh is free,
# offline and idempotent. Gating on the install rather than the variant keeps
# this off CI, where neither ci.yml nor release.yml passes --install.
if (( DEV || INSTALL )) && [[ -z "$(developer_id_identity)" ]] \
    && ! legacy_identity_installed && [[ "${SASNOTCH_SKIP_SIGNING_SETUP:-0}" != "1" ]]; then
    echo "▸ No signing identity installed; creating the stable local one…"
    if ! ./Tools/setup-signing.sh; then
        echo "  ⚠ Tools/setup-signing.sh failed; signing ad-hoc instead." >&2
        echo "    Accessibility and Screen Recording grants will not survive rebuilds:" >&2
        echo "    System Settings will show them as granted while the app is not trusted." >&2
        echo "    After fixing the identity, clear the stale grant once with:" >&2
        echo "      tccutil reset Accessibility $APP_BUNDLE_ID" >&2
    fi
fi

codesign_with_timestamp_retry() {
    local attempt
    for attempt in 1 2 3; do
        if /usr/bin/codesign "$@"; then
            return 0
        fi
        if (( attempt < 3 )); then
            echo "  Developer ID signing failed; retrying ($((attempt + 1))/3)"
            sleep "$attempt"
        fi
    done
    return 1
}

write_swift_output_file_map() {
    local output_file="$1"
    local object_dir="$2"
    shift 2
    local source artifact

    {
        print -r -- "{"
        print -r -- "  \"\": {"
        print -r -- "    \"swift-dependencies\": \"$object_dir/master.swiftdeps\""
        print -r -- "  }"
        for source in "$@"; do
            artifact="${source//\//__}"
            artifact="${artifact%.swift}"
            print -r -- ","
            print -r -- "  \"$source\": {"
            print -r -- "    \"object\": \"$object_dir/$artifact.o\","
            print -r -- "    \"swift-dependencies\": \"$object_dir/$artifact.swiftdeps\""
            print -r -- "  }"
        done
        print -r -- "}"
    } > "$output_file"
}

finalize_installed_bundle_after_child() {
    local bundle="$1"
    local helper="$bundle/Contents/Library/LaunchServices/$FAN_HELPER_ID"
    local adapter="$bundle/Contents/Frameworks/$NOW_PLAYING_ADAPTER"
    local devid
    devid="$(developer_id_identity)"

    echo "▸ Finalizing installed signature…"
    sleep 3
    if [[ -n "$devid" ]]; then
        [[ -f "$helper" ]] && codesign_with_timestamp_retry --force --strip-disallowed-xattrs \
            --options runtime --timestamp --identifier "$FAN_HELPER_ID" --sign "$devid" "$helper"
        [[ -f "$adapter" ]] && codesign_with_timestamp_retry --force --strip-disallowed-xattrs \
            --options runtime --timestamp --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$devid" "$adapter"
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$devid" "$bundle"
    elif legacy_identity_installed; then
        [[ -f "$helper" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$FAN_HELPER_ID" --sign "$LEGACY_IDENTITY" "$helper"
        [[ -f "$adapter" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$LEGACY_IDENTITY" "$adapter"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$bundle"
    else
        [[ -f "$helper" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$FAN_HELPER_ID" --sign - "$helper"
        [[ -f "$adapter" ]] && /usr/bin/codesign --force --strip-disallowed-xattrs \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign - "$adapter"
        /usr/bin/codesign --force --strip-disallowed-xattrs --sign - "$bundle"
    fi
    [[ -f "$helper" ]] && /usr/bin/codesign --verify --strict "$helper"
    [[ -f "$adapter" ]] && /usr/bin/codesign --verify --strict "$adapter"
    /usr/bin/codesign --verify --deep --strict "$bundle"
    echo "✓ Signature ready: $bundle"
}

if (( INSTALL && ! TEST )) && [[ "${SASNOTCH_INSTALL_CHILD:-0}" != "1" ]]; then
    SASNOTCH_INSTALL_CHILD=1 "$0" "$@"
    child_status=$?
    if (( child_status != 0 )); then
        exit "$child_status"
    fi
    finalize_installed_bundle_after_child "/Applications/$APP_NAME.app"
    exit 0
fi

# Prefer the macOS 26 SDK when present: the 27 SDK turns SwiftUI property wrappers
# into macros (SwiftUIMacros plugin) that the Command Line Tools cannot load yet.
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    SDK="$(xcrun --show-sdk-path)"
elif [[ -d "$PINNED_SDK" ]]; then
    SDK="$PINNED_SDK"
else
    SDK="$(xcrun --show-sdk-path)"
fi
SDK_COMPAT_FLAGS=()
VM_STATISTICS_COMPAT_FLAGS=(-I Sources/VMStatisticsCompat)
HID_EVENT_SYSTEM_FLAGS=(-I Sources/HIDEventSystem)
if [[ "$SDK" == "$PINNED_SDK" ]]; then
    # Swift 6.4 can read the SDK 26 interfaces when given their compiler version.
    SDK_COMPAT_FLAGS=(-Xfrontend -interface-compiler-version -Xfrontend 6.3.2)
fi

# The defaults migrations under test need a real UserDefaults suite, and every
# suite leaves an empty plist in ~/Library/Preferences. The tests already clear
# the domains, but cfprefsd writes the emptied file back out around the time the
# process that owned it exits, so only a caller that outlives the run can remove
# them. `PreferenceNamespaceTests` scans every compiled Swift test file against
# these namespaces, which keeps this sweep complete without a second list.
discard_test_preferences() {
    local preferences="${1:-$HOME/Library/Preferences}" name attempt
    local survivors=0 quiet_passes=0
    # cfprefsd can recreate an emptied domain after the first removal. Require
    # two quiet checks, but keep a hard limit so persistent failures still fail CI.
    for attempt in {1..10}; do
        for name in "sasnotch.tests." "com.sasnotch.tests."; do
            rm -f "$preferences"/$name*.plist(N)
        done
        rm -f "$preferences/metrics-tests.plist"
        sleep 0.2
        survivors=$(find "$preferences" -maxdepth 1 \
            \( -name "sasnotch.tests.*.plist" -o -name "com.sasnotch.tests.*.plist" \
               -o -name "metrics-tests.plist" \) 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$survivors" == "0" ]]; then
            quiet_passes=$((quiet_passes + 1))
            if (( quiet_passes == 2 )); then return 0; fi
        else
            quiet_passes=0
        fi
    done
    echo "✗ test preferences did not settle in $preferences ($survivors remaining)" >&2
    return 1
}

# Standalone automated tests: pure contracts plus isolated disk, subprocess,
# keyboard-data and media fixtures. No application windows or device capture.
if (( TEST )); then
    python3 Tests/generate_sources.py
    TEST_OBJECT_DIR="build/objects/tests"
    mkdir -p "$TEST_OBJECT_DIR"
    TEST_SOURCES=(
        Sources/SasNotch/Services/Media/MediaSupport.swift
        Sources/SasNotch/Core/QuitProtectionSupport.swift
        Sources/SasNotch/Core/QuitProtectionStrings.swift
        Sources/SasNotch/Core/Defaults.swift
        Sources/SasNotch/Core/NotchStrings.swift
        Sources/SasNotch/Core/NotchTourStrings.swift
        Sources/SasNotch/Core/NotchEditorStrings.swift
        Sources/SasNotch/UI/Settings/NotchSettingsTabRow.swift
        Sources/SasNotch/Core/NotchActivityStrings.swift
        Sources/SasNotch/Services/Notch/NotchTimerSupport.swift
        Sources/SasNotch/Services/Notch/NotchAppFullscreen.swift
        Sources/SasNotch/Services/Notch/NotchTimerAlert.swift
        Sources/SasNotch/UI/Notch/NotchIslandAlert.swift
        Sources/SasNotch/Services/Notch/NotchAccessorySupport.swift
        Sources/SasNotch/Services/Notch/NotchAccessoryConnectionMonitor.swift
        Sources/SasNotch/Services/QuickTools/CameraPreviewSupport.swift
        Sources/SasNotch/Core/NotchMusicExtrasStrings.swift
        Sources/SasNotch/Core/NotchClipboardSizeStrings.swift
        Sources/SasNotch/Services/Notch/NotchLyricsSupport.swift
        Sources/SasNotch/Services/Notch/NotchQueueSupport.swift
        Sources/SasNotch/Services/Notch/NotchPreferredPlayer.swift
        Sources/SasNotch/Core/NotchFilesStrings.swift
        Sources/SasNotch/Core/NotchWatchStrings.swift
        Sources/SasNotch/Services/Notch/NotchWatchSupport.swift
        Sources/SasNotch/Core/NotchMascotStrings.swift
        Sources/SasNotch/Services/Notch/NotchMascotSupport.swift
        Sources/SasNotch/Services/CommandBar/CommandBarDropletMotion.swift
        Sources/SasNotch/Services/Notch/NotchFileToolsSupport.swift
        Sources/SasNotch/Services/Notch/NotchDownloadSupport.swift
        Sources/SasNotch/Services/Notch/NotchDownloadProgressObserver.swift
        Sources/SasNotch/Core/NotchCalendarStrings.swift
        Sources/SasNotch/Core/NotchNotificationStrings.swift
        Sources/SasNotch/Core/NotchGestureStrings.swift
        Sources/SasNotch/Core/NotchAgentStrings.swift
        Sources/SasNotch/Core/CodexAccountStrings.swift
        Sources/SasNotch/Services/Notch/NotchAgentSupport.swift
        Sources/SasNotch/Core/NotchLockScreenStrings.swift
        Sources/SasNotch/Services/Notch/NotchLockScreenSupport.swift
        Sources/SasNotch/Services/AgentUsage/AgentUsageModels.swift
        Sources/SasNotch/Services/AgentUsage/AgentPricing.swift
        Sources/SasNotch/Services/AgentUsage/AgentLogObject.swift
        Sources/SasNotch/Services/AgentUsage/AgentLogParser.swift
        Sources/SasNotch/Services/AgentUsage/Harness/AgentHarnessReader.swift
        Sources/SasNotch/Services/AgentUsage/Harness/ClaudeReader.swift
        Sources/SasNotch/Services/AgentUsage/Harness/CodexReader.swift
        Sources/SasNotch/Services/AgentUsage/Harness/OpenCodeReader.swift
        Sources/SasNotch/Services/AgentUsage/Harness/CopilotReader.swift
        Sources/SasNotch/Services/AgentUsage/AgentUsageSummary.swift
        Sources/SasNotch/Services/AgentUsage/AgentUsageStore.swift
        Sources/SasNotch/Services/AgentUsage/AgentUsageArchive.swift
        Sources/SasNotch/Services/AgentUsage/AgentClaudeAppUsage.swift
        Sources/SasNotch/Services/AgentUsage/AgentCLIConversation.swift
        Sources/SasNotch/Services/AgentUsage/AgentClaudeServer.swift
        Sources/SasNotch/Services/AgentUsage/AgentCodexServer.swift
        Sources/SasNotch/Services/AgentUsage/CodexAccountLimits.swift
        Sources/SasNotch/Services/AgentUsage/CodexProfileLimitsService.swift
        Sources/SasNotch/Services/AgentUsage/AgentOpenCodeReader.swift
        Sources/SasNotch/Services/Notch/NotchGestureSupport.swift
        Sources/SasNotch/Services/Notch/NotchSectionPaging.swift
        Sources/SasNotch/Services/Notch/NotchSliderEditing.swift
        Sources/SasNotch/Services/Notch/NotchNotificationSupport.swift
        Sources/SasNotch/Services/Notch/NotchNotificationReaderCore.swift
        Sources/SasNotch/Services/Notch/NotchCalendarSupport.swift
        Sources/SasNotch/Services/Notch/NotchKeepAwakeSupport.swift
        Sources/SasNotch/Services/Notch/NotchSupport.swift
        Sources/SasNotch/Services/Notch/NotchAudioLevelSupport.swift
        Sources/SasNotch/Services/Notch/NotchVolumeKeyGate.swift
        Sources/SasNotch/Services/Notch/NotchMusicSupport.swift
        Sources/SasNotch/UI/Notch/NotchDecorativeClock.swift
        Sources/SasNotch/Services/Notch/NotchBrowserArtworkSupport.swift
        Sources/SasNotch/UI/Notch/NotchEqualizerBars.swift
        Sources/SasNotch/UI/Notch/NotchScrollEdgeFade.swift
        Sources/SasNotch/UI/Notch/NotchAgentAnimationView.swift
        Sources/SasNotch/UI/WindowVisibilityReader.swift
        Sources/SasNotch/Services/Notch/NotchMusicAutomationSupport.swift
        Sources/SasNotch/Services/Notch/NotchMusicAutomation.swift
        Sources/SasNotch/Services/Notch/NotchPlaybackSource.swift
        Sources/SasNotch/Services/Notch/NotchPlaybackCommand.swift
        Sources/SasNotch/Services/Notch/NotchMusicCommandWriter.swift
        Sources/SasNotch/Core/FeatureCatalog.swift
        Sources/SasNotch/Core/FeaturePresets.swift
        Sources/SasNotch/Core/FeatureHubStrings.swift
        Sources/SasNotch/Core/MixerScreenSharingStrings.swift
        Sources/SasNotch/Core/ShortcutSettingsStrings.swift
        Sources/SasNotch/Core/SettingsBackupSupport.swift
        Sources/SasNotch/Core/BackupStrings.swift
        Sources/SasNotch/Core/SnippetStrings.swift
        Sources/SasNotch/Core/AlertSoundStrings.swift
        Sources/SasNotch/Core/BrightnessStrings.swift
        Sources/SasNotch/Core/MediaImageStrings.swift
        Sources/SasNotch/Core/QuickToggleStrings.swift
        Sources/SasNotch/Core/ScreenshotStrings.swift
        Sources/SasNotch/Core/RecentCaptureStrings.swift
        Sources/SasNotch/Core/RecorderStrings.swift
        Sources/SasNotch/Core/RecorderShareStrings.swift
        Sources/SasNotch/Core/CameraPreviewStrings.swift
        Sources/SasNotch/Core/WallpaperStrings.swift
        Sources/SasNotch/Services/Wallpaper/WallpaperSupport.swift
        Sources/SasNotch/Core/ScratchpadStrings.swift
        Sources/SasNotch/Core/FinderRenameStrings.swift
        Sources/SasNotch/Core/CommandBarStrings.swift
        Sources/SasNotch/Core/FeedbackStrings.swift
        Sources/SasNotch/Core/RadialMenuStrings.swift
        Sources/SasNotch/Core/MenuBarAppearanceStrings.swift
        Sources/SasNotch/Core/AppAppearance.swift
        Sources/SasNotch/Core/AppearanceStrings.swift
        Sources/SasNotch/Core/GeneralSettingsStrings.swift
        Sources/SasNotch/Core/SettingsPageStrings.swift
        Sources/SasNotch/Core/BatteryTimeStrings.swift
        Sources/SasNotch/Core/CPUCoreStrings.swift
        Sources/SasNotch/Core/MonitorLayoutStrings.swift
        Sources/SasNotch/Core/KeepAwakeStrings.swift
        Sources/SasNotch/Core/BluetoothSleepStrings.swift
        Sources/SasNotch/Core/PermissionGuideStrings.swift
        Sources/SasNotch/Core/FanControlStrings.swift
        Sources/SasNotch/Core/ConnectedDevicesStrings.swift
        Sources/SasNotch/Services/FanControl/FanControlSupport.swift
        Sources/SasNotch/Services/FanControl/FanControlResumeSupport.swift
        Sources/SasNotch/Services/Snippets/TextSnippetSupport.swift
        Sources/SasNotch/Services/RadialMenu/RadialMenuSupport.swift
        Sources/SasNotch/Services/QuickTools/ScratchpadSupport.swift
        Sources/SasNotch/Services/QuickTools/ScratchpadStore.swift
        Sources/SasNotch/Services/KillProcess/KillProcessSupport.swift
        Sources/SasNotch/Services/Recorder/RecorderSupport.swift
        Sources/SasNotch/Services/Recorder/RecorderSampleTiming.swift
        Sources/SasNotch/Services/Recorder/RecorderWriter.swift
        Sources/SasNotch/Services/Recorder/RecorderCaptureEngine.swift
        Sources/SasNotch/Core/RecorderExportStrings.swift
        Sources/SasNotch/Services/Recorder/RecorderComposer.swift
        Sources/SasNotch/Services/Recorder/RecorderComposerPlan.swift
        Sources/SasNotch/Services/Recorder/RecorderCursorSprite.swift
        Sources/SasNotch/Services/Recorder/RecorderTextRenderer.swift
        Sources/SasNotch/Services/Recorder/RecorderImageRenderer.swift
        Sources/SasNotch/Services/Recorder/RecorderExporter.swift
        Sources/SasNotch/Services/Recorder/RecorderGIFClipboard.swift
        Sources/SasNotch/Services/Recorder/RecorderGIFWriter.swift
        Sources/SasNotch/Services/Recorder/RecorderGIFWorkspace.swift
        Sources/SasNotch/Services/Recorder/RecorderComposition.swift
        Sources/SasNotch/Services/Recorder/RecordingSharingSupport.swift
        Sources/SasNotch/Services/PrivateFileStore.swift
        Sources/SasNotch/Services/Recorder/RecorderTakeStore.swift
        Sources/SasNotch/Services/Recorder/RecorderPresetImageStore.swift
        Sources/SasNotch/Services/Recorder/RecorderMotion.swift
        Sources/SasNotch/Services/Recorder/RecorderPointerTrack.swift
        Sources/SasNotch/Services/Recorder/RecorderTypingTrack.swift
        Sources/SasNotch/Services/Recorder/RecorderTimeline.swift
        Sources/SasNotch/Services/Recorder/RecorderTextOverlay.swift
        Sources/SasNotch/Services/Recorder/RecorderImageOverlay.swift
        Sources/SasNotch/Services/Recorder/RecorderBlurRegion.swift
        Sources/SasNotch/Services/Recorder/RecorderEditDocument.swift
        Sources/SasNotch/Core/AppInfo.swift
        Sources/SasNotch/Core/GlobalShortcut.swift
        Sources/SasNotch/Core/SymbolicHotKeys.swift
        Sources/SasNotch/Services/SystemShortcutTakeoverSupport.swift
        Sources/SasNotch/Core/Localization.swift
        Sources/SasNotch/Core/Localizations/Strings+*.swift
        Sources/SasNotch/Core/FeatureStrings.swift
        Sources/SasNotch/Core/KillProcessStrings.swift
        Sources/SasNotch/Core/PortManagerStrings.swift
        Sources/SasNotch/Core/WhatsAppDownloadStrings.swift
        Sources/SasNotch/Core/WhatsAppOrganizerStrings.swift
        Sources/SasNotch/Core/ReleaseNotes.swift
        Sources/SasNotch/Core/ReleaseDigest.swift
        Sources/SasNotch/Core/ReleaseChangeAliases.swift
        Sources/SasNotch/Core/WhatsNewStrings.swift
        Sources/SasNotch/Core/URLCleaning.swift
        Sources/SasNotch/Services/GeneralPasteboardAccess.swift
        Sources/SasNotch/Services/Clipboard/ClipboardHistoryWrite.swift
        Sources/SasNotch/Services/Audio/AirPlayRouteManager.swift
        Sources/SasNotch/Services/Audio/MixerRoutingSupport.swift
        Sources/SasNotch/Services/Audio/MusicLaunchSupport.swift
        Sources/SasNotch/Services/Bluetooth/BluetoothSleepSupport.swift
        Sources/SasNotch/UI/MenuPanel/MixerPercentNativeTextField.swift
        Sources/SasNotch/UI/MenuPanel/MixerAppDragSource.swift
        Sources/SasNotch/Services/Audio/BoostLimiter.swift
        Sources/SasNotch/Services/Audio/MixerRender.swift
        Sources/SasNotch/Services/Audio/PreciseVolumeRollerSupport.swift
        Sources/SasNotch/Services/DockPreview/DockPreviewSupport.swift
        Sources/SasNotch/Services/DockPreview/DockAutohideHold.swift
        Sources/SasNotch/Services/SpacesOrder/SpacesOrderHold.swift
        Sources/SasNotch/Services/Homebrew/HomebrewSupport.swift
        Sources/SasNotch/Services/Homebrew/HomebrewEnvironment.swift
        Sources/SasNotch/Services/AppUpdates/AppUpdatesSupport.swift
        Sources/SasNotch/Services/AppUpdates/AppUpdateFeedSupport.swift
        Sources/SasNotch/Core/AppUpdateStrings.swift
        Sources/SasNotch/Core/DiskImageInstallerStrings.swift
        Sources/SasNotch/Services/DiskImageInstaller/DiskImageInstallerSupport.swift
        Sources/SasNotch/UI/NonModalAlert.swift
        Sources/SasNotch/Services/Clipboard/ClipboardHistorySupport.swift
        Sources/SasNotch/Core/ColorValue.swift
        Sources/SasNotch/Services/Clipboard/ClipboardAutoClearSupport.swift
        Sources/SasNotch/Services/AutoQuit/AutoQuitSupport.swift
        Sources/SasNotch/Core/AutoQuitDockAppsStrings.swift
        Sources/SasNotch/Services/Shelf/ShelfSupport.swift
        Sources/SasNotch/Services/Shelf/ShelfFilePromiseTransfer.swift
        Sources/SasNotch/Core/ShelfPromiseDeliveryStrings.swift
        Sources/SasNotch/Services/Finder/FinderRenameSupport.swift
        Sources/SasNotch/Services/Update/UpdateInstallerSupport.swift
        Sources/SasNotch/Services/Update/UpdateServiceSupport.swift
        Sources/SasNotch/Services/InstalledApps.swift
        Sources/SasNotch/Services/LaunchAtLoginSupport.swift
        Sources/SasNotch/UI/Settings/SettingsSearchSupport.swift
        Sources/SasNotch/UI/Settings/SettingsSidebarSupport.swift
        Sources/SasNotch/UI/Settings/FeatureVisibilitySupport.swift
        Sources/SasNotch/UI/Onboarding/WhatsNewSupport.swift
        Sources/SasNotch/UI/Settings/SettingsWindow.swift
        Sources/SasNotch/Core/SettingsNavigationStrings.swift
        Sources/SasNotch/App/MenuBarSpacingSupport.swift
        Sources/SasNotch/App/MenuBarAllowanceSupport.swift
        Sources/SasNotch/App/ReopenRequestSupport.swift
        Sources/SasNotch/App/StatusItemAnchorSupport.swift
        Sources/SasNotch/Services/DockClick/DockClickSupport.swift
        Sources/SasNotch/Services/Finder/CutPasteProgressSupport.swift
        Sources/SasNotch/Services/Finder/CutPastePrivilegeSupport.swift
        Sources/SasNotch/Services/Finder/FinderPasteImageSupport.swift
        Sources/SasNotch/Services/MiddleClick/MiddleClickSupport.swift
        Sources/SasNotch/Services/MouseNavigation/MouseNavigationSupport.swift
        Sources/SasNotch/Services/MouseNavigation/MouseNavigationKeys.swift
        Sources/SasNotch/Services/MouseButtons/MouseButtonShortcutSupport.swift
        Sources/SasNotch/Services/MouseButtons/MouseSpacesGestureSupport.swift
        Sources/SasNotch/Services/MouseClickDebounce/MouseClickDebounceSupport.swift
        Sources/SasNotch/Services/MouseExceptions/MouseAppExceptionSupport.swift
        Sources/SasNotch/Services/MouseExceptions/MouseAppExceptions.swift
        Sources/SasNotch/Services/WindowServerSupport.swift
        Sources/SasNotch/Services/WindowMaximizerSupport.swift
        Sources/SasNotch/Core/MouseButtonStrings.swift
        Sources/SasNotch/Core/MouseClickDebounceStrings.swift
        Sources/SasNotch/Core/MouseExceptionStrings.swift
        Sources/SasNotch/Core/ClipboardIgnoredAppsStrings.swift
        Sources/SasNotch/Core/ClipboardRetentionStrings.swift
        Sources/SasNotch/Core/WindowLayoutIgnoredAppsStrings.swift
        Sources/SasNotch/Services/WindowLayout/WindowLayoutIgnoredApps.swift
        Sources/SasNotch/Core/WindowPreviewExclusionStrings.swift
        Sources/SasNotch/Core/WindowMaximizerExclusionStrings.swift
        Sources/SasNotch/Core/DiskExclusionStrings.swift
        Sources/SasNotch/Core/SwitcherAppRulesStrings.swift
        Sources/SasNotch/Services/QuickTools/QuickToolsSupport.swift
        Sources/SasNotch/Services/CommandBar/CommandBarSupport.swift
        Sources/SasNotch/Services/CommandBar/CommandBarPreferences.swift
        Sources/SasNotch/Services/CommandBar/CommandBarMath.swift
        Sources/SasNotch/Services/CommandBar/CommandBarUnits.swift
        Sources/SasNotch/Services/CommandBar/CommandBarColors.swift
        Sources/SasNotch/Services/CommandBar/CommandBarEmoji.swift
        Sources/SasNotch/Services/CommandBar/CommandBarLinks.swift
        Sources/SasNotch/Services/CommandBar/CommandBarDates.swift
        Sources/SasNotch/Services/CommandBar/CommandBarRowShortcuts.swift
        Sources/SasNotch/Services/CommandBar/CommandBarSystemSettingsSupport.swift
        Sources/SasNotch/Services/CommandBar/CommandBarFileSearchSupport.swift
        Sources/SasNotch/Services/CommandBar/CommandBarQueryMemory.swift
        Sources/SasNotch/Services/SpotlightNamesSupport.swift
        Sources/SasNotch/Services/QuickTools/MicMuteSupport.swift
        Sources/SasNotch/Services/QuickTools/QuickTogglesSupport.swift
        Sources/SasNotch/Services/QuickTools/ScreenshotCapturePolicy.swift
        Sources/SasNotch/Services/QuickTools/ScreenshotSupport.swift
        Sources/SasNotch/Services/QuickTools/ScreenshotCanvasSupport.swift
        Sources/SasNotch/UI/Settings/ScreenCaptureToolPicker.swift
        Sources/SasNotch/UI/Settings/MonitorToken.swift
        Sources/SasNotch/Services/QuickTools/ScreenshotRenderer.swift
        Sources/SasNotch/Services/QuickTools/ScreenshotImageLayerRendering.swift
        Sources/SasNotch/Services/QuickTools/RecentCaptureStore.swift
        Sources/SasNotch/Services/QuickTools/ScreenshotSharingSupport.swift
        Sources/SasNotch/Services/QuickTools/WindowActivationPolicy.swift
        Sources/SasNotch/Services/KeyboardDebounce/KeyboardDebounceSupport.swift
        Sources/SasNotch/Services/SuperKey/SuperKeySupport.swift
        Sources/SasNotch/Services/SuperKey/SuperKeyMappingGuard.swift
        Sources/SasNotch/Core/SuperKeyStrings.swift
        Sources/SasNotch/Core/InputSourceSelection.swift
        Sources/SasNotch/Services/SessionActivity.swift
        Sources/SasNotch/Services/SessionActivitySupport.swift
        Sources/SasNotch/Services/EventTimestamp.swift
        Sources/SasNotch/Services/OwnKeyEvent.swift
        Sources/SasNotch/Services/ScrollWheelSupport.swift
        Sources/SasNotch/Services/HorizontalWheelScrolling.swift
        Sources/SasNotch/Services/SmoothScrollSupport.swift
        Sources/SasNotch/Services/MouseAcceleration/MouseAccelerationSupport.swift
        Sources/SasNotch/Services/FocusFollowsMouse/FocusFollowsMouseSupport.swift
        Sources/SasNotch/Services/AssistiveKeyboard.swift
        Sources/SasNotch/Services/Switcher/SwitcherModels.swift
        Sources/SasNotch/Services/Switcher/WindowServerCaptureQueue.swift
        Sources/SasNotch/Services/Switcher/SwitcherSupport.swift
        Sources/SasNotch/Services/Switcher/SpaceHopSupport.swift
        Sources/SasNotch/Services/Switcher/WindowUseOrder.swift
        Sources/SasNotch/Services/Metrics/MetricFormat.swift
        Sources/SasNotch/Services/Metrics/VMStatisticsDecoder.swift
        Sources/SasNotch/Services/KeepAwakeAutomationSupport.swift
        Sources/SasNotch/Services/SudoersSupport.swift
        Sources/SasNotch/Services/Metrics/BatteryTimeSupport.swift
        Sources/SasNotch/Services/Metrics/BatteryPowerSupport.swift
        Sources/SasNotch/Services/BoundedProcessRunner.swift
        Sources/SasNotch/Services/DetachedProcess.swift
        Sources/SasNotch/Services/ShellSupport.swift
        Sources/SasNotch/Services/PortManager/PortManagerSupport.swift
        Sources/SasNotch/Services/Metrics/NetworkProcessSupport.swift
        Sources/SasNotch/Services/Metrics/NetworkSampler.swift
        Sources/SasNotch/Services/Metrics/NetworkAddressService.swift
        Sources/SasNotch/Services/Metrics/SpeedTest.swift
        Sources/SasNotch/Services/Metrics/PeripheralBatterySampler.swift
        Sources/SasNotch/Services/Metrics/PeripheralBatterySupport.swift
        Sources/SasNotch/Services/Metrics/DiskSupport.swift
        Sources/SasNotch/Services/Metrics/MonitorSamplingPolicy.swift
        Sources/SasNotch/Services/Metrics/USBDeviceSampler.swift
        Sources/SasNotch/Services/Metrics/CPUCoreSampler.swift
        Sources/SasNotch/Services/Metrics/MaxCapacityProbe.swift
        Sources/SasNotch/Services/Metrics/TemperatureSensorSelector.swift
        Sources/SasNotch/Services/Metrics/SustainedAlertGate.swift
        Sources/SasNotch/Services/WindowLayout/WindowLayoutSupport.swift
        Sources/SasNotch/Services/WindowLayout/WindowStageManagerSupport.swift
        Sources/SasNotch/Core/WindowStageManagerStrings.swift
        Sources/SasNotch/Services/WindowLayout/WindowGestureSupport.swift
        Sources/SasNotch/Core/WindowDirectionalStrings.swift
        Sources/SasNotch/Core/PointerDisplayStrings.swift
        Sources/SasNotch/Core/GraphScaleStrings.swift
        Sources/SasNotch/Core/NotchLowBatteryStrings.swift
        Sources/SasNotch/Services/CleaningMode/CleaningUnlockCounter.swift
        Sources/SasNotch/Services/CleaningMode/CleaningMouseReleaseGate.swift
        Sources/SasNotch/Services/Display/ExtraBrightnessSupport.swift
        Sources/SasNotch/Services/Display/BrightnessSupport.swift
        Sources/SasNotch/Services/Display/LidDimmingSupport.swift
        Sources/SasNotch/Services/Cleaner/CleanerSupport.swift
        Sources/SasNotch/Services/Cleaner/CleanerPolicy.swift
        Sources/SasNotch/Services/Cleaner/CleanerSchedule.swift
        Sources/SasNotch/Services/Uninstall/UninstallerSupport.swift
        Sources/SasNotch/Services/ManagedDownloads/WhatsAppDownloadSupport.swift
        Sources/SasNotch/Core/SecureInputSupport.swift
        Tests/*.swift
        build/generated-tests/*.swift
    )
    TEST_OUTPUT_FILE_MAP="$TEST_OBJECT_DIR/output-file-map.json"
    write_swift_output_file_map "$TEST_OUTPUT_FILE_MAP" "$TEST_OBJECT_DIR" "${TEST_SOURCES[@]}"
    echo "▸ Building & running tests against $(basename "$SDK")…"
    swiftc -Onone -incremental -enable-batch-mode -j "$(sysctl -n hw.logicalcpu)" \
        -module-name SasNotchTests -output-file-map "$TEST_OUTPUT_FILE_MAP" \
        -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" \
        "${VM_STATISTICS_COMPAT_FLAGS[@]}" "${TEST_SOURCES[@]}" -o build/metrics-tests
    test_status=0
    ./build/metrics-tests "${TEST_ARGS[@]}" || test_status=$?
    if (( ${#TEST_ARGS} == 0 )); then
        ./Tests/PreferenceCleanupTests.sh || test_status=1
        ./Tests/UninstallSpacesTests.sh || test_status=1
        ./Tests/DeveloperInstallIsolationTests.sh || test_status=1
    fi
    discard_test_preferences || test_status=1
    exit $test_status
fi

echo "▸ Compiling ($BUILD_CONFIGURATION) against $(basename "$SDK")…"
APP_SOURCES=(Sources/SasNotch/**/*.swift)
if (( ! DEV )); then
    # A release starts from an empty build directory, so nothing an earlier
    # build left behind (an old icon catalog, a staged bundle) can reach it.
    # Only the compiler's incremental records stay: they rebuild whatever
    # changed since, and a fresh checkout has none.
    find build -mindepth 1 -maxdepth 1 ! -name objects -exec rm -rf {} + 2>/dev/null || true
fi
APP_OBJECT_DIR="build/objects/$EXECUTABLE"
mkdir -p build "$APP_OBJECT_DIR"
APP_OUTPUT_FILE_MAP="$APP_OBJECT_DIR/output-file-map.json"
write_swift_output_file_map "$APP_OUTPUT_FILE_MAP" "$APP_OBJECT_DIR" "${APP_SOURCES[@]}"
# Without -j the driver compiles one file at a time, and without batch mode
# each file's compiler parses the whole module again: a clean release took a
# quarter of an hour. Batches share that work and run on every core, and the
# optimization stays per file, as before.
swiftc "${APP_OPTIMIZATION_FLAGS[@]}" -incremental -enable-batch-mode -j "$(sysctl -n hw.logicalcpu)" \
    -output-file-map "$APP_OUTPUT_FILE_MAP" \
    -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${VM_STATISTICS_COMPAT_FLAGS[@]}" "${HID_EVENT_SYSTEM_FLAGS[@]}" \
    "${BUILD_VARIANT_FLAGS[@]}" \
    "${APP_SOURCES[@]}" -o "build/$EXECUTABLE"

echo "▸ Compiling protected fan helper…"
swiftc -O -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" "${BUILD_VARIANT_FLAGS[@]}" \
    Sources/SasNotch/Services/FanControl/FanControlSupport.swift \
    Sources/SasNotch/Services/FanControl/FanControlXPC.swift \
    Sources/SasNotch/Services/SystemMonitor/SMCClient.swift \
    Sources/SasNotch/Services/Metrics/TemperatureSensorSelector.swift \
    Sources/SasNotch/Services/FanControl/FanControlHardware.swift \
    Sources/FanControlHelper/main.swift \
    -o "build/$FAN_HELPER_ID"
"build/$FAN_HELPER_ID" --selftest

echo "▸ Compiling Now Playing adapter…"
swiftc -O -target "$TARGET" -sdk "$SDK" "${SDK_COMPAT_FLAGS[@]}" -emit-library \
    -module-name SasNotchNowPlaying \
    Sources/NowPlayingAdapter/NowPlayingAdapter.swift \
    Sources/NowPlayingAdapter/NowPlayingQueue.swift \
    Sources/NowPlayingAdapter/NowPlayingSelection.swift \
    Sources/SasNotch/Services/Notch/NotchPlaybackSource.swift \
    Sources/SasNotch/Services/Notch/NotchPlaybackCommand.swift \
    -o "build/$NOW_PLAYING_ADAPTER"

echo "▸ Generating app icon…"
swift Tools/MakeIcon.swift build/AppIcon.iconset
xattr -c -r build/AppIcon.iconset build/AppIcon.icns build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png 2>/dev/null || true
echo "▸ Assembling and signing bundle…"
STAGE_TMP="$(mktemp -d)"
STAGE="$STAGE_TMP/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" \
    "$STAGE/Contents/Library/LaunchDaemons" "$STAGE/Contents/Library/LaunchServices"
cp "build/$EXECUTABLE" "$STAGE/Contents/MacOS/$EXECUTABLE"
cp "build/$FAN_HELPER_ID" "$STAGE/Contents/Library/LaunchServices/$FAN_HELPER_ID"
mkdir -p "$STAGE/Contents/Frameworks"
cp "build/$NOW_PLAYING_ADAPTER" "$STAGE/Contents/Frameworks/$NOW_PLAYING_ADAPTER"
cp Resources/now-playing.pl "$STAGE/Contents/Resources/now-playing.pl"
cp Resources/agent-prices.json "$STAGE/Contents/Resources/agent-prices.json"
cp Resources/com.sasnotch.app.fan-control.plist \
    "$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp CHANGELOG.md "$STAGE/Contents/Resources/CHANGELOG.md"
for lproj in Resources/*.lproj(N); do
    cp -R "$lproj" "$STAGE/Contents/Resources/"
done
if (( DEV )); then
    # A distinct identity so the Developer build installs and runs next to the
    # official app, with its own permissions, preferences and login item.
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $APP_BUNDLE_ID" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$STAGE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXECUTABLE" "$STAGE/Contents/Info.plist"
    FAN_PLIST="$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist"
    /usr/libexec/PlistBuddy -c "Set :Label $FAN_HELPER_ID" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Set :BundleProgram Contents/Library/LaunchServices/$FAN_HELPER_ID" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Delete :MachServices:com.sasnotch.app.fan-control" "$FAN_PLIST"
    /usr/libexec/PlistBuddy -c "Add :MachServices:$FAN_HELPER_ID bool true" "$FAN_PLIST"
    # Stamp the source commit + build time so the running dev app shows (in About)
    # exactly which code it was compiled from. Lets you verify it matches HEAD before
    # testing, instead of unknowingly running a stale build. Dev-only; never shipped.
    SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    [[ -n "$(git status --porcelain 2>/dev/null)" ]] && SHA="$SHA-dirty"
    /usr/libexec/PlistBuddy -c "Add :SasNotchBuildCommit string '$SHA · $(date '+%Y-%m-%d %H:%M')'" "$STAGE/Contents/Info.plist"
    echo "  stamped dev build: $SHA"
fi
FAN_HELPER_VERSION="$(
    export LC_ALL=C
    /usr/bin/shasum -a 256 \
        "$STAGE/Contents/Library/LaunchServices/$FAN_HELPER_ID" \
        "$STAGE/Contents/Library/LaunchDaemons/$FAN_HELPER_ID.plist" \
        | /usr/bin/awk '{print $1}' | /usr/bin/shasum -a 256 \
        | /usr/bin/awk '{print $1}'
)"
/usr/libexec/PlistBuddy -c "Add :SasNotchFanControlHelperVersion string '$FAN_HELPER_VERSION'" \
    "$STAGE/Contents/Info.plist"
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp build/MenuBarIcon.png build/MenuBarIcon@2x.png build/BrandMark.png "$STAGE/Contents/Resources/"
if [[ -f build/Assets.car ]]; then
    cp build/Assets.car "$STAGE/Contents/Resources/Assets.car"
fi
if [[ -d Resources/Gifs ]]; then
    mkdir -p "$STAGE/Contents/Resources/Gifs"
    cp Resources/Gifs/*.gif "$STAGE/Contents/Resources/Gifs/"
fi
if ! cmp -s Resources/Gifs/highlights-notch.gif "$STAGE/Contents/Resources/Gifs/highlights-notch.gif"; then
    echo "Dynamic Island tour GIF is missing or differs from the bundled copy" >&2
    exit 1
fi
if [[ -d Resources/Images ]]; then
    mkdir -p "$STAGE/Contents/Resources/Images"
    cp Resources/Images/* "$STAGE/Contents/Resources/Images/"
fi
xattr -c -r "$STAGE" 2>/dev/null || true

# Signing, in order of preference:
#   1. Developer ID Application — the real, Apple-issued identity used for
#      notarized releases. Signed with the hardened runtime (required for
#      notarization), the app's entitlements and a secure timestamp. Gives a
#      stable, team-based designated requirement, so permissions persist across
#      updates AND Gatekeeper shows no "unverified developer" warning.
#   2. "SasNotch Self-Signed" — the legacy stable self-signed identity, kept
#      as a fallback so contributors without a Developer ID still get a constant
#      designated requirement across their local builds.
#   3. Ad-hoc — fresh clone with no identity at all.
DEVID="$(developer_id_identity)"
codesign_app() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --entitlements "$ENTITLEMENTS" --sign "$DEVID" "$target"
    elif legacy_identity_installed; then
        codesign --force --strip-disallowed-xattrs --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --sign - "$target"
    fi
}

codesign_fan_helper() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --identifier "$FAN_HELPER_ID" --sign "$DEVID" "$target"
    elif legacy_identity_installed; then
        codesign --force --strip-disallowed-xattrs --identifier "$FAN_HELPER_ID" \
            --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --identifier "$FAN_HELPER_ID" --sign - "$target"
    fi
}

codesign_now_playing_adapter() {
    local target="$1"
    if [[ -n "$DEVID" ]]; then
        codesign_with_timestamp_retry --force --strip-disallowed-xattrs --options runtime --timestamp \
            --identifier "$NOW_PLAYING_ADAPTER_ID" --sign "$DEVID" "$target"
    elif legacy_identity_installed; then
        codesign --force --strip-disallowed-xattrs --identifier "$NOW_PLAYING_ADAPTER_ID" \
            --sign "$LEGACY_IDENTITY" "$target"
    else
        codesign --force --strip-disallowed-xattrs --identifier "$NOW_PLAYING_ADAPTER_ID" --sign - "$target"
    fi
}

sign_bundle() {
    local bundle="$1"
    local executable="$bundle/Contents/MacOS/$EXECUTABLE"
    local helper="$bundle/Contents/Library/LaunchServices/$FAN_HELPER_ID"
    local adapter="$bundle/Contents/Frameworks/$NOW_PLAYING_ADAPTER"

    if [[ -n "$DEVID" ]]; then
        echo "  signing with Developer ID (hardened runtime): $DEVID"
    elif legacy_identity_installed; then
        echo "  signing with legacy self-signed identity: $LEGACY_IDENTITY"
    else
        echo "  signing ad-hoc (no identity installed — run Tools/setup-signing.sh)"
    fi
    [[ -f "$helper" ]] && codesign_fan_helper "$helper"
    [[ -f "$adapter" ]] && codesign_now_playing_adapter "$adapter"
    codesign_app "$bundle"

    # If local filesystem metadata invalidates the first signature, sign once
    # more. The installed Developer bundle is signed again after the final copy.
    if ! codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
        echo "  re-signing after filesystem metadata settled"
        xattr -c -r "$bundle" 2>/dev/null || true
        [[ -f "$helper" ]] && codesign_fan_helper "$helper"
        [[ -f "$adapter" ]] && codesign_now_playing_adapter "$adapter"
        codesign_app "$bundle"
    fi
    [[ -f "$executable" ]] && codesign --verify --strict "$executable"
    [[ -f "$helper" ]] && codesign --verify --strict "$helper"
    [[ -f "$adapter" ]] && codesign --verify --strict "$adapter"
    codesign --verify --deep --strict "$bundle"
}

sign_installed_bundle() {
    local bundle="$1"
    wait_for_install_metadata "$bundle"
    sign_bundle "$bundle"
}

sign_bundle "$STAGE"

process_is_running() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pgrep -f "/Contents/MacOS/$proc" >/dev/null 2>&1
    else
        pgrep -x "$proc" >/dev/null 2>&1
    fi
}

stop_process() {
    local proc="$1"
    if (( ${#proc} > 15 )); then
        pkill -f "/Contents/MacOS/$proc" 2>/dev/null || true
    else
        pkill -x "$proc" 2>/dev/null || true
    fi
    for _ in {1..50}; do
        if ! process_is_running "$proc"; then
            return 0
        fi
        sleep 0.1
    done
    echo "✗ $proc is still running — quit it and retry" >&2
    return 1
}

wait_for_install_metadata() {
    local bundle="$1"
    local missing
    for _ in {1..50}; do
        missing=0
        while IFS= read -r file; do
            if ! xattr -p com.apple.provenance "$file" >/dev/null 2>&1; then
                missing=1
                break
            fi
        done < <(find "$bundle/Contents" -type f ! -path "*/_CodeSignature/*")
        if (( missing == 0 )); then
            return 0
        fi
        sleep 0.1
    done
}

# Installed development builds only need the copy in /Applications. Retaining
# another app in each checkout pollutes application search with stale builds.
if (( DEV )); then
    for old_bundle in "build/stage/$APP_NAME.app" "build/stage.noindex/$APP_NAME.app"; do
        if [[ -d "$old_bundle" ]]; then
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
                -u "$PWD/$old_bundle" >/dev/null 2>&1 || true
            rm -rf "$old_bundle"
        fi
    done
fi

if (( !DEV || !INSTALL )); then
    STAGE_DIRECTORY="build/stage"
    (( DEV )) && STAGE_DIRECTORY="build/stage.noindex"
    mkdir -p "$STAGE_DIRECTORY"
    BUILD_STAGE="$STAGE_DIRECTORY/$APP_NAME.app"
    rm -rf "$BUILD_STAGE"
    ditto --noextattr --noqtn "$STAGE" "$BUILD_STAGE"
    xattr -c -r "$BUILD_STAGE" 2>/dev/null || true
    if ! codesign --verify --deep --strict "$BUILD_STAGE" >/dev/null 2>&1; then
        if xattr -lr "$BUILD_STAGE" 2>/dev/null | grep -Eq 'com\.apple\.(FinderInfo|ResourceFork|provenance|fileprovider)'; then
            echo "  staging copy has local filesystem metadata; temp bundle was verified"
        else
            codesign --verify --deep --strict "$BUILD_STAGE"
        fi
    fi
    echo "✓ Bundle ready: $BUILD_STAGE"
fi

if (( INSTALL )); then
    echo "▸ Installing into /Applications…"
    stop_process "$EXECUTABLE"
    # Only an official install replaces the pre-rename official apps. The
    # Developer variant must coexist with them just as it does with SasNotch.
    if (( ! DEV )); then
        for legacy in "SasNotchLegacy:SasNotchLegacy" "SasNotch Utils:SasNotchUtils"; do
            name="${legacy%%:*}"; proc="${legacy##*:}"
            if [[ -d "/Applications/$name.app" ]]; then
                stop_process "$proc"
                rm -rf "/Applications/$name.app"
                echo "  (legacy $name.app removed)"
            fi
        done
    fi
    INSTALL_DEST="/Applications/$APP_NAME.app"
    rm -rf "$INSTALL_DEST"
    ditto --noextattr --noqtn "$STAGE" "$INSTALL_DEST"
    sign_installed_bundle "$INSTALL_DEST"
    echo "✓ Installed: $INSTALL_DEST"
fi
