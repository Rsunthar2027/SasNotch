// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import AppKit
import Combine
import SwiftUI

/// The light or dark appearance the app's windows have. The island's panel
/// stays dark for its black and frosted surfaces; open on Liquid Glass it
/// follows this instead, as Apple's own glass does.
final class NotchSystemAppearance: ObservableObject {
    static let shared = NotchSystemAppearance()

    @Published private(set) var scheme: ColorScheme
    private var subscription: AnyCancellable?

    private init() {
        scheme = Self.scheme(of: NSApplication.shared.effectiveAppearance)
        subscription = NSApplication.shared.publisher(for: \.effectiveAppearance, options: [.new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] appearance in
                guard let self else { return }
                let next = Self.scheme(of: appearance)
                if next != self.scheme { self.scheme = next }
            }
    }

    private static func scheme(of appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}

private struct NotchGlassSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

private struct NotchTileRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = NotchGlassGeometry.tileRadius(surfaceRadius: 28)
}

private struct NotchGlassNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

private struct NotchGlassUnionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct NotchGlassIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

private struct NotchGlassNamesBySymbolKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The open island is on Liquid Glass, so what lies on it draws glass too.
    var notchGlassSurface: Bool {
        get { self[NotchGlassSurfaceKey.self] }
        set { self[NotchGlassSurfaceKey.self] = newValue }
    }

    /// The radius a tile laid in the current container takes so its corners
    /// stay concentric with it: the open island's, or a padded card's.
    var notchTileRadius: CGFloat {
        get { self[NotchTileRadiusKey.self] }
        set { self[NotchTileRadiusKey.self] = newValue }
    }

    /// The island's glass identities, so controls in its top row and on its
    /// pages flow into each other as the island changes.
    var notchGlassNamespace: Namespace.ID? {
        get { self[NotchGlassNamespaceKey.self] }
        set { self[NotchGlassNamespaceKey.self] = newValue }
    }

    /// Buttons side by side that read as one capsule on glass.
    var notchGlassUnion: String? {
        get { self[NotchGlassUnionKey.self] }
        set { self[NotchGlassUnionKey.self] = newValue }
    }

    /// The identity a tile keeps while its own glyph and title change with
    /// its state, set where the tile is placed.
    var notchGlassTileID: String? {
        get { self[NotchGlassIDKey.self] }
        set { self[NotchGlassIDKey.self] = newValue }
    }

    /// In the island's top row each button's symbol is its identity. Lists
    /// repeat their symbols from row to row, so their buttons go without one.
    var notchGlassNamesBySymbol: Bool {
        get { self[NotchGlassNamesBySymbolKey.self] }
        set { self[NotchGlassNamesBySymbolKey.self] = newValue }
    }
}

#if compiler(>=6.2)
@available(macOS 26, *)
extension NotchGlassStyle {
    var glass: Glass {
        switch self {
        case .light, .clear: return .clear
        case .regular: return .regular
        }
    }
}
#endif

extension ColorScheme {
    /// Solid text and marks where a hierarchical style cannot go: the
    /// number on a chosen day's disc, and the disc itself.
    var notchInk: Color { self == .dark ? .white : .black }
    var notchPaper: Color { self == .dark ? .black : .white }
}

/// The tints the island's glass takes, only for what is on or chosen.
enum NotchGlassTint {
    /// A selected tab or a chosen control: a brighter lens on dark glass, a
    /// deeper one on light glass, in the island's own monochrome.
    static var selection: Color { Color.primary.opacity(0.22) }
}

/// The island's motion for glass that merges and parts: a spring that settles
/// with a little give. Reduce Motion moves nothing: lenses materialize in
/// place and the island's content fades, as its window already does.
enum NotchGlassMotion {
    static func morph(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .bouncy(duration: 0.42, extraBounce: 0)
    }
}

/// Adjacent glass that should blend as it moves: Apple's container on
/// macOS 26, the content alone before it. One view goes in, laid out as is.
struct NotchGlassGroup<Content: View>: View {
    /// The distance under which neighbouring lenses start to merge; the
    /// layout's own gap keeps them apart at rest.
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
#if compiler(>=6.2)
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
#else
        content()
#endif
    }
}

/// A control's lens on the open island: Apple's interactive glass on
/// macOS 26, which flexes under the pointer, tinted only while the control
/// is on. The black and frosted islands, Reduce Transparency and older
/// systems keep the quiet fills those islands have always drawn, solid
/// under Reduce Transparency.
struct NotchGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    /// White over the black island, as a share of full white.
    var offGlass: Double = 0
    var offGlassStroke: Double = 0
    var offGlassStrokeWidth: CGFloat = 0.5
    /// A fill of its own off the glass, such as a tile's colour while it is on.
    var offGlassColor: Color? = nil
    /// The colour of an active state: a selected tab, an on toggle.
    var tint: Color? = nil
    var interactive = true
    var selected = false
    var glassID: String? = nil
    var unionID: String? = nil
    @AppStorage(DefaultsKey.notchGlassStyle) private var glassStyle = NotchGlassStyle.fallback.rawValue
    @Environment(\.notchGlassSurface) private var glassSurface
    @Environment(\.notchGlassNamespace) private var namespace
    @Environment(\.notchGlassUnion) private var environmentUnion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26, *), glassSurface, !reduceTransparency {
            content
                .glassEffect(glass, in: shape)
                .modifier(NotchGlassIdentity(id: glassID, union: unionID ?? environmentUnion, namespace: namespace,
                                             reduceMotion: reduceMotion))
                .overlay { outline }
        } else {
            solid(content)
        }
#else
        solid(content)
#endif
    }

    private var increased: Bool { contrast == .increased }

#if compiler(>=6.2)
    @available(macOS 26, *)
    private var glass: Glass {
        let tone: Color = scheme == .dark ? .black : .white
        let style = NotchGlassStyle.sanitized(glassStyle)
        let dimming = NotchGlassContrast.tileTintOpacity(increasedContrast: increased, style: style)
        let tinted = tint ?? (dimming > 0 ? tone.opacity(dimming) : nil)
        // Reduce Motion keeps the lens still under the pointer.
        return style.glass.tint(tinted).interactive(interactive && !reduceMotion)
    }
#endif

    /// Increase Contrast outlines every lens; otherwise the glass's own edge
    /// is its outline.
    @ViewBuilder private var outline: some View {
        if increased {
            shape.strokeBorder(.primary.opacity(NotchGlassContrast.strokeOpacity(increasedContrast: true, selected: selected)),
                               lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    /// Off the glass the island is black, so a share of white over it reads
    /// as that grey; Reduce Transparency paints the grey itself.
    private func solid(_ content: Content) -> some View {
        let fill = offGlassColor ?? (reduceTransparency ? Color(white: offGlass) : Color.white.opacity(offGlass))
        let stroke = increased ? max(offGlassStroke, NotchGlassContrast.strokeOpacity(increasedContrast: true, selected: selected))
            : offGlassStroke
        return content
            .background(offGlassColor != nil || offGlass > 0 ? fill : .clear, in: shape)
            .overlay {
                if stroke > 0 {
                    shape.strokeBorder(.white.opacity(stroke), lineWidth: increased ? max(1, offGlassStrokeWidth) : offGlassStrokeWidth)
                        .allowsHitTesting(false)
                }
            }
    }
}

#if compiler(>=6.2)
/// Gives a lens its identity in the island's namespace, so it morphs into
/// the lens that takes its place, and joins the capsule it belongs to.
/// Reduce Motion lets lenses fade in and out instead of morphing.
@available(macOS 26, *)
private struct NotchGlassIdentity: ViewModifier {
    let id: String?
    let union: String?
    let namespace: Namespace.ID?
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if let namespace {
            content
                .glassEffectID(id, in: namespace)
                .glassEffectUnion(id: union, namespace: namespace)
                .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
        } else {
            content.glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
        }
    }
}
#endif

extension View {
    func notchGlass<S: InsettableShape>(_ shape: S, offGlass: Double = 0, offGlassStroke: Double = 0,
                                        offGlassStrokeWidth: CGFloat = 0.5, offGlassColor: Color? = nil,
                                        tint: Color? = nil, interactive: Bool = true, selected: Bool = false,
                                        id: String? = nil, union: String? = nil) -> some View {
        modifier(NotchGlassBackground(shape: shape, offGlass: offGlass, offGlassStroke: offGlassStroke,
                                      offGlassStrokeWidth: offGlassStrokeWidth, offGlassColor: offGlassColor, tint: tint,
                                      interactive: interactive, selected: selected, glassID: id, unionID: union))
    }
}
