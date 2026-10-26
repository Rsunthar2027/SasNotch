// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Modified for SasNotch by SasNotch contributors, 2026

// Opens in Xcode (File › Open… › Package.swift) and builds with
// `xcodebuild -scheme SasNotch`. Releases are built by build.sh, which
// assembles, signs and packages the .app bundle with the Command Line Tools.

import PackageDescription

let package = Package(
    name: "SasNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Keep in step with SPARKLE_VERSION in build.sh.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .systemLibrary(
            name: "HIDEventSystem",
            path: "Sources/HIDEventSystem"
        ),
        .systemLibrary(
            name: "VMStatisticsCompat",
            path: "Sources/VMStatisticsCompat"
        ),
        .executableTarget(
            name: "SasNotch",
            dependencies: [
                "VMStatisticsCompat",
                "HIDEventSystem",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/SasNotch"
        )
    ]
)
