// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 SasNotch contributors

import Foundation

/// The layered Icon Composer icon: actool is absent from a Command Line Tools
/// build, so this pins what can be known without it. The bundle parses, names
/// only files it carries, answers each appearance, keeps the master's
/// artwork, and a build without actool still ships the plain icon.
enum AppIconBundleTests {
    private static func source(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    static func run(_ suite: TestSuite) {
        let bundle = "Branding/AppIcon.icon"
        let data = FileManager.default.contents(atPath: "\(bundle)/icon.json") ?? Data()
        let icon = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let groups = icon["groups"] as? [[String: Any]] ?? []
        let layers = groups.flatMap { $0["layers"] as? [[String: Any]] ?? [] }
        let images = layers.compactMap { $0["image-name"] as? String }
        suite.expect(images.sorted() == ["background.svg", "sasquatch-body.svg", "sasquatch-face.svg", "sasquatch-features.svg"],
                     "the icon has a background layer and the sasquatch's foreground layers")
        suite.expect(images.allSatisfy { FileManager.default.fileExists(atPath: "\(bundle)/Assets/\($0)") },
                     "every layer's image is in the bundle")
        suite.expect((groups.first?["layers"] as? [[String: Any]])?.first?["image-name"] as? String == "sasquatch-features.svg"
                     && (groups.last?["layers"] as? [[String: Any]])?.last?["image-name"] as? String == "background.svg",
                     "Icon Composer lists layers front to back: the face's features first, the background last")
        let fills = icon["fill-specializations"] as? [[String: Any]] ?? []
        let appearances = Set(fills.compactMap { $0["appearance"] as? String })
        suite.expect(fills.contains { $0["appearance"] == nil } && appearances == ["dark", "tinted"],
                     "the icon answers default and dark, and tinted, which macOS also draws its clear icons from")
        for layer in layers where layer["image-name"] as? String != "background.svg" {
            let layerAppearances = Set((layer["fill-specializations"] as? [[String: Any]] ?? [])
                .compactMap { $0["appearance"] as? String })
            suite.expect(layerAppearances == ["dark", "tinted"],
                         "\(layer["name"] as? String ?? "a layer") has its own dark and tinted colour")
        }
        let platforms = icon["supported-platforms"] as? [String: Any]
        suite.expect(platforms?["squares"] as? [String] == ["macOS"], "the icon is made for macOS")

        let master = source("Branding/sasquatch-icon.svg")
        for (file, path) in [("sasquatch-body.svg", #"d="M 110 960"#), ("sasquatch-face.svg", #"d="M 398 474"#),
                             ("sasquatch-features.svg", #"d="M 474 620"#)] {
            let layer = source("\(bundle)/Assets/\(file)")
            suite.expect(master.contains(path) && layer.contains(path), "\(file) keeps the master icon's artwork")
            // Icon Composer's canvas is the icon's own square, where the
            // master leaves macOS's margins around its tile.
            suite.expect(layer.contains(#"viewBox="100 100 824 824""#), "\(file) fills the icon's canvas")
        }

        let build = source("build.sh")
        suite.expect(build.contains("xcrun --find actool 2>/dev/null")
                     && build.contains("Branding/AppIcon.icon")
                     && build.contains("--app-icon AppIcon"),
                     "a toolchain with actool compiles the layered icon")
        suite.expect(build.contains("swift Tools/MakeIcon.swift build/AppIcon.iconset")
                     && build.contains(#"cp build/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns""#)
                     && build.contains("rm -f build/Assets.car"),
                     "the plain icon always ships, and a stale catalog never does")
        let plist = FileManager.default.contents(atPath: "Resources/Info.plist")
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
        suite.expect(plist?["CFBundleIconName"] as? String == "AppIcon" && plist?["CFBundleIconFile"] as? String == "AppIcon",
                     "the bundle names the catalog's icon and the plain one alike, so either can serve")
    }
}
