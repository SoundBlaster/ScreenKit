// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "ScreenKit",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(name: "ScreenKit", targets: ["ScreenKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0")
    ],
    targets: [
        .macro(
            name: "ScreenKitMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ]
        ),
        .target(name: "ScreenKit", dependencies: ["ScreenKitMacros"]),
        .testTarget(name: "ScreenKitTests", dependencies: ["ScreenKit"]),
        .testTarget(
            name: "ScreenKitMacroTests",
            dependencies: [
                "ScreenKitMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        )
    ]
)
