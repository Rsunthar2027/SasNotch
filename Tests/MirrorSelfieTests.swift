// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// The Mirror selfie's pure parts: the name a selfie is saved under, the
/// suffix that keeps it from replacing a file, what the shutter offers for
/// each camera permission, and the setting's default.
enum MirrorSelfieTests {
    static func run(_ suite: TestSuite) {
        naming(suite)
        shutter(suite)
        outcome(suite)
        setting(suite)
    }

    /// 2 November 2026, 14:05:33 on this Mac's clock, which is the clock the
    /// file name is written in.
    private static var takenAt: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 2
        components.hour = 14
        components.minute = 5
        components.second = 33
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private static func naming(_ suite: TestSuite) {
        let base = "SasNotch Selfie 2026-11-02 at 14.05.33.png"
        suite.expect(MirrorSelfieNaming.fileName(for: takenAt) == base,
                     "a selfie is named after the moment it was taken: \(MirrorSelfieNaming.fileName(for: takenAt))")
        suite.expect(!base.contains(":") && !base.contains("/"),
                     "the name has nothing Finder would show differently or refuse")
        suite.expect(MirrorSelfieNaming.availableName(for: takenAt) { _ in false } == base,
                     "a free name is used as it is")
        var taken: Set<String> = [base]
        suite.expect(MirrorSelfieNaming.availableName(for: takenAt, exists: taken.contains)
                        == "SasNotch Selfie 2026-11-02 at 14.05.33 2.png",
                     "a second selfie in the same second gets \" 2\" before the extension")
        taken.insert("SasNotch Selfie 2026-11-02 at 14.05.33 2.png")
        suite.expect(MirrorSelfieNaming.availableName(for: takenAt, exists: taken.contains)
                        == "SasNotch Selfie 2026-11-02 at 14.05.33 3.png",
                     "the suffix counts on past the names already taken")
        taken = ["SasNotch Selfie 2026-11-02 at 14.05.33 2.png"]
        suite.expect(MirrorSelfieNaming.availableName(for: takenAt, exists: taken.contains) == base,
                     "a taken suffix alone leaves the plain name free")
        suite.expect(MirrorSelfieNaming.availableName(for: takenAt) { _ in true } == nil,
                     "with every candidate taken there is no name, so nothing is ever replaced")
    }

    private static func shutter(_ suite: TestSuite) {
        let flags = [false, true]
        for missing in flags {
            for running in flags {
                suite.expect(MirrorSelfieShutter.resolve(access: .notDetermined, cameraMissing: missing,
                                                         running: running) == .requestAccess,
                             "never asked, the shutter asks for the camera (missing \(missing), running \(running))")
                for access in [MirrorCameraAccess.denied, .restricted] {
                    suite.expect(MirrorSelfieShutter.resolve(access: access, cameraMissing: missing,
                                                             running: running) == .denied,
                                 "\(access) camera access waits on System Settings (missing \(missing), running \(running))")
                }
                suite.expect(MirrorSelfieShutter.resolve(access: .authorized, cameraMissing: true,
                                                         running: running) == .noCamera,
                             "allowed without a camera, the shutter has nothing to take (running \(running))")
            }
        }
        suite.expect(MirrorSelfieShutter.resolve(access: .authorized, cameraMissing: false, running: true) == .ready,
                     "allowed and running, one click takes the selfie")
        suite.expect(MirrorSelfieShutter.resolve(access: .authorized, cameraMissing: false, running: false)
                        == .notRunning,
                     "allowed while the session starts or after it stopped, the shutter waits")

        let enabled = MirrorSelfieShutter.allCases.filter(\.isEnabled)
        suite.expect(enabled == [.ready, .requestAccess],
                     "only a running camera or an unanswered permission makes the shutter clickable")
        suite.expect(MirrorSelfieShutter.ready.title == "Take Selfie",
                     "the running shutter is named for what it does")
        suite.expect(MirrorSelfieShutter.requestAccess.title == "Allow Camera Access",
                     "the unasked shutter says it asks for the camera")
        let titles = MirrorSelfieShutter.allCases.map(\.title)
        suite.expect(titles.allSatisfy { !$0.isEmpty } && Set(titles).count == titles.count,
                     "every shutter state has its own name and tooltip")
        suite.expect(MirrorSelfieShutter.noCamera.title.localizedCaseInsensitiveContains("camera")
                        && MirrorSelfieShutter.denied.title.contains("System Settings"),
                     "a dimmed shutter says what is missing")
    }

    private static func outcome(_ suite: TestSuite) {
        suite.expect(MirrorSelfieOutcome.copied.message == "Copied",
                     "a selfie on the clipboard is confirmed in one word")
        suite.expect([MirrorSelfieOutcome.copied, .saved, .notSaved, .failed].filter(\.flashes) == [.copied],
                     "the image flashes once per photo, not again when the file is written")
        suite.expect([MirrorSelfieOutcome.copied, .saved, .notSaved].allSatisfy(\.copiedImage)
                        && !MirrorSelfieOutcome.failed.copiedImage,
                     "only a missing frame leaves the clipboard as it was")
        suite.expect(Set([MirrorSelfieOutcome.copied, .saved, .notSaved, .failed].map(\.message)).count == 4,
                     "each ending reads differently")
        let first = MirrorSelfieFeedback(id: UUID(), outcome: .copied)
        let second = MirrorSelfieFeedback(id: UUID(), outcome: .copied)
        suite.expect(first != second, "two selfies in a row are two confirmations, so the second flashes too")
    }

    private static func setting(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchSelfieSavesToDownloads] as? Bool == false,
                     "selfies stay on the clipboard only until the user asks for Downloads")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchSelfieSavesToDownloads),
                     "the Downloads choice travels with the settings backup")
        suite.expect(MirrorSelfieText.saveToDownloads == "Also save selfies to Downloads",
                     "the setting reads as the owner named it")
    }
}
