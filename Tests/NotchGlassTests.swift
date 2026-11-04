// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import CoreGraphics
import Foundation

/// The island's Liquid Glass: its variant setting, its concentric radii, the
/// black it keeps over the camera, and what it does under accessibility
/// settings. The glass itself is compositor-backed; these pin what decides it.
enum NotchGlassTests {
    static func run(_ suite: TestSuite) {
        style(suite)
        radii(suite)
        seam(suite)
        contrast(suite)
        realGlass(suite)
    }

    private static func style(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchGlassStyle] as? String == NotchGlassStyle.clear.rawValue
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchGlassStyle),
                     "the island's glass starts Regular and its style travels with settings backups")
        suite.expect(NotchGlassStyle.fallback == .clear && NotchGlassStyle.allCases == [.regular, .clear],
                     "the choice is Clear, the default, or Regular")
        suite.expect(NotchGlassStyle.sanitized("clear") == .clear && NotchGlassStyle.sanitized("regular") == .regular,
                     "a stored style reads back as itself")
        for raw in [nil, "", "Clear", "REGULAR", "frosted", "identity"] {
            suite.expect(NotchGlassStyle.sanitized(raw) == .clear,
                         "an unknown stored style draws the default glass: \(raw ?? "nil")")
        }
        let domain = "sasnotch.tests.glass-style.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchGlassStyle.stored(in: defaults) == .clear, "nothing stored reads as the default")
        defaults.set("regular", forKey: DefaultsKey.notchGlassStyle)
        suite.expect(NotchGlassStyle.stored(in: defaults) == .regular, "a stored choice is what the island draws")
        defaults.set("mirror", forKey: DefaultsKey.notchGlassStyle)
        suite.expect(NotchGlassStyle.stored(in: defaults) == .clear, "a hand-edited value falls back")
        suite.expect(NotchGlassStyle.regular.title == "Regular" && NotchGlassStyle.clear.title == "Clear"
                     && NotchGlassText.style == "Glass style"
                     && NotchGlassText.requiresMacOS26 == "Liquid Glass requires macOS 26",
                     "the setting and the note before macOS 26 read as written")
    }

    private static func radii(_ suite: TestSuite) {
        suite.expect(NotchGlassGeometry.concentricRadius(outer: 28, inset: 16) == 12,
                     "a tile takes the outer radius minus the padding")
        suite.expect(NotchGlassGeometry.concentricRadius(outer: 10, inset: 16) == 0,
                     "padding past the outer radius leaves a square corner, never a negative one")
        suite.expect(NotchGlassGeometry.concentricRadius(outer: 10, inset: 16, minimum: 4) == 4,
                     "a minimum holds where the curve would vanish")
        suite.expect(NotchGlassGeometry.concentricRadius(outer: 12, inset: -5) == 12,
                     "a negative inset cannot grow the radius")
        suite.expect(NotchGlassGeometry.concentricRadius(outer: .nan, inset: 4, minimum: 3) == 3
                     && NotchGlassGeometry.concentricRadius(outer: 12, inset: .infinity, minimum: 3) == 3
                     && NotchGlassGeometry.concentricRadius(outer: .nan, inset: 4, minimum: .nan) == 0,
                     "a broken measurement falls back rather than reaching the layout")
        suite.expect(NotchGlassGeometry.tileRadius(surfaceRadius: 28) == 28 - NotchLayout.bottomInset,
                     "a card on the open island is concentric with the island over the page's inset")
        suite.expect(NotchGlassGeometry.tileRadius(surfaceRadius: 12) == 10,
                     "a tight island corner keeps its cards visibly rounded")
        suite.expect(NotchGlassGeometry.innerRadius(cardRadius: 18, padding: 12) == 6
                     && NotchGlassGeometry.innerRadius(cardRadius: 12, padding: 12) == 4,
                     "what lies inside a padded card is concentric with the card")
    }

    private static func seam(_ suite: TestSuite) {
        let housing = CGSize(width: 180, height: 37)
        suite.expect(NotchGlassSeam.size(cutout: housing, floats: false) == housing,
                     "the black is the camera housing's rect")
        suite.expect(NotchGlassSeam.size(cutout: .zero, floats: false) == .zero
                     && NotchGlassSeam.size(cutout: housing, floats: true) == .zero
                     && NotchGlassSeam.size(cutout: CGSize(width: CGFloat.nan, height: 37), floats: false) == .zero,
                     "with no housing to hide the island is glass from its top edge")
        let notched = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 37,
                                    cameraWidth: 180, menuBarHeight: 37, cameraFit: NotchCameraFit(width: 10, height: 6))
        suite.expect(notched.physicalCutout == housing && notched.cameraWidth > housing.width,
                     "a wider resting island in Settings leaves the black at the hardware's size")
        let plain = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
                                  cameraWidth: 0, menuBarHeight: 24)
        suite.expect(plain.physicalCutout == .zero, "a display without a camera housing has no black")
        suite.expect(NotchGlassSeam.restingOpacity(openness: 1) == 0,
                     "open glass has no black outside the housing")
        suite.expect(NotchGlassSeam.restingOpacity(openness: 0) == 1 && NotchGlassSeam.restingOpacity(openness: .nan) == 1,
                     "a glass still closed, or an unreadable fade, matches the resting black")
        suite.expect(NotchGlassSeam.restingOpacity(openness: 0.25) == 0.75, "the black lets go as the glass opens")
        let components = (try? String(contentsOfFile: "Sources/SasNotch/UI/Notch/NotchComponents.swift", encoding: .utf8)) ?? ""
        suite.expect(components.contains("UnevenRoundedRectangle(bottomLeadingRadius: NotchGlassSeam.cornerRadius")
                     && !components.contains("NotchGlassSeam.stops"),
                     "no gradient runs from the housing into the body")
    }

    private static func contrast(_ suite: TestSuite) {
        suite.expect(NotchGlassContrast.surfaceTintOpacity(increasedContrast: false) == 0
                     && NotchGlassContrast.tileTintOpacity(increasedContrast: false) == 0,
                     "the glass is untinted at ordinary contrast")
        suite.expect(NotchGlassContrast.surfaceTintOpacity(increasedContrast: true) > 0
                     && NotchGlassContrast.tileTintOpacity(increasedContrast: true) > 0,
                     "Increase Contrast tints the glass more opaquely")
        suite.expect(NotchGlassContrast.strokeOpacity(increasedContrast: false) == 0
                     && NotchGlassContrast.strokeOpacity(increasedContrast: true) >= 0.5
                     && NotchGlassContrast.strokeOpacity(increasedContrast: true, selected: true)
                        > NotchGlassContrast.strokeOpacity(increasedContrast: true),
                     "Increase Contrast outlines each lens, the selected one more strongly")
    }

    /// The compiler proves the API exists; this proves the island uses it, in
    /// place of the imitation it replaced.
    private static func realGlass(_ suite: TestSuite) {
        func source(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
        let components = source("Sources/SasNotch/UI/Notch/NotchComponents.swift")
        let glass = source("Sources/SasNotch/UI/Notch/NotchGlass.swift")
        let general = source("Sources/SasNotch/UI/Settings/GeneralSettings.swift")
        let view = source("Sources/SasNotch/UI/Notch/NotchView.swift")
        suite.expect(components.contains(".glassEffect(surfaceGlass, in: shape)") && !components.contains("func shade("),
                     "the island's surface is Apple's glass in its own shape, with no shade laid over it")
        suite.expect(glass.contains(".glass.tint(tinted).interactive(interactive && !reduceMotion)")
                     && glass.contains("GlassEffectContainer(spacing: spacing)")
                     && glass.contains(".glassEffectID(id, in: namespace)")
                     && glass.contains(".glassEffectUnion(id: union, namespace: namespace)"),
                     "tiles are interactive glass that merge and morph through Apple's own API")
        suite.expect(glass.contains("reduceMotion ? .materialize : .matchedGeometry")
                     && NotchGlassMotion.morph(reduceMotion: true) == nil
                     && NotchGlassMotion.morph(reduceMotion: false) != nil,
                     "Reduce Motion takes the morph and its spring away")
        suite.expect(glass.contains("glassSurface, !reduceTransparency")
                     && glass.contains("reduceTransparency ? Color(white: offGlass)"),
                     "Reduce Transparency leaves solid tiles on a solid island")
        suite.expect(general.contains("NotchGlassText.requiresMacOS26") && general.contains("NotchGlassText.style"),
                     "Settings offers the glass style on macOS 26 and the note before it")
        suite.expect(view.contains(".environment(\\.colorScheme, surfaceScheme)")
                     && view.contains("band.besideCamera ? .dark : surfaceScheme"),
                     "the island adapts on glass, and stays dark on black, frosted and the camera's seam")
    }
}
