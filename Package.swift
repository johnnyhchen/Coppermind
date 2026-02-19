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
            name: "CoppermindCoreTests",
            dependencies: ["CoppermindCore"],
            path: "CoppermindTests/CoreTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "CoppermindAudioTests",
            dependencies: ["CoppermindCore"],
            path: "CoppermindTests/AudioTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "CoppermindEngineTests",
            dependencies: ["CoppermindCore"],
            path: "CoppermindTests/EngineTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "CoppermindIntegrationTests",
            dependencies: ["CoppermindCore"],
            path: "CoppermindTests/IntegrationTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
