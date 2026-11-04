// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import CoreGraphics
import Foundation

/// The variant of Apple's Liquid Glass the open island uses on macOS 26.
/// Clear, the default, lets what lies behind the island through; Regular is
/// the system's heavier material, which reads as a tinted panel.
enum NotchGlassStyle: String, CaseIterable, Identifiable {
    case regular
    case clear

    var id: String { rawValue }

    static let fallback: NotchGlassStyle = .clear

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

/// The black kept over the physical camera on Liquid Glass: the housing's own
/// rect and nothing else, so the glass starts right at its edge. Only a
/// display with a camera housing has one; a capsule or an island on a display
/// without one is glass from its top edge.
enum NotchGlassSeam {
    /// The housing's own curve, so the black never shows past the hardware.
    static let cornerRadius: CGFloat = 10

    static func size(cutout: CGSize, floats: Bool) -> CGSize {
        guard !floats, cutout.width.isFinite, cutout.height.isFinite, cutout.width > 0, cutout.height > 0 else { return .zero }
        return cutout
    }

    /// The rest of the island is black only while the glass opens or closes,
    /// so the last frames of a collapse match the resting black.
    static func restingOpacity(openness: Double) -> Double {
        openness.isFinite ? 1 - min(1, max(0, openness)) : 1
    }
}

/// How the glass answers the accessibility settings. Reduce Transparency
/// never reaches here: the island and its tiles are solid then.
enum NotchGlassContrast {
    /// Increase Contrast lays a more opaque tint of the surface's own tone
    /// over the glass, so content reads against any wallpaper.
    static func surfaceTintOpacity(increasedContrast: Bool) -> Double { increasedContrast ? 0.55 : 0 }
    /// Apple's guidance for clear glass over bright content: a light dimming
    /// of its own, so a tile's text reads over a white window. Regular has
    /// its own; only Increase Contrast adds to it.
    static func tileTintOpacity(increasedContrast: Bool, style: NotchGlassStyle = .regular) -> Double {
        if increasedContrast { return style == .clear ? 0.5 : 0.35 }
        return style == .clear ? 0.3 : 0
    }
    static let haloRadius: CGFloat = 2.5
    /// The halo behind glyphs on the glass, in the tone opposite the ink.
    static func haloOpacity(increasedContrast: Bool) -> Double { increasedContrast ? 0.85 : 0.5 }
    /// The outline every tile and button on the glass carries.
    static func strokeOpacity(increasedContrast: Bool, selected: Bool = false) -> Double {
        increasedContrast ? (selected ? 0.75 : 0.5) : 0
    }
}
