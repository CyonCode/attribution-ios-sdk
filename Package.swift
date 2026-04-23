// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AttributionKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "AttributionKit", targets: ["AttributionKit"])
    ],
    targets: [
        .target(name: "AttributionKit", path: "Sources/AttributionKit"),
        .testTarget(name: "AttributionKitTests", dependencies: ["AttributionKit"])
    ]
)
