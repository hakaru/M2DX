// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "M2DXPackage",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "M2DXFeature",
            targets: ["M2DXFeature"]
        ),
        .library(
            name: "M2DXCore",
            targets: ["M2DXCore"]
        ),
    ],
    dependencies: [
        // MIDIKit for MIDI 2.0 support
        .package(url: "https://github.com/orchetect/MIDIKit.git", from: "0.9.0"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "M2DXCore",
            dependencies: [
                .product(name: "MIDIKit", package: "MIDIKit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "M2DXCoreTests",
            dependencies: ["M2DXCore"]
        ),

        // MARK: - Feature (UI)
        .target(
            name: "M2DXFeature",
            dependencies: [
                "M2DXCore",
                .product(name: "MIDIKit", package: "MIDIKit"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "M2DXFeatureTests",
            dependencies: ["M2DXFeature"]
        ),
    ]
)
