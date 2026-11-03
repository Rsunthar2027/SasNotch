// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Modified for SasNotch by SasNotch contributors, 2026

import AVFoundation
import SwiftUI

struct NotchCameraView: View {
    let size: CGSize
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        Group {
            if service.isEmbeddedPresented {
                // The preview takes the whole page; its camera picker, shutter
                // and stop button sit in the island's top row, clear of the image.
                let preview = NotchLayout.cameraPreviewSize(in: size)
                CameraPreviewView(size: preview, showsCameraMenu: false)
                    .overlay { NotchMirrorSelfieFeedback(size: preview) }
            } else {
                HStack(spacing: 16) {
                    Image(systemName: "web.camera").font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                        .frame(width: 56, height: 56)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(text.cameraHint).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(text.startCamera, action: service.showEmbedded)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { service.hideEmbedded() }
    }
}

/// The camera the mirror shows, in the island's top row while it runs with
/// more than one camera around: the current one's name, cut short beside the
/// camera, over a native menu of them all.
struct NotchCameraChooser: View {
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    private var strings: CameraPreviewFeatureStrings { FeatureStrings.cameraPreview(l10n.language) }

    private var current: String {
        service.devices.first { $0.uniqueID == service.selectedDeviceID }?.localizedName ?? strings.cameraMenuLabel
    }

    var body: some View {
        if service.isEmbeddedPresented, service.state == .running, service.session != nil, service.devices.count > 1 {
            NotchMenuButton(title: strings.cameraMenuLabel, items: service.devices.map { device in
                NotchMenuItem(title: device.localizedName, checked: device.uniqueID == service.selectedDeviceID) {
                    service.selectCamera(device)
                }
            }, cornerRadius: 9) {
                NotchBandMenuLabel(title: current)
            }
            .help(current)
            .accessibilityValue(current)
        }
    }
}

/// Takes a selfie from the island's top row, beside the stop button and so
/// next to the lens: the image on screen, copied at once. While the camera is
/// starting, missing or not allowed, the button stays in place, dimmed, and
/// its tooltip says why.
struct NotchCameraShutterButton: View {
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var selfie = MirrorSelfieService.shared

    var body: some View {
        if service.isEmbeddedPresented {
            let shutter = service.selfieShutter
            let copied = selfie.feedback?.outcome.copiedImage == true
            NotchIconButton(symbol: copied ? "checkmark" : "camera", title: shutter.title,
                            action: service.takeSelfie)
                .disabled(!shutter.isEnabled)
        }
    }
}

/// The selfie's answer over the image: a flash as the photo is taken and a
/// short confirmation along the bottom, gone after a moment. It never takes a
/// click, and VoiceOver hears the same words as an announcement.
struct NotchMirrorSelfieFeedback: View {
    let size: CGSize
    @ObservedObject private var selfie = MirrorSelfieService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = 0.0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.opacity(flash)
            if let feedback = selfie.feedback {
                Label(feedback.outcome.message, systemImage: feedback.outcome.symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding([.horizontal, .bottom], 10)
                    .transition(.opacity)
                    .id(feedback.id)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selfie.feedback)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: selfie.feedback) { _, feedback in
            guard let feedback, feedback.outcome.flashes else { return }
            // Softer with Reduce Motion, so the image never jumps to white.
            flash = reduceMotion ? 0.3 : 0.85
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: reduceMotion ? 0.25 : 0.45)) { flash = 0 }
            }
        }
    }
}

/// Stops the mirror from the island's top row: a glyph beside the camera,
/// where a word may not fit, and the word itself across a full row.
struct NotchCameraStopButton: View {
    @ObservedObject private var service = CameraPreviewService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchBand) private var band

    var body: some View {
        if service.isEmbeddedPresented {
            let title = FeatureStrings.notchActivities(l10n.language).stopCamera
            if band.besideCamera {
                NotchIconButton(symbol: "video.slash", title: title, action: service.hideEmbedded)
            } else {
                NotchPillButton(title: title, prominent: true, action: service.hideEmbedded)
            }
        }
    }
}
