// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignalEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SignalEngine",
            targets: ["SignalEngine"]
        )
    ],
    targets: [
        .target(
            name: "SignalEngine",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SignalEngineTests",
            dependencies: ["SignalEngine"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
