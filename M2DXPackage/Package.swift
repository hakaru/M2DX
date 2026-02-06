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
        // MIDI2Kit for MIDI 2.0 support (local development)
        .package(path: "../../MIDI2Kit"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "M2DXCore",
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
                .product(name: "MIDI2Kit", package: "MIDI2Kit"),
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
