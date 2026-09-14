// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ScreenKit",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "ScreenKit", targets: ["ScreenKit"])
    ],
    targets: [
        .target(name: "ScreenKit"),
        .testTarget(name: "ScreenKitTests", dependencies: ["ScreenKit"])
    ]
)
