// swift-tools-version:5.10
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright 2026 Zack Bleach. See LICENSE.md.
import PackageDescription

// "12 Step Sync": a small Mac app that points the desktop 12 Step Editor at iCloud Drive (and
// back), so the iOS app can share its presets. It replaces the two .command scripts in
// Tools/mac-sync with the same steps behind a window. Build the .app with ./build-app.sh.
let package = Package(
    name: "SyncSetup",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SyncCore"),
        .executableTarget(name: "SyncSetup", dependencies: ["SyncCore"]),
        .testTarget(name: "SyncCoreTests", dependencies: ["SyncCore"]),
    ]
)
