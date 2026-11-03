// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import CoreGraphics
import Foundation

/// The variant of Apple's Liquid Glass the open island uses on macOS 26.
/// Regular is the system's default material; Clear lets more of what lies
/// behind the island through, as Apple's clear glass does over media.
enum NotchGlassStyle: String, CaseIterable, Identifiable {
    case regular
    case clear

    var id: String { rawValue }

    static let fallback: NotchGlassStyle = .regular

    /// An unknown or hand-edited value never breaks the island; it draws the
    /// default glass.
    static func sanitized(_ raw: String?) -> NotchGlassStyle {
        guard let raw, let style = NotchGlassStyle(rawValue: raw) else { return fallback }
        return style
    }

    static func stored(in defaults: UserDefaults = .standard) -> NotchGlassStyle {
        sanitized(defaults.string(forKey: DefaultsKey.notchGlassStyle))
    }

    var title: String {
        switch self {
        case .regular: return NotchGlassText.regular
        case .clear: return NotchGlassText.clear
        }
    }
}

/// English-only text for the island's glass settings.
enum NotchGlassText {
    static let style = "Glass style"
    static let regular = "Regular"
    static let clear = "Clear"
    static let styleCaption = "Regular adapts to what's behind the island. Clear lets more of it show through."
    static let requiresMacOS26 = "Liquid Glass requires macOS 26"
}

/// Corner radii that stay concentric with the shape around them, as Apple
/// lays out controls on glass: a tile inset into a container takes the
/// container's radius minus the inset, so the two curves keep one centre.
enum NotchGlassGeometry {
    /// `outer` minus `inset`, never below `minimum`. A broken measurement
    /// falls back to `minimum` rather than reaching the layout.
    static func concentricRadius(outer: CGFloat, inset: CGFloat, minimum: CGFloat = 0) -> CGFloat {
        let floor = minimum.isFinite ? max(0, minimum) : 0
        guard outer.isFinite, inset.isFinite else { return floor }
        return max(floor, outer - max(0, inset))
    }

    /// The radius of a card laid straight on the open island, from the
    /// island's own corner and the page's inset from its bottom edge.
    static func tileRadius(surfaceRadius: CGFloat) -> CGFloat {
        concentricRadius(outer: surfaceRadius, inset: NotchLayout.bottomInset, minimum: 10)
    }

    /// Inside a card padded by `padding`.
    static func innerRadius(cardRadius: CGFloat, padding: CGFloat) -> CGFloat {
        concentricRadius(outer: cardRadius, inset: padding, minimum: 4)
    }
}

/// The black kept over the physical camera on Liquid Glass. Only a display
/// with a camera housing has a seam to hide; a capsule or an island on a
/// display without one is glass from its top edge.
enum NotchGlassSeam {
    /// Short enough that the page below the camera's row sits on clear glass.
    static let rampLength: CGFloat = 10

    static func height(stripHeight: CGFloat, isNotched: Bool, floats: Bool) -> CGFloat {
        guard isNotched, !floats, stripHeight.isFinite else { return 0 }
        return max(0, stripHeight)
    }

    /// Opaque over the camera strip, then released over `rampLength`.
    /// While the island opens, `openness` below 1 keeps the rest dark, so
    /// the last frames of a collapse already match the resting black.
    static func opacity(atDepth depth: CGFloat, seamHeight: CGFloat, openness: Double) -> Double {
        let open = openness.isFinite ? min(1, max(0, openness)) : 0
        guard seamHeight > 0 else { return 1 - open }
        guard depth > seamHeight else { return 1 }
        let ramp = Double(min(1, (depth - seamHeight) / rampLength))
        let eased = ramp * ramp * (3 - 2 * ramp)
        return 1 - open * eased
    }

    /// Gradient stops over an island `height` points tall, top to bottom.
    static func stops(height: CGFloat, seamHeight: CGFloat,
                      openness: Double) -> [(location: Double, opacity: Double)] {
        guard height > 0, height.isFinite else { return [(0, 1), (1, 1)] }
        let seam = seamHeight.isFinite ? max(0, seamHeight) : 0
        let depths = [0, seam] + (1...4).map { seam + rampLength * CGFloat($0) / 4 } + [height]
        return depths.filter { $0 >= 0 && $0 <= height }.map {
            (Double($0 / height), opacity(atDepth: $0, seamHeight: seam, openness: openness))
        }
    }
}

/// How the glass answers the accessibility settings. Reduce Transparency
/// never reaches here: the island and its tiles are solid then.
enum NotchGlassContrast {
    /// Increase Contrast lays a more opaque tint of the surface's own tone
    /// over the glass, so content reads against any wallpaper.
    static func surfaceTintOpacity(increasedContrast: Bool) -> Double { increasedContrast ? 0.55 : 0 }
    static func tileTintOpacity(increasedContrast: Bool) -> Double { increasedContrast ? 0.35 : 0 }
    /// The outline every tile and button on the glass carries.
    static func strokeOpacity(increasedContrast: Bool, selected: Bool = false) -> Double {
        increasedContrast ? (selected ? 0.75 : 0.5) : 0
    }
}
