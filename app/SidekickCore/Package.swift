// swift-tools-version: 6.0
// Verified on Ubuntu 24.04 x86_64 with Swift 6.4.0 (swift-6.4.0-RELEASE).

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
            name: "SidekickCore"
        ),
        .testTarget(
            name: "SidekickCoreTests",
            dependencies: ["SidekickCore"]
        ),
    ]
)
