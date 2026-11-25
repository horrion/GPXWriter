// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "GPXWriter",
    products: [
        .library(name: "GPXWriter", targets: ["GPXWriter"])
    ],
    targets: [
        .target(name: "GPXWriter"),
        .testTarget(name: "GPXWriterTests", dependencies: ["GPXWriter"])
    ]
)
