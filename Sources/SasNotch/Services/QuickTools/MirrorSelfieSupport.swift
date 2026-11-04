// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// The Mirror's selfie in words. English only, like everything else SasNotch
/// added on top of the upstream app.
enum MirrorSelfieText {
    static let takeSelfie = "Take Selfie"
    static let allowCamera = "Allow Camera Access"
    static let waiting = "Waiting for the camera"
    static let noCamera = "Connect a camera to take a selfie"
    static let denied = "Turn on camera access in System Settings to take a selfie"
    static let copied = "Copied"
    static let saved = "Copied and saved to Downloads"
    static let notSaved = "Copied, but not saved to Downloads"
    static let failed = "No picture yet. Try again."
    static let saveToDownloads = "Also save selfies to Downloads"
    static let saveToDownloadsCaption = "The camera button in Mirror copies the photo. This also keeps a PNG in your Downloads folder."
    static let fileNamePrefix = "SasNotch Selfie"
}

/// The camera permission as AVFoundation reports it, without the framework,
/// so the shutter's mapping can be tested on its own.
enum MirrorCameraAccess: Equatable {
    case notDetermined, authorized, denied, restricted
}

/// What the Mirror's shutter offers, from the camera permission and whether
/// the session is delivering frames.
enum MirrorSelfieShutter: Equatable, CaseIterable {
    /// The camera runs: one click takes the selfie.
    case ready
    /// Never asked: the click asks for the camera.
    case requestAccess
    /// Turned off in System Settings, or restricted. The page explains it and
    /// links to Privacy & Security › Camera; the shutter waits.
    case denied
    /// Allowed, but there is no camera to take a picture with.
    case noCamera
    /// Allowed, while the session starts, after it was interrupted, or once it
    /// stopped. Nothing to capture yet, and nothing to crash on.
    case notRunning

    static func resolve(access: MirrorCameraAccess, cameraMissing: Bool, running: Bool) -> MirrorSelfieShutter {
        switch access {
        case .notDetermined: return .requestAccess
        case .denied, .restricted: return .denied
        case .authorized:
            if cameraMissing { return .noCamera }
            return running ? .ready : .notRunning
        }
    }

    var isEnabled: Bool { self == .ready || self == .requestAccess }

    /// The button's name for VoiceOver and its tooltip. A disabled shutter
    /// says why, which is the hint a sighted user gets on hover.
    var title: String {
        switch self {
        case .ready: return MirrorSelfieText.takeSelfie
        case .requestAccess: return MirrorSelfieText.allowCamera
        case .denied: return MirrorSelfieText.denied
        case .noCamera: return MirrorSelfieText.noCamera
        case .notRunning: return MirrorSelfieText.waiting
        }
    }
}

/// How a selfie ended, as the island says it for a moment.
enum MirrorSelfieOutcome: Equatable {
    case copied, saved, notSaved, failed

    var message: String {
        switch self {
        case .copied: return MirrorSelfieText.copied
        case .saved: return MirrorSelfieText.saved
        case .notSaved: return MirrorSelfieText.notSaved
        case .failed: return MirrorSelfieText.failed
        }
    }

    var symbol: String {
        switch self {
        case .copied, .saved: return "checkmark"
        case .notSaved, .failed: return "exclamationmark.triangle"
        }
    }

    /// The photo reached the clipboard, whatever became of the file.
    var copiedImage: Bool { self != .failed }

    /// The image flashes once, as the photo is taken. The word about the file
    /// in Downloads follows the copy without a second flash.
    var flashes: Bool { self == .copied }
}

/// One confirmation on screen. A new id restarts the flash and the timer even
/// when two selfies in a row end the same way.
struct MirrorSelfieFeedback: Equatable {
    let id: UUID
    let outcome: MirrorSelfieOutcome
}

/// File names for selfies kept in Downloads: the screenshot pattern with its
/// own prefix, "SasNotch Selfie 2026-11-02 at 14.05.33.png".
enum MirrorSelfieNaming {
    static func fileName(for date: Date) -> String {
        ScreenshotSupport.fileName(prefix: MirrorSelfieText.fileNamePrefix, date: date)
    }

    /// The first name nothing uses yet, " 2", " 3" and on after a taken one.
    /// Nil when every candidate is taken, so a selfie never replaces a file.
    static func availableName(for date: Date, exists: (String) -> Bool) -> String? {
        let name = ScreenshotSupport.uniqueFileName(fileName(for: date), exists: exists)
        return exists(name) ? nil : name
    }
}
