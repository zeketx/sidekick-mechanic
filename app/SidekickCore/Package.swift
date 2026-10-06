// swift-tools-version: 6.0
// Verified on Ubuntu 24.04 x86_64 with Swift 6.4 (swift-6.4-RELEASE).

import PackageDescription

let package = Package(
    name: "SidekickCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SidekickCore",
            targets: ["SidekickCore"]
        ),
    ],
    targets: [
        .target(
            name: "SidekickCore",
            resources: [
                .copy("Resources/Scenarios"),
                .copy("Resources/demo_bay_photos.json"),
            ]
        ),
        .testTarget(
            name: "SidekickCoreTests",
            dependencies: ["SidekickCore"]
        ),
    ]
)
