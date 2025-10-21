// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveStreamingCore",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "LiveStreamingCore",
            targets: ["LiveStreamingCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/HaishinKit/HaishinKit.swift", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "LiveStreamingCore",
            dependencies: [
                .product(name: "HaishinKit", package: "HaishinKit.swift")
            ],
            path: "Sources",
            exclude: [],
            resources: []
        ),
        .testTarget(
            name: "LiveStreamingCoreTests",
            dependencies: ["LiveStreamingCore"],
            path: "Tests"
        ),
    ]
)
