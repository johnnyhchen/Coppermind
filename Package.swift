// swift-tools-version: 6.0
// Coppermind — Root Package (Monorepo)

import PackageDescription

let package = Package(
    name: "Coppermind",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "CoppermindCore",
            targets: ["CoppermindCore"]
        ),
        .executable(
            name: "CoppermindMac",
            targets: ["CoppermindMac"]
        ),
        .executable(
            name: "CoppermindIOS",
            targets: ["CoppermindIOS"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CoppermindCore",
            dependencies: [],
            path: "CoppermindCore/Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "CoppermindMac",
            dependencies: ["CoppermindCore"],
            path: "CoppermindMac/Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "CoppermindIOS",
            dependencies: ["CoppermindCore"],
            path: "CoppermindIOS/Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "CoppermindTests",
            dependencies: ["CoppermindCore"],
            path: "CoppermindTests/Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
