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
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchGlassStyle] as? String == NotchGlassStyle.regular.rawValue
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchGlassStyle),
                     "the island's glass starts Regular and its style travels with settings backups")
        suite.expect(NotchGlassStyle.fallback == .regular && NotchGlassStyle.allCases == [.regular, .clear],
                     "the choice is Regular, the default, or Clear")
        suite.expect(NotchGlassStyle.sanitized("clear") == .clear && NotchGlassStyle.sanitized("regular") == .regular,
                     "a stored style reads back as itself")
        for raw in [nil, "", "Clear", "REGULAR", "frosted", "identity"] {
            suite.expect(NotchGlassStyle.sanitized(raw) == .regular,
                         "an unknown stored style draws the default glass: \(raw ?? "nil")")
        }
        let domain = "sasnotch.tests.glass-style.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        suite.expect(NotchGlassStyle.stored(in: defaults) == .regular, "nothing stored reads as the default")
        defaults.set("clear", forKey: DefaultsKey.notchGlassStyle)
        suite.expect(NotchGlassStyle.stored(in: defaults) == .clear, "a stored choice is what the island draws")
        defaults.set("mirror", forKey: DefaultsKey.notchGlassStyle)
        suite.expect(NotchGlassStyle.stored(in: defaults) == .regular, "a hand-edited value falls back")
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
        suite.expect(NotchGlassSeam.height(stripHeight: 37, isNotched: true, floats: false) == 37,
                     "a camera housing keeps its strip black")
        suite.expect(NotchGlassSeam.height(stripHeight: 24, isNotched: false, floats: false) == 0
                     && NotchGlassSeam.height(stripHeight: 24, isNotched: true, floats: true) == 0
                     && NotchGlassSeam.height(stripHeight: .nan, isNotched: true, floats: false) == 0,
                     "with no housing to hide the island is glass from its top edge")
        let strip: CGFloat = 37
        suite.expect(NotchGlassSeam.opacity(atDepth: 0, seamHeight: strip, openness: 1) == 1
                     && NotchGlassSeam.opacity(atDepth: strip, seamHeight: strip, openness: 1) == 1,
                     "the camera strip stays solid black on open glass")
        suite.expect(NotchGlassSeam.opacity(atDepth: strip + NotchGlassSeam.rampLength, seamHeight: strip, openness: 1) == 0,
                     "below the seam the glass carries no shade")
        suite.expect(NotchGlassSeam.opacity(atDepth: 200, seamHeight: strip, openness: 0) == 1,
                     "a glass still closed matches the resting black")
        suite.expect(NotchGlassSeam.opacity(atDepth: 200, seamHeight: strip, openness: .nan) == 1,
                     "an unreadable fade stays black")
        suite.expect(NotchGlassSeam.opacity(atDepth: 0, seamHeight: 0, openness: 1) == 0
                     && NotchGlassSeam.opacity(atDepth: 0, seamHeight: 0, openness: 0.25) == 0.75,
                     "with no seam only the resting black is left, as the glass opens")
        let midway = NotchGlassSeam.opacity(atDepth: strip + NotchGlassSeam.rampLength / 2, seamHeight: strip, openness: 1)
        suite.expect(midway > 0 && midway < 1, "the seam eases out rather than ending in a line")
        suite.expect(strip + NotchGlassSeam.rampLength <= strip + 10 + 1,
                     "a page below the camera's row starts on clear glass")
        let stops = NotchGlassSeam.stops(height: 260, seamHeight: strip, openness: 1)
        suite.expect(stops.first?.location == 0 && stops.first?.opacity == 1 && stops.last?.location == 1
                     && stops.last?.opacity == 0,
                     "the stops run the island's height, from black to clear")
        suite.expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location <= $1.location && $0.opacity >= $1.opacity },
                     "the stops run in order and never darken on the way down")
        let shallow = NotchGlassSeam.stops(height: 20, seamHeight: strip, openness: 1)
        suite.expect(!shallow.isEmpty && shallow.allSatisfy { $0.location >= 0 && $0.location <= 1 && $0.opacity == 1 },
                     "an island no taller than its strip is all seam")
        suite.expect(NotchGlassSeam.stops(height: 0, seamHeight: strip, openness: 1).allSatisfy { $0.opacity == 1 }
                     && NotchGlassSeam.stops(height: .nan, seamHeight: strip, openness: 1).allSatisfy { $0.opacity == 1 },
                     "no height to draw in leaves it black")
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
        suite.expect(glass.contains("Glass.regular.tint(tinted).interactive(interactive && !reduceMotion)")
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
