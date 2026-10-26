// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2024-2026 Atoll Contributors
// Copyright (C) 2026 SasNotch contributors
//
// Adapted from Atoll's PrivacyIndicatorManager, CameraMonitor and
// MicrophoneMonitor (Ebullioscopic/Atoll, GPL-3.0-or-later): devices report
// "running somewhere" when any process uses them, so no permission is needed.

import AppKit
import CoreAudio
import CoreMediaIO

/// Shows a notice in the island when any app starts using the camera or a
/// microphone, as the island on a phone does with its colored dots.
/// Main thread only, like the island it reports to.
final class PrivacyIndicatorService: ObservableObject {
    static let shared = PrivacyIndicatorService()

    @Published private(set) var cameraInUse = false
    @Published private(set) var microphoneInUse = false

    private var running = false
    private var cameraDevices: [CMIOObjectID] = []
    private var microphoneDevices: [AudioObjectID] = []
    private var pollTimer: Timer?

    private init() {}

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchPrivacyEnabled)
    }

    func syncWithPreferences() {
        Self.isEnabled() ? start() : stop()
    }

    func start() {
        guard !running else { return }
        running = true
        cameraDevices = Self.cameraDeviceIDs()
        microphoneDevices = Self.inputDeviceIDs()
        // Taking the starting state silently: only a change is news.
        cameraInUse = cameraDevices.contains(where: Self.cameraIsRunning)
        microphoneInUse = microphoneDevices.contains(where: Self.audioDeviceIsRunning)
        // Both frameworks also offer listeners, but their callbacks arrive
        // on arbitrary threads and the device lists change as devices come
        // and go; a light poll covers both and costs a few property reads.
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        guard running else { return }
        running = false
        pollTimer?.invalidate()
        pollTimer = nil
        cameraInUse = false
        microphoneInUse = false
    }

    private func poll() {
        guard running else { return }
        cameraDevices = Self.cameraDeviceIDs()
        microphoneDevices = Self.inputDeviceIDs()
        let camera = cameraDevices.contains(where: Self.cameraIsRunning)
        let microphone = microphoneDevices.contains(where: Self.audioDeviceIsRunning)
        let cameraStarted = camera && !cameraInUse
        let microphoneStarted = microphone && !microphoneInUse
        cameraInUse = camera
        microphoneInUse = microphone
        guard cameraStarted || microphoneStarted else { return }
        // SasNotch's own Mirror is the camera the person is looking at.
        if cameraStarted, !microphoneStarted, CameraPreviewService.shared.state == .running { return }
        let title = camera && microphone ? PrivacyText.both
            : camera ? PrivacyText.camera : PrivacyText.microphone
        NotchService.shared.show(NotchNotice(event: .privacy, title: title, detail: PrivacyText.inUse,
                                             symbol: camera ? "video.fill" : "mic.fill"))
    }

    // MARK: Camera (CoreMediaIO)

    static func cameraDeviceIDs() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size)
                == OSStatus(kCMIOHardwareNoError), size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &size, &devices)
                == OSStatus(kCMIOHardwareNoError) else { return [] }
        return devices
    }

    static func cameraIsRunning(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, size, &size, &running)
                == OSStatus(kCMIOHardwareNoError) else { return false }
        return running != 0
    }

    // MARK: Microphone (Core Audio)

    static func inputDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
                == noErr else { return [] }
        return devices.filter(hasInputStreams)
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    static func audioDeviceIsRunning(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}

/// Privacy indicator wording, added by SasNotch. English for now.
enum PrivacyText {
    static let camera = "Camera"
    static let microphone = "Microphone"
    static let both = "Camera & mic"
    static let inUse = "In use"
    static let settingsToggle = "Show camera and microphone use"
    static let settingsCaption = "Shows when any app starts using the camera or a microphone."
}
