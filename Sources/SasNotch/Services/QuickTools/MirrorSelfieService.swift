// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import AppKit
import AVFoundation
import CoreImage

/// Keeps the Mirror's newest camera frame, so a selfie is the image on screen
/// at the click. Each frame only replaces a reference; turning one into a
/// picture waits for the shutter. It exists only with the island's capture
/// session, so a closed Mirror costs nothing.
final class MirrorFrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.sasnotch.app.mirror-frames", qos: .userInitiated)
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// On the session queue, inside the session's configuration.
    func attach(to session: AVCaptureSession) {
        // A late frame is dropped rather than queued: only the newest counts.
        output.alwaysDiscardsLateVideoFrames = true
        // The camera's own 4:2:0 frames need no conversion on the way here;
        // Core Image reads them directly when a selfie is taken.
        let native = [kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        if let format = native.first(where: output.availableVideoPixelFormatTypes.contains) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: format]
        }
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
    }

    /// Frames arrive as the camera sees them, and the selfie is flipped once
    /// when it is taken instead of on every frame. A new camera brings a new
    /// connection, so this runs after every change of input.
    func unmirrorConnection() {
        guard let connection = output.connection(with: .video), connection.isVideoMirroringSupported else { return }
        if connection.automaticallyAdjustsVideoMirroring {
            connection.automaticallyAdjustsVideoMirroring = false
        }
        if connection.isVideoMirrored {
            connection.isVideoMirrored = false
        }
    }

    func discardFrame() {
        lock.withLock { latest = nil }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.withLock { latest = buffer }
    }

    /// The newest frame flipped the way the preview flips it, as a mirror
    /// shows a face. Nil before the first frame and after the session stops.
    /// Called off the main thread.
    func mirroredSnapshot() -> CGImage? {
        guard let buffer = lock.withLock({ latest }) else { return nil }
        let image = CIImage(cvPixelBuffer: buffer).oriented(.upMirrored)
        return Self.context.createCGImage(image, from: image.extent)
    }
}

/// Takes the Mirror's selfie: the frame on screen, flipped like the preview,
/// copied as PNG and TIFF so Messages, Slack and Notes all paste it, and also
/// kept in Downloads when the user turned that on. Main thread, like the
/// island's other services; the pixels and the file go through a work queue.
final class MirrorSelfieService: ObservableObject {
    static let shared = MirrorSelfieService()

    /// The confirmation the island shows, cleared after a moment.
    @Published private(set) var feedback: MirrorSelfieFeedback?
    private var capturing = false
    private let work = DispatchQueue(label: "com.sasnotch.app.mirror-selfie", qos: .userInitiated)
    private static let feedbackDuration: TimeInterval = 1.6

    private init() {}

    /// Without a frame (the session not running yet, or gone) the island says
    /// so and nothing else happens.
    func capture(from grabber: MirrorFrameGrabber?) {
        guard !capturing else { return }
        guard let grabber else {
            show(.failed)
            return
        }
        capturing = true
        let date = Date()
        let savesToDownloads = UserDefaults.standard.bool(forKey: DefaultsKey.notchSelfieSavesToDownloads)
        work.async {
            let image = grabber.mirroredSnapshot()
            let png = image.flatMap { ScreenshotRenderer.pngData(from: $0, scale: 1) }
            let tiff = image.flatMap { ScreenshotRenderer.tiffData(from: $0, scale: 1) }
            DispatchQueue.main.async {
                self.capturing = false
                guard let png,
                      ScreenshotEditorController.copyClipboardPayload(.init(png: png, tiff: tiff))
                else {
                    self.show(.failed)
                    return
                }
                self.show(.copied)
                guard savesToDownloads else { return }
                // The first save may wait on the system's Downloads prompt;
                // the copy above never does.
                self.work.async {
                    let saved = Self.saveToDownloads(png, date: date)
                    DispatchQueue.main.async { self.show(saved ? .saved : .notSaved) }
                }
            }
        }
    }

    private func show(_ outcome: MirrorSelfieOutcome) {
        let feedback = MirrorSelfieFeedback(id: UUID(), outcome: outcome)
        self.feedback = feedback
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: outcome.message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.feedbackDuration) {
            if self.feedback?.id == feedback.id { self.feedback = nil }
        }
    }

    /// Writes under the first free name and never replaces a file: a file
    /// that appears between the check and the write makes the write fail,
    /// and the next name is tried.
    private static func saveToDownloads(_ png: Data, date: Date) -> Bool {
        let manager = FileManager.default
        guard let folder = manager.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return false }
        var claimed = Set<String>()
        for _ in 0..<5 {
            guard let name = MirrorSelfieNaming.availableName(for: date, exists: {
                claimed.contains($0) || manager.fileExists(atPath: folder.appendingPathComponent($0).path)
            }) else { return false }
            do {
                try png.write(to: folder.appendingPathComponent(name), options: .withoutOverwriting)
                return true
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                claimed.insert(name)
            } catch {
                return false
            }
        }
        return false
    }
}
